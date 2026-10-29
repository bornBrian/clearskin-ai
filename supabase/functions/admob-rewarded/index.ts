// GET /functions/v1/admob-rewarded  (called by Google AdMob, not the app)
//
// AdMob server-side verification (SSV) for the "watch a video for one more
// scan" reward. When a user finishes a rewarded ad, Google calls this URL
// with the reward details signed by Google's ECDSA key. Only a valid
// signature mints a scan credit, so a patched app that skips the ad (or
// fakes the reward callback on the device) gets nothing.
//
// Set this URL as the rewarded ad unit's "Server-side verification" callback
// in the AdMob console. The app passes the Supabase user id as the SSV
// user id.

import { adminClient, intEnv } from "../_shared/common.ts";
import { base64Decode, ecdsaDerToRaw } from "../_shared/encoding.ts";

const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const MAX_AGE_MS = 60 * 60 * 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

let keyCache: { keys: Map<string, CryptoKey>; at: number } | undefined;

async function verifierKey(id: string): Promise<CryptoKey | undefined> {
  if (!keyCache || Date.now() - keyCache.at > 6 * 60 * 60 * 1000 || !keyCache.keys.has(id)) {
    const res = await fetch(KEYS_URL);
    if (!res.ok) throw new Error(`AdMob keys ${res.status}`);
    const body = await res.json() as { keys: { keyId: number; base64: string }[] };
    const keys = new Map<string, CryptoKey>();
    for (const k of body.keys) {
      const der = Uint8Array.from(atob(k.base64), (c) => c.charCodeAt(0));
      keys.set(
        String(k.keyId),
        await crypto.subtle.importKey("spki", der, { name: "ECDSA", namedCurve: "P-256" }, false, [
          "verify",
        ]),
      );
    }
    keyCache = { keys, at: Date.now() };
  }
  return keyCache.keys.get(id);
}

const ok = () => new Response("ok", { status: 200 });

Deno.serve(async (req) => {
  if (req.method !== "GET") return new Response("method not allowed", { status: 405 });
  const url = new URL(req.url);
  const query = url.search.slice(1);
  const at = query.indexOf("&signature=");
  // AdMob's console sends an unsigned ping when the URL is saved.
  if (at < 0) return ok();

  try {
    const params = url.searchParams;
    const signature = params.get("signature") ?? "";
    const keyId = params.get("key_id") ?? "";
    const key = await verifierKey(keyId);
    if (!key) return new Response("unknown key", { status: 400 });

    let raw: Uint8Array<ArrayBuffer>;
    try {
      // AdMob signs with DER-encoded ECDSA; WebCrypto wants raw r‖s.
      raw = ecdsaDerToRaw(base64Decode(signature), 32);
    } catch {
      return new Response("bad signature", { status: 400 });
    }
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      raw,
      new TextEncoder().encode(query.slice(0, at)),
    );
    if (!valid) {
      console.warn("AdMob SSV: bad signature");
      return new Response("bad signature", { status: 400 });
    }

    const userId = params.get("user_id") ?? "";
    const transactionId = params.get("transaction_id") ?? "";
    const timestamp = Number(params.get("timestamp"));
    // Genuine but for no account: the console's "verify URL" test sends no
    // user id. Acknowledge it (or AdMob won't save the URL); credit nothing.
    if (!UUID.test(userId)) return ok();
    if (!transactionId || transactionId.length > 200) {
      return new Response("bad params", { status: 400 });
    }
    if (!Number.isFinite(timestamp) || Date.now() - timestamp > MAX_AGE_MS) {
      return new Response("stale", { status: 400 });
    }

    const db = adminClient();
    const startOfDay = new Date(new Date().setUTCHours(0, 0, 0, 0)).toISOString();
    const { count, error: countErr } = await db.from("scan_credits")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("created_at", startOfDay);
    if (countErr) throw countErr;
    if ((count ?? 0) >= intEnv("REWARDED_SCANS_PER_DAY", 1)) {
      // Valid but over today's cap: acknowledge so AdMob doesn't retry.
      return ok();
    }

    // transaction_id is unique: a replayed callback inserts nothing.
    const { error } = await db.from("scan_credits").upsert(
      { user_id: userId, source: "rewarded_ad", transaction_id: transactionId },
      { onConflict: "transaction_id", ignoreDuplicates: true },
    );
    if (error) {
      // Unknown user (FK) or a DB problem. Logged; AdMob may retry.
      console.error("AdMob SSV insert failed", error.code);
      return new Response("error", { status: 500 });
    }
    return ok();
  } catch (err) {
    console.error("AdMob SSV failed", err);
    return new Response("error", { status: 500 });
  }
});
