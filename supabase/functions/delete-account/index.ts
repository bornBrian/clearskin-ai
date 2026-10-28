// POST /functions/v1/delete-account
// Permanently deletes the caller's server-side data: the RevenueCat
// customer record, ClearSkin's Sign in with Apple access (revoked at Apple,
// as Apple requires), scan credits and the auth user. Usage rows are unlinked
// (the foreign key sets user_id to null) rather than deleted, so a device's
// free scans can't be reset by deleting and re-creating an account. They
// hold no personal data and are purged after 90 days. Required by Google Play's
// account-deletion policy. Store subscriptions must still be cancelled by the
// user in Google Play / App Store (stores don't allow apps to cancel them).

import { appleSignInConfigured, revokeToken } from "../_shared/apple_signin.ts";
import { adminClient, errorResponse, json, requireUser } from "../_shared/common.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const userId = await requireUser(req);
    const admin = adminClient();

    const rcSecret = Deno.env.get("REVENUECAT_SECRET_KEY");
    if (rcSecret) {
      const res = await fetch(
        `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
        { method: "DELETE", headers: { Authorization: `Bearer ${rcSecret}` } },
      );
      if (!res.ok && res.status !== 404) {
        console.error("RevenueCat delete failed", res.status);
      }
    }

    // Best effort: a failure at Apple is logged, never blocks the deletion.
    const { data: apple } = await admin.from("apple_tokens")
      .select("refresh_token")
      .eq("user_id", userId)
      .maybeSingle();
    if (apple?.refresh_token && appleSignInConfigured()) {
      try {
        if (!await revokeToken(apple.refresh_token)) console.error("Apple revoke refused");
      } catch (err) {
        console.error("Apple revoke failed", err);
      }
    }

    const { error: authErr } = await admin.auth.admin.deleteUser(userId);
    if (authErr) throw authErr;

    return json({ deleted: true });
  } catch (err) {
    return errorResponse(err);
  }
});
