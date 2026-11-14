// Push notifications about new episodes (FCM). Two pieces:
//   pushRegister  POST /pushRegister {token, follows: ["<hikka slug>|<mikai release id>", ...], enabled}
//                 the app tells which releases (title + dub the person chose) it follows; one document per device.
//   episodePush   every 30 minutes: ONE request to the Mikai releases feed for everybody, then matching in memory,
//                 so the cost does not grow with the number of users (a run with no new releases reads nothing else).
import { onRequest, Request } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getApps, initializeApp } from "firebase-admin/app";
import { defineSecret } from "firebase-functions/params";
import { createHash, timingSafeEqual } from "crypto";
import type { Response } from "express";

if (getApps().length === 0) initializeApp();
const db = getFirestore();

const REGION = "europe-west1";
const MIKAI_API = "https://api.mikai.me/public/v1";
const MAX_FOLLOWS = 400;
const MAX_PAGES = 6;
const DEVICE_TTL_MS = 90 * 24 * 3600 * 1000; // a device that has not re-registered for 90 days is forgotten
const base = { region: REGION, cors: false, maxInstances: 5 } as const;

const ADMIN_KEY = defineSecret("ADMIN_KEY");

const hash = (s: string) => createHash("sha256").update(s).digest("hex");

async function requireSession(req: Request, res: Response): Promise<string | null> {
  const sid = String(req.get("x-session") ?? "");
  if (!/^[a-f0-9]{48}$/.test(sid)) { res.status(401).json({ error: "no_session" }); return null; }
  const snap = await db.collection("sessions").doc(hash(sid)).get();
  const d = snap.data();
  if (!d || d.expiresAt.toMillis() < Date.now()) { res.status(401).json({ error: "bad_session" }); return null; }
  return sid;
}

/** POST /pushRegister: saves (or, with enabled=false / no follows, removes) this device's subscription */
export const pushRegister = onRequest(base, async (req, res) => {
  if (req.method !== "POST") { res.status(405).end(); return; }
  if (!(await requireSession(req, res))) return;
  const token = String(req.body?.token ?? "");
  if (!/^[\w:\-.]{40,400}$/.test(token)) { res.status(400).json({ error: "bad_token" }); return; }
  const follows: string[] = (Array.isArray(req.body?.follows) ? req.body.follows : [])
    .map((x: unknown) => String(x))
    .filter((x: string) => /^[^|\s]{1,200}\|[\w-]{1,100}$/.test(x))
    .slice(0, MAX_FOLLOWS);
  const ref = db.collection("devices").doc(hash(token));
  // A device with push on but no followed titles stays registered: it still receives announcements
  if (req.body?.enabled !== true) {
    await ref.delete();
    res.json({ ok: true, follows: 0 });
    return;
  }
  await ref.set({ token, follows, updated: FieldValue.serverTimestamp(), expireAt: new Date(Date.now() + DEVICE_TTL_MS) });
  res.json({ ok: true, follows: follows.length });
});

interface Row { slug: string; release: string; episode: number; team: string; kind: string; title: string; image: string | null; at: number }

function poster(images: any): string | null {
  const p = images?.poster;
  for (const size of ["medium", "big", "small"]) {
    const url = p?.[size]?.jpg ?? p?.[size]?.webp;
    if (typeof url === "string" && url.startsWith("https://")) return url;
  }
  return null;
}

async function fetchFeed(since: Date): Promise<Row[]> {
  const out: Row[] = [];
  let pages = 1;
  for (let page = 1; page <= pages && page <= MAX_PAGES; page++) {
    const url = `${MIKAI_API}/updates?since=${encodeURIComponent(since.toISOString())}&limit=100&page=${page}`;
    const key = process.env.MIKAI_KEY;
    const r = await fetch(url, { headers: { accept: "application/json", ...(key ? { "X-API-Key": key } : {}) } });
    if (!r.ok) throw new Error(`Mikai HTTP ${r.status}`);
    const j: any = await r.json();
    pages = Number(j?.pages) || 0;
    for (const x of j?.result ?? []) {
      const slug = x?.anime?.ids?.hikka;
      const ep = Number(x?.episode);
      if (typeof slug !== "string" || !x?.releaseId || !Number.isFinite(ep)) continue;
      const t = x.anime?.titles ?? {};
      out.push({
        slug, release: String(x.releaseId), episode: ep,
        team: String(x.teamName ?? ""), kind: x.kind === "sub" ? "sub" : "voice",
        title: String(t.ua ?? t.english ?? t.original ?? slug).slice(0, 120),
        image: poster(x.anime?.images),
        at: Date.parse(String(x.publishedAt)) || Date.now(),
      });
    }
  }
  return out;
}

