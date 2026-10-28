// POST /functions/v1/app-attest  { key_id, attestation, ts }
//
// Registers an iPhone install's App Attest key (see _shared/app_attest.ts).
// The app calls this once per install, then signs every AI call with the
// key. The attestation is bound to "<user id>|app-attest|<ts>", so one
// captured from another user or an hour ago is refused.
//
// 503 until APPLE_APP_ID is set; the app then simply sends no proof, which
// INTEGRITY_MODE decides about like a missing Play Integrity token.

import { z } from "npm:zod@4.6.7";
import { AttestError, appAttestConfigured, clientDataHash, verifyAttestation } from "../_shared/app_attest.ts";
import { adminClient, errorResponse, HttpError, intEnv, json, readJson, requireUser } from "../_shared/common.ts";

const MAX_SKEW_MS = 5 * 60 * 1000;

const RequestSchema = z.object({
  // Apple's key id: base64 of 32 bytes.
  key_id: z.string().regex(/^[A-Za-z0-9+/]{43}=$/),
  // A real attestation is ~5 KB of base64.
  attestation: z.string().min(100).max(12_000).regex(/^[A-Za-z0-9+/]+={0,2}$/),
  ts: z.number().int(),
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const userId = await requireUser(req);
    if (!appAttestConfigured()) {
      throw new HttpError(503, "not_configured", "App Attest isn't set up yet.");
    }
    const parsed = RequestSchema.safeParse(await readJson(req, 16_000));
    if (!parsed.success) throw new HttpError(400, "bad_request", "Invalid request.");
    const { key_id, attestation, ts } = parsed.data;
    if (Math.abs(Date.now() - ts) > MAX_SKEW_MS) {
      throw new HttpError(400, "bad_request", "Your phone's clock looks wrong.");
    }

    // A real install registers one key; a few more covers reinstalls and
    // keys lost when the phone was restored. Far more is a script.
    const db = adminClient();
    const since = new Date(Date.now() - 86_400_000).toISOString();
    const { count, error: countError } = await db.from("app_attest_keys")
      .select("key_id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("created_at", since);
    if (countError) throw new Error(countError.message);
    if ((count ?? 0) >= intEnv("APP_ATTEST_KEYS_PER_DAY", 5)) {
      throw new HttpError(429, "quota_exceeded", "Please try again tomorrow.");
    }

    let key;
    try {
      key = await verifyAttestation(key_id, attestation, await clientDataHash(userId, "app-attest", ts));
    } catch (err) {
      if (err instanceof AttestError) {
        console.warn(`app-attest refused: ${err.message}`);
        throw new HttpError(403, "integrity", "This copy of ClearSkin can't be verified.");
      }
      throw err;
    }

    // The key id is the hash of the public key, so the same id is always
    // the same key: registering it twice is harmless.
    const { error } = await db.from("app_attest_keys").upsert({
      key_id: key.keyId,
      public_key: `\\x${[...key.publicKey].map((b) => b.toString(16).padStart(2, "0")).join("")}`,
      environment: key.environment,
      user_id: userId,
    }, { onConflict: "key_id", ignoreDuplicates: true });
    if (error) throw new Error(error.message);
    return json({ ok: true });
  } catch (err) {
    return errorResponse(err);
  }
});
