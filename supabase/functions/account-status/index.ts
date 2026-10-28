// POST /functions/v1/account-status
// Returns the caller's plan, scan allowance and shop configuration:
// {
//   premium, expires_at, will_renew, billing_issue,
//   scans: { used, limit, window_days, resets_at, credits, rewarded_left_today },
//   shop: { ...SHOP_CONFIG_JSON }
// }
// Read-only and cheap; the app calls it on launch and before a scan so the
// numbers it shows are the server's, not its own guess.

import { adminClient, deviceHash, entitlement, errorResponse, intEnv, json, requireUser } from "../_shared/common.ts";

let shopConfig: unknown;

function shop(): unknown {
  if (shopConfig !== undefined) return shopConfig;
  try {
    shopConfig = JSON.parse(Deno.env.get("SHOP_CONFIG_JSON") ?? "null");
  } catch {
    console.error("SHOP_CONFIG_JSON is not valid JSON");
    shopConfig = null;
  }
  return shopConfig;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const userId = await requireUser(req);
    const device = deviceHash(req);
    const db = adminClient();
    const ent = await entitlement(userId);

    const limit = intEnv("FREE_SCANS_PER_WINDOW", 2);
    const windowDays = intEnv("FREE_SCAN_WINDOW_DAYS", 30);
    const since = new Date(Date.now() - windowDays * 86_400_000).toISOString();

    const counted = (column: "user_id" | "device_hash", value: string) =>
      db.from("usage_events")
        .select("created_at")
        .eq(column, value)
        .eq("kind", "scan")
        .eq("refunded", false)
        .is("credit_id", null)
        .gte("created_at", since)
        .order("created_at", { ascending: true })
        .limit(50);

    const [mine, onDevice, credits, earnedToday] = await Promise.all([
      counted("user_id", userId),
      device ? counted("device_hash", device) : Promise.resolve({ data: [], error: null }),
      db.from("scan_credits")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .is("consumed_at", null),
      db.from("scan_credits")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .gte("created_at", new Date(new Date().setUTCHours(0, 0, 0, 0)).toISOString()),
    ]);
    for (const r of [mine, onDevice, credits, earnedToday]) if (r.error) throw r.error;

    // Same rule as reserve_usage: whichever of account and device has used more.
    const rows = (mine.data!.length >= onDevice.data!.length ? mine.data : onDevice.data) ?? [];
    const used = rows.length;
    // When the oldest counted scan leaves the window, one scan frees up.
    const resetsAt = used >= limit && rows[0]
      ? new Date(Date.parse(rows[0].created_at) + windowDays * 86_400_000).toISOString()
      : null;

    return json({
      premium: ent.premium,
      expires_at: ent.expiresAt,
      will_renew: ent.willRenew,
      billing_issue: ent.billingIssue,
      scans: {
        used,
        limit,
        window_days: windowDays,
        resets_at: resetsAt,
        credits: credits.count ?? 0,
        rewarded_left_today: Math.max(
          0,
          intEnv("REWARDED_SCANS_PER_DAY", 1) - (earnedToday.count ?? 0),
        ),
      },
      shop: shop(),
    });
  } catch (err) {
    return errorResponse(err);
  }
});
