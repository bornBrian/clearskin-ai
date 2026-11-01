// Invite codes and the referral reward, shared by the referral and
// analyze-skin functions.

import { adminClient, intEnv } from "./common.ts";

// No 0/O, 1/I/L: easy to read out and type.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const CODE = /^[A-Z2-9]{6}$/;

export function newCode(random: (n: number) => Uint8Array = (n) => crypto.getRandomValues(new Uint8Array(n))): string {
  return [...random(6)].map((b) => ALPHABET[b % ALPHABET.length]).join("");
}

/** Called by analyze-skin after a usable scan. Never throws: a reward
 * failing must not fail the scan. */
export async function rewardReferral(userId: string): Promise<void> {
  const { error } = await adminClient().rpc("reward_referral", {
    p_invitee: userId,
    p_monthly_cap: intEnv("REFERRAL_MONTHLY_CAP", 5),
  });
  if (error) console.error("reward_referral failed", error.code);
}
