// The Miki Miki admin panel: only for the Hikka accounts in ADMINS (now ZEDDY). ADD-ON for the existing backend (functions/src):
//   1. copy this file to functions/src/admin.ts
//   2. in functions/src/index.ts add the line:  export { admin } from "./admin";
//   3. in firebase.json "hosting.rewrites" add (next to the others):
//        { "source": "/api/admin", "function": { "functionId": "admin", "region": "europe-west1" } }
//   4. firebase deploy --only functions,hosting
// Who asks is decided on the server: the app sends its session (`x-session`) and its Hikka token (`x-hikka-auth`), the
// server asks Hikka whose token it is and compares the name with ADMINS. No key lives in the app; the token is not stored.
//
// POST /admin {action, ...}
//   whoami                                                → { admin: true, username, devices }
//   push.count    {target}                                → { devices }
//   push.send     {type, title, body, target, slug?, image?} → { devices, sent, failed }
//   push.history                                          → { items: [{ at, by, type, title, body, target, slug, image, devices, sent, failed }] }
// target: "all" | "slug:<hikka slug>" (the devices that follow that title)
// type:   "news"    an announcement (with a slug the tap opens that title)
//         "update"  a new version is out (the tap opens the update window in the app)
//         "episode" looks like a real "new episode" notification, to check the whole chain (needs slug)
// Every send is written to `adminLog`. Dead tokens are dropped, as in the scheduled job (push.ts).
import { onRequest, Request } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getApps, initializeApp } from "firebase-admin/app";
import { createHash } from "crypto";
import type { Response } from "express";

if (getApps().length === 0) initializeApp();
const db = getFirestore();

const REGION = "europe-west1";
const HIKKA_API = "https://api.hikka.io";

/** Hikka usernames (lower case) that may use the panel */
const ADMINS = new Set(["zeddy"]);

const TYPES = ["news", "update", "episode"];
const SLUG = /^[A-Za-z0-9._\-]{1,160}$/;
const base = { region: REGION, cors: false, maxInstances: 2 } as const;

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
  if (!(await rateLimit(`admin:${sid}`, 30))) { res.status(429).json({ error: "slow_down" }); return null; }
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

/** The devices a target reaches: every registered one, or those that follow one title */
async function devicesFor(target: string): Promise<FirebaseFirestore.QueryDocumentSnapshot[] | null> {
  if (target !== "all" && !(target.startsWith("slug:") && SLUG.test(target.slice(5)))) return null;
  const all = await db.collection("devices").get();
  if (target === "all") return all.docs;
  const slug = target.slice(5);
  return all.docs.filter((d) => ((d.data().follows as string[]) ?? []).some((k) => k.startsWith(`${slug}|`)));
}

const DEAD = new Set(["messaging/registration-token-not-registered", "messaging/invalid-registration-token"]);

export const admin = onRequest(base, async (req, res) => {
  if (req.method !== "POST") { res.status(405).end(); return; }
  if (!(await requireSession(req, res))) return;
  const user = await hikkaUser(req, res);
  if (!user) return;
  if (!ADMINS.has(user.toLowerCase())) {
    console.warn(`admin: refused for ${user}`);
    res.status(403).json({ error: "not_admin" });
    return;
  }
  res.set("cache-control", "no-store");
  const action = String(req.body?.action ?? "");

  if (action === "whoami") {
    const count = await db.collection("devices").count().get();
    res.json({ admin: true, username: user, devices: count.data().count });
    return;
  }

  if (action === "push.count") {
    const picked = await devicesFor(String(req.body?.target ?? "all"));
    if (!picked) { res.status(400).json({ error: "bad_target" }); return; }
    res.json({ devices: picked.length });
    return;
  }

  if (action === "push.history") {
    const snap = await db.collection("adminLog").orderBy("at", "desc").limit(20).get();
    res.json({ items: snap.docs.map((d) => d.data()) });
    return;
  }

  if (action === "push.send") {
    if (!(await rateLimit(`admin-send:${user.toLowerCase()}`, 5))) { res.status(429).json({ error: "slow_down" }); return; }
    const type = String(req.body?.type ?? "news");
    if (!TYPES.includes(type)) { res.status(400).json({ error: "bad_type" }); return; }
    const title = String(req.body?.title ?? "").trim();
    const body = String(req.body?.body ?? "").trim();
    if (!title || !body) { res.status(400).json({ error: "title_and_body_required" }); return; }
    if (title.length > 120 || body.length > 300) { res.status(400).json({ error: "too_long" }); return; }
    const slug = String(req.body?.slug ?? "").trim();
    if (slug && !SLUG.test(slug)) { res.status(400).json({ error: "bad_slug" }); return; }
    if (type === "episode" && !slug) { res.status(400).json({ error: "slug_required" }); return; }
    const rawImage = String(req.body?.image ?? "").trim();
    if (rawImage && (!rawImage.startsWith("https://") || rawImage.length > 500)) { res.status(400).json({ error: "bad_image" }); return; }
    const target = String(req.body?.target ?? "all");
    const picked = await devicesFor(target);
    if (!picked) { res.status(400).json({ error: "bad_target" }); return; }

    // Data-only (see push.ts): the app's messaging service shows it and keeps a copy for the "Сповіщення" tab.
    // No "id": the app builds one, so every message is a separate entry there
    const data: Record<string, string> = { type, title, body };
    if (slug && type !== "update") data.slug = slug;
    if (rawImage) data.image = rawImage;
    let sent = 0, failed = 0;
    for (let i = 0; i < picked.length; i += 500) {
      const chunk = picked.slice(i, i + 500);
      const r = await getMessaging().sendEach(chunk.map((d) => ({
        token: d.data().token as string,
        data,
        android: { priority: "high" as const },
      })));
      sent += r.successCount; failed += r.failureCount;
      await Promise.all(r.responses.map(async (x, idx) => {
        if (DEAD.has(x.error?.code ?? "")) await chunk[idx].ref.delete();
      }));
    }
    const at = Date.now();
    await db.collection("adminLog").add({
      at, by: user, type, title, body, target, slug: data.slug ?? "", image: rawImage, devices: picked.length, sent, failed,
    });
    console.log(`admin: ${user} sent "${type}" to ${target}: ${sent} ok, ${failed} failed`);
    res.json({ devices: picked.length, sent, failed, at });
    return;
  }

  res.status(400).json({ error: "bad_action" });
});
