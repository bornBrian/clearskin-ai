// POST /functions/v1/referral
// Body: { action: "status" }            → { code, rewarded, redeemed }
//       { action: "redeem", code: "…" } → { ok: true }
//
// Invite a friend. Each account has a stable 6-character code. A new
// account can enter one friend's code; once it completes a usable scan,
// analyze-skin calls reward_referral and both get one free scan credit.
// Guards: no own code, one code per account, one referral per phone,
// accounts older than REFERRAL_MAX_ACCOUNT_DAYS can't redeem, and inviters
// earn at most REFERRAL_MONTHLY_CAP rewards a month.

import { z } from "npm:zod@4.6.7";
import {
  adminClient,
  allInOrder,
  deviceHash,
  errorResponse,
  HttpError,
  intEnv,
  json,
  readJson,
  requireUser,
} from "../_shared/common.ts";
import { requireIntegrity } from "../_shared/integrity.ts";
import { CODE, newCode } from "../_shared/referral.ts";

const Body = z.discriminatedUnion("action", [
  z.object({ action: z.literal("status") }),
  z.object({
    action: z.literal("redeem"),
    code: z.string().trim().toUpperCase().regex(CODE),
  }),
]);

async function codeFor(userId: string): Promise<string> {
  const db = adminClient();
  const { data } = await db.from("referral_codes").select("code").eq("user_id", userId).maybeSingle();
  if (data?.code) return data.code;
  for (let i = 0; i < 5; i++) {
    const code = newCode();
    const { error } = await db.from("referral_codes").insert({ user_id: userId, code });
    if (!error) return code;
    // Another request created ours first: use it.
    const again = await db.from("referral_codes").select("code").eq("user_id", userId).maybeSingle();
    if (again.data?.code) return again.data.code;
  }
  throw new HttpError(500, "server", "Couldn't make your invite code. Please try again.");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const userId = await requireUser(req);
    const [, raw] = await allInOrder(requireIntegrity(req, userId, "referral"), readJson(req, 2_000));
    const parsed = Body.safeParse(raw);
    if (!parsed.success) {
      throw new HttpError(400, "bad_code", "That code doesn't look right. Codes are 6 letters and numbers.");
    }
    const db = adminClient();

    if (parsed.data.action === "status") {
      const [code, rewarded, mine] = await Promise.all([
        codeFor(userId),
        db.from("referrals").select("invitee_id", { count: "exact", head: true })
          .eq("inviter_id", userId).not("rewarded_at", "is", null),
        db.from("referrals").select("invitee_id").eq("invitee_id", userId).maybeSingle(),
      ]);
      return json({ code, rewarded: rewarded.count ?? 0, redeemed: !!mine.data });
    }

    const { code } = parsed.data;
    const [owner, already, user] = await Promise.all([
      db.from("referral_codes").select("user_id").eq("code", code).maybeSingle(),
      db.from("referrals").select("invitee_id").eq("invitee_id", userId).maybeSingle(),
      db.auth.admin.getUserById(userId),
    ]);
    const inviter = owner.data?.user_id as string | undefined;
    if (!inviter) throw new HttpError(404, "bad_code", "We couldn't find that code. Check it with your friend.");
    if (inviter === userId) {
      throw new HttpError(400, "own_code", "That's your own code. Share it with a friend instead.");
    }
    if (already.data) throw new HttpError(409, "already_redeemed", "You've already used a friend's code.");

    const created = Date.parse(user.data.user?.created_at ?? "");
    const maxDays = intEnv("REFERRAL_MAX_ACCOUNT_DAYS", 14);
    if (!Number.isFinite(created) || Date.now() - created > maxDays * 86_400_000) {
      throw new HttpError(403, "too_late", "Invite codes are for new accounts, in their first two weeks.");
    }

    const device = deviceHash(req);
    const { error } = await db.from("referrals").insert({
      invitee_id: userId,
      inviter_id: inviter,
      invitee_device: device,
    });
    if (error) {
      // Unique violations: this account or this phone was already referred.
      if (error.code === "23505") {
        throw new HttpError(409, "already_redeemed", "This phone has already used an invite code.");
      }
      console.error("Referral insert failed", error.code);
      throw new HttpError(500, "server", "Couldn't save the code. Please try again.");
    }
    return json({ ok: true });
  } catch (err) {
    return errorResponse(err);
  }
});
