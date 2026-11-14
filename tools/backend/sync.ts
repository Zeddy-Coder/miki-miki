// Settings / theme / position sync for Miki Miki. ADD-ON for the existing backend (functions/src):
//   1. copy this file to functions/src/sync.ts
//   2. in functions/src/index.ts add the line:  export { syncGet, syncPut } from "./sync";
//   3. in firebase.json "hosting.rewrites" add (next to the others):
//        { "source": "/api/syncGet", "function": { "functionId": "syncGet", "region": "europe-west1" } },
//        { "source": "/api/syncPut", "function": { "functionId": "syncPut", "region": "europe-west1" } }
//   4. firebase deploy --only functions,hosting
// The account is the Hikka user: the client sends its Hikka token (`x-hikka-auth`), the server asks Hikka who it is
// and stores one document per user in `sync/{sha256("hikka:" + username)}`. The token itself is never stored.
import { onRequest, Request } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getApps, initializeApp } from "firebase-admin/app";
import { createHash } from "crypto";
import type { Response } from "express";

if (getApps().length === 0) initializeApp();
const db = getFirestore();

const REGION = "europe-west1";
const HIKKA_API = "https://api.hikka.io";
const MAX_BYTES = 200_000; // one document, well below the Firestore 1 MiB limit
const base = { region: REGION, cors: false, maxInstances: 5 } as const;

const hash = (s: string) => createHash("sha256").update(s).digest("hex");

async function rateLimit(key: string, limit: number): Promise<boolean> {
  const ref = db.collection("limits").doc(hash(key));
  const minute = Math.floor(Date.now() / 60000);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.data();
    const count = d && d.minute === minute ? d.count + 1 : 1;
    tx.set(ref, { minute, count, expireAt: new Date(Date.now() + 3600_000) });
    return count <= limit;
  });
}

/** App session (same rules as in index.ts) */
async function requireSession(req: Request, res: Response): Promise<string | null> {
  const sid = String(req.get("x-session") ?? "");
  if (!/^[a-f0-9]{48}$/.test(sid)) { res.status(401).json({ error: "no_session" }); return null; }
  const snap = await db.collection("sessions").doc(hash(sid)).get();
  const d = snap.data();
  if (!d || d.expiresAt.toMillis() < Date.now()) { res.status(401).json({ error: "bad_session" }); return null; }
  if (!(await rateLimit(`sync:${sid}`, 30))) { res.status(429).json({ error: "slow_down" }); return null; }
  return sid;
}

/** Who owns this Hikka token: the user's name, or a 401 */
async function hikkaUser(req: Request, res: Response): Promise<string | null> {
  const token = String(req.get("x-hikka-auth") ?? "");
  if (!/^[\w.\-]{16,200}$/.test(token)) { res.status(401).json({ error: "no_hikka_token" }); return null; }
  const r = await fetch(`${HIKKA_API}/user/me`, { headers: { auth: token } });
  if (!r.ok) { res.status(401).json({ error: "bad_hikka_token" }); return null; }
  const me = (await r.json()) as { username?: string };
  if (!me.username) { res.status(401).json({ error: "bad_hikka_token" }); return null; }
  return me.username;
}

const docOf = (username: string) => db.collection("sync").doc(hash(`hikka:${username}`));

/** GET /syncGet → { updated: ms, data: { key: { v, t } } } (updated 0 = nothing stored yet) */
export const syncGet = onRequest(base, async (req, res) => {
  if (req.method !== "GET") { res.status(405).end(); return; }
  if (!(await requireSession(req, res))) return;
  const user = await hikkaUser(req, res);
  if (!user) return;
  const snap = await docOf(user).get();
  const d = snap.data();
  res.set("cache-control", "no-store");
  res.json({ updated: d?.updated ?? 0, data: d ? JSON.parse(d.json) : {} });
});

/** POST /syncPut { data: { key: { v, t } } } → { updated }. The client merges by per-key time, the server just stores. */
export const syncPut = onRequest(base, async (req, res) => {
  if (req.method !== "POST") { res.status(405).end(); return; }
  if (!(await requireSession(req, res))) return;
  const user = await hikkaUser(req, res);
  if (!user) return;
  const data = req.body?.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) { res.status(400).json({ error: "bad_request" }); return; }
  for (const [k, e] of Object.entries<any>(data)) {
    if (!/^[\w:#.\-\/]{1,200}$/.test(k) || !e || typeof e !== "object" || typeof e.t !== "number") {
      res.status(400).json({ error: "bad_entry" }); return;
    }
  }
  const json = JSON.stringify(data);
  if (Buffer.byteLength(json) > MAX_BYTES) { res.status(413).json({ error: "too_big" }); return; }
  const updated = Date.now();
  await docOf(user).set({ json, updated, saved: FieldValue.serverTimestamp(), app: String(req.body?.app ?? "").slice(0, 32) });
  res.json({ updated });
});
