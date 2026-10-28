// POST /functions/v1/apple-token  { authorization_code }
//
// Called by the iPhone app right after Sign in with Apple. Exchanges the
// one-time code for Apple's refresh token and keeps it, only so that
// delete-account can revoke ClearSkin's access at Apple, as Apple requires.
// Signing in never depends on this succeeding.

import { z } from "npm:zod@4.6.7";
import { appleSignInConfigured, exchangeCode } from "../_shared/apple_signin.ts";
import { adminClient, errorResponse, HttpError, json, readJson, requireUser } from "../_shared/common.ts";

const RequestSchema = z.object({
  authorization_code: z.string().min(10).max(1000).regex(/^[A-Za-z0-9._-]+$/),
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const userId = await requireUser(req);
    if (!appleSignInConfigured()) {
      throw new HttpError(503, "not_configured", "Sign in with Apple isn't set up yet.");
    }
    const parsed = RequestSchema.safeParse(await readJson(req, 4_000));
    if (!parsed.success) throw new HttpError(400, "bad_request", "Invalid request.");

    const token = await exchangeCode(parsed.data.authorization_code);
    if (!token) throw new HttpError(400, "bad_request", "Apple didn't accept that code.");

    const { error } = await adminClient().from("apple_tokens").upsert({
      user_id: userId,
      refresh_token: token,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
    if (error) throw new Error(error.message);
    return json({ ok: true });
  } catch (err) {
    return errorResponse(err);
  }
});
