// MoonAnime's episode guide for Miki Miki's episode list. ADD-ON for the existing backend (functions/src):
//   1. copy this file to functions/src/guide.ts; in functions/ run:  npm install sharp
//   2. in functions/src/index.ts add the line:  export { guide, guideThumb } from "./guide";
//   3. MoonAnime's regular API key (the X-API-KEY one, not the Premium key):  firebase functions:secrets:set MOON_API_KEY
//   4. in firebase.json "hosting.rewrites" add (next to the others):
//        { "source": "/api/guide", "function": { "functionId": "guide", "region": "europe-west1" } },
//        { "source": "/api/guideThumb", "function": { "functionId": "guideThumb", "region": "europe-west1" } }
//   5. firebase deploy --only functions:guide,functions:guideThumb,hosting
// `guide?mal=<MyAnimeList id>` (an app session, `x-session`): the title's episodes from MoonAnime
// (`/api/7.0/anime/{mal_id}/schedule`, its `episode_guide`): Ukrainian titles, lengths, filler / recap marks,
// descriptions and stills, kept in Firestore (`guide/{mal}`) for a day while the title airs and for a week after. So
// MoonAnime's key stays on the server (MoonAnime asks for that) and MoonAnime is asked once for everyone, not by every
// phone. MoonAnime's stills are 1920×1080 lossless WebP, about 1 MB each: `guideThumb?u=…&s=…` turns one into a
// 320×180 WebP (~15 KB) that Hosting's CDN keeps for a month. The address is signed by `guide`, so it is no open proxy.
import { onRequest, Request } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getApps, initializeApp } from "firebase-admin/app";
import { createHash, createHmac, timingSafeEqual } from "crypto";
import type { Response } from "express";
import sharp from "sharp";

if (getApps().length === 0) initializeApp();
const db = getFirestore();

const REGION = "europe-west1";
const MOON_API = "https://api.moonanime.art";
const MOON_API_KEY = defineSecret("MOON_API_KEY");
const DAY = 86_400_000;
/** One document per title stays well below Firestore's 1 MiB: descriptions go first when a long series is too big */
const MAX_BYTES = 700_000;

const hash = (s: string) => createHash("sha256").update(s).digest("hex");

/** The signature of a still's address (`guideThumb` makes only what `guide` gave out) */
const sign = (url: string) => createHmac("sha256", MOON_API_KEY.value()).update(url).digest("hex").slice(0, 24);

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
  if (!(await rateLimit(`guide:${sid}`, 60))) { res.status(429).json({ error: "slow_down" }); return null; }
  return sid;
}

/** «Серія 5», «Episode 5»: a stand-in, not a title */
const standIn = /^\s*(серія|серiя|епізод|episode)\s*\d+\s*$/i;
/** MoonAnime's stills live on its CDN: s1.mooncdn.wtf, s2.mooncdn.net … */
const moonCdn = /^s\d+\.mooncdn\.[a-z]+$/;

type MoonEpisode = {
  episode?: number;
  title?: string | null;
  thumb_url?: string | null;
  duration?: number | string | null; // seconds, as a string: "1420"
  description?: string | null;
  filler?: boolean;
  recap?: boolean;
  upcoming?: boolean;
  estimated_air_at?: string | null;
};
type MoonGuide = { episode_guide?: { season?: number; episodes?: MoonEpisode[] }[] };

/** An episode for the app: `t` title, `d` seconds, `a` description, `i` the still's path (`guideThumb`), `f` / `r` filler / recap */
type Ep = { t?: string; d?: number; a?: string; i?: string; f?: 1; r?: 1 };

/** MoonAnime's `episode_guide` by episode number, and whether the title still airs. A number found in several seasons is
 * left out: which episode it is cannot be told */