/** Every 30 minutes: new releases → devices that follow them */
export const episodePush = onSchedule({ region: REGION, schedule: "every 30 minutes", timeoutSeconds: 120, maxInstances: 1 }, async () => {
  const metaRef = db.collection("meta").doc("push");
  const meta = (await metaRef.get()).data();
  const now = Date.now();
  // A small overlap catches records that appeared on the feed a bit after their time; repeats are cut by the `pushed` documents
  const since = new Date(meta?.since ? Number(meta.since) : now - 3600_000);
  let rows: Row[];
  try { rows = await fetchFeed(since); } catch (e) { console.warn("feed", String(e)); return; }
  await metaRef.set({ since: now - 10 * 60_000, ran: now });
  if (!rows.length) return;

  // Which of these were already announced (several runs overlap)
  const ids = rows.map((r) => hash(`${r.slug}|${r.release}|${r.episode}`));
  const seen = await db.getAll(...ids.map((id) => db.collection("pushed").doc(id)));
  const fresh = rows.filter((_, i) => !seen[i].exists);
  if (!fresh.length) return;

  // Devices: usually few documents; matching is done in memory
  const byKey = new Map<string, Row[]>();
  for (const r of fresh) { const k = `${r.slug}|${r.release}`; byKey.set(k, [...(byKey.get(k) ?? []), r]); }
  const devices = await db.collection("devices").get();
  const messages: { token: string; ref: FirebaseFirestore.DocumentReference; row: Row }[] = [];
  for (const d of devices.docs) {
    const data = d.data();
    const seenSlug = new Set<string>();
    for (const k of (data.follows as string[]) ?? []) {
      for (const row of byKey.get(k) ?? []) {
        // One notification per title and device in one run: the newest episode
        if (seenSlug.has(row.slug)) continue;
        seenSlug.add(row.slug);
        const newest = (byKey.get(k) ?? []).reduce((a, b) => (b.episode > a.episode ? b : a));
        messages.push({ token: data.token, ref: d.ref, row: newest });
      }
    }
  }
  const batch = db.batch();
  const expire = new Date(now + 7 * 24 * 3600 * 1000);
  fresh.forEach((r) => batch.set(db.collection("pushed").doc(hash(`${r.slug}|${r.release}|${r.episode}`)), { at: now, expireAt: expire }));
  await batch.commit();
  if (!messages.length) return;

  for (let i = 0; i < messages.length; i += 500) {
    const chunk = messages.slice(i, i + 500);
    // Data-only: the app's messaging service shows the notification itself AND keeps a copy for the "Сповіщення" tab
    // (a "notification" message would be drawn by the system without running the app's code)
    const res = await getMessaging().sendEach(chunk.map(({ token, row }) => ({
      token,
      data: {
        type: "episode",
        id: `${row.slug}|${row.release}|${row.episode}`,
        title: row.title,
        body: `Вийшла серія ${row.episode} · ${row.kind === "sub" ? "Субтитри" : "Озвучення"}: ${row.team}`,
        slug: row.slug,
        release: row.release,
        episode: String(row.episode),
        team: row.team,
        kind: row.kind,
        ...(row.image ? { image: row.image } : {}),
      },
      android: { priority: "high" as const },
    })));
    // Dead tokens (the app was removed) are dropped
    await Promise.all(res.responses.map(async (r, idx) => {
      const code = r.error?.code ?? "";
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") await chunk[idx].ref.delete();
    }));
    console.log(`push: sent ${res.successCount}, failed ${res.failureCount}`);
  }
});

/**
 * POST /pushAdmin (header x-admin-key = the ADMIN_KEY secret): a manual push for testing and announcements.
 *   {type: "episode" | "news" | "update", title, body, target?: "all" | "slug:<hikka slug>", slug?, image?, dryRun?}
 *   episode  looks like a real "new episode" notification (tap opens the title `slug`) - to check the whole chain
 *   news     a message from the developer (channel "news")
 *   update   "a new version is out" (channel "news")
 * target "slug:x" limits it to the devices that follow that title; the default is every registered device.
 * dryRun only counts the devices. Dead tokens are dropped, as in the scheduled job.
 */
export const pushAdmin = onRequest({ ...base, secrets: [ADMIN_KEY], maxInstances: 1 }, async (req, res) => {
  if (req.method !== "POST") { res.status(405).end(); return; }
  const given = Buffer.from(String(req.get("x-admin-key") ?? ""));
  const real = Buffer.from(ADMIN_KEY.value());
  if (given.length !== real.length || !timingSafeEqual(given, real)) { res.status(403).json({ error: "forbidden" }); return; }
  const type = String(req.body?.type ?? "news");
  if (!["episode", "news", "update"].includes(type)) { res.status(400).json({ error: "bad_type" }); return; }
  const title = String(req.body?.title ?? "").slice(0, 120);
  const body = String(req.body?.body ?? "").slice(0, 300);
  if (!title || !body) { res.status(400).json({ error: "title_and_body_required" }); return; }
  const slug = String(req.body?.slug ?? "").slice(0, 200);
  const image = typeof req.body?.image === "string" && req.body.image.startsWith("https://") ? req.body.image : null;
  const target = String(req.body?.target ?? "all");

  const devices = await db.collection("devices").get();
  const wanted = target.startsWith("slug:") ? target.slice(5) : null;
  const picked = devices.docs.filter((d) => !wanted || ((d.data().follows as string[]) ?? []).some((k) => k.startsWith(`${wanted}|`)));
  if (req.body?.dryRun === true || picked.length === 0) { res.json({ ok: true, devices: picked.length, sent: 0, dryRun: req.body?.dryRun === true }); return; }

  // Data-only (see episodePush); no "id": the app builds one, so every manual push is a separate entry in the tab
  const data: Record<string, string> = { type, title, body };
  if (slug) data.slug = slug;
  if (image) data.image = image;
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
      const code = x.error?.code ?? "";
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") await chunk[idx].ref.delete();
    }));
  }
  res.json({ ok: true, devices: picked.length, sent, failed });
});