export function episodesOf(data: MoonGuide, now = Date.now()): { eps: Record<string, Ep>; airing: boolean } {
  const all = (data.episode_guide ?? []).flatMap((s) => s.episodes ?? []);
  const seen = new Map<number, number>();
  for (const e of all) if (typeof e.episode === "number") seen.set(e.episode, (seen.get(e.episode) ?? 0) + 1);
  const eps: Record<string, Ep> = {};
  let airing = false;
  for (const e of all) {
    const n = e.episode;
    if (typeof n !== "number" || n < 1 || seen.get(n) !== 1) continue;
    const at = e.estimated_air_at ? Date.parse(e.estimated_air_at) : NaN;
    if (e.upcoming || (!Number.isNaN(at) && now - at < 30 * DAY)) airing = true;
    if (e.upcoming) continue;
    const ep: Ep = {};
    const t = (e.title ?? "").trim();
    if (t && !standIn.test(t)) ep.t = t;
    const d = Number(e.duration ?? NaN);
    if (Number.isFinite(d) && d > 0) ep.d = Math.round(d);
    const a = (e.description ?? "").trim();
    if (a) ep.a = a.length > 400 ? `${a.slice(0, 400)}…` : a;
    if (e.filler) ep.f = 1;
    if (e.recap) ep.r = 1;
    try {
      const u = new URL(e.thumb_url ?? "");
      if (u.protocol === "https:" && moonCdn.test(u.hostname)) ep.i = `/api/guideThumb?u=${encodeURIComponent(u.href)}&s=${sign(u.href)}`;
    } catch {
      // no still
    }
    if (Object.keys(ep).length > 0) eps[String(n)] = ep;
  }
  if (JSON.stringify(eps).length > MAX_BYTES) for (const ep of Object.values(eps)) delete ep.a;
  return { eps, airing };
}

export const guide = onRequest({ region: REGION, cors: false, maxInstances: 5, secrets: [MOON_API_KEY] }, async (req, res) => {
  if (req.method !== "GET") { res.status(405).json({ error: "method" }); return; }
  if (!(await requireSession(req, res))) return;
  const mal = String(req.query.mal ?? "");
  if (!/^\d{1,7}$/.test(mal)) { res.status(400).json({ error: "bad_mal" }); return; }
  const ref = db.collection("guide").doc(mal);
  const kept = (await ref.get()).data();
  if (kept && kept.until.toMillis() > Date.now()) { res.json({ mal: Number(mal), eps: kept.eps }); return; }
  try {
    const r = await fetch(`${MOON_API}/api/7.0/anime/${mal}/schedule`, {
      headers: { "X-API-KEY": MOON_API_KEY.value(), Accept: "application/json" },
      signal: AbortSignal.timeout(15_000),
    });
    if (r.status === 404) {
      // MoonAnime does not have the title: asked again in a few days
      await ref.set({ eps: {}, until: Timestamp.fromMillis(Date.now() + 3 * DAY) });
      res.json({ mal: Number(mal), eps: {} });
      return;
    }
    const body = (await r.json()) as { status?: string; data?: MoonGuide };
    if (!r.ok || body.status !== "success" || !body.data) throw new Error(`MoonAnime ${r.status}`);
    const { eps, airing } = episodesOf(body.data);
    await ref.set({ eps, until: Timestamp.fromMillis(Date.now() + (airing ? DAY : 7 * DAY)) });
    res.json({ mal: Number(mal), eps });
  } catch (e) {
    console.warn(`guide ${mal}: ${e}`);
    // MoonAnime cannot be reached: what was kept, however old
    if (kept) { res.json({ mal: Number(mal), eps: kept.eps, stale: true }); return; }
    res.status(502).json({ error: "moon_unreachable" });
  }
});

export const guideThumb = onRequest(
  { region: REGION, cors: false, maxInstances: 5, memory: "512MiB", timeoutSeconds: 30, secrets: [MOON_API_KEY] },
  async (req, res) => {
    const u = String(req.query.u ?? "");
    const want = Buffer.from(sign(u));
    const got = Buffer.from(String(req.query.s ?? ""));
    let url: URL;
    try {
      url = new URL(u);
    } catch {
      res.status(400).end();
      return;
    }
    if (url.protocol !== "https:" || !moonCdn.test(url.hostname) || want.length !== got.length || !timingSafeEqual(want, got)) {
      res.status(403).end();
      return;
    }
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(20_000) });
      if (!r.ok || !(r.headers.get("content-type") ?? "").startsWith("image/")) { res.status(404).end(); return; }
      const small = await sharp(Buffer.from(await r.arrayBuffer())).resize(320, 180, { fit: "cover" }).webp({ quality: 70 }).toBuffer();
      // Hosting's CDN keeps it: the function runs once per still, not once per viewer
      res.set("Cache-Control", "public, max-age=2592000, s-maxage=2592000, immutable").type("image/webp").send(small);
    } catch (e) {
      console.warn(`guideThumb: ${e}`);
      res.status(502).end();
    }
  },
);
