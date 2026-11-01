// POST /functions/v1/skin-insight
// Body: { profile, radiance, metrics, measure }  (numbers only, no photo)
// Returns: { insight: { summary, strengths, priorities,
//            recommended_ingredients, ingredients_to_avoid, beyond_products } }
//
// Words for a scan the phone measured itself (when the vision analysis
// couldn't be reached). A small Gemini model writes them, checking its
// advice against live Google Search; sources aren't returned. Far cheaper
// than a vision call, and limited per user like scans and the coach.

import {
  allInOrder,
  deviceHash,
  errorResponse,
  finishUsage,
  HttpError,
  intEnv,
  isPremium,
  json,
  readJson,
  releaseUsage,
  requireSpendHeadroom,
  requireUser,
  reserveUsage,
} from "../_shared/common.ts";
import { extractJson, grounded, groundingAvailable } from "../_shared/grounded.ts";
import { requireIntegrity } from "../_shared/integrity.ts";
import { InsightSchema, RequestSchema, SYSTEM_PROMPT } from "./insight.ts";

const MAX_BODY_BYTES = 20_000;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  let reservation: number | undefined;
  try {
    const userId = await requireUser(req);
    const [, raw, premium] = await allInOrder(
      requireIntegrity(req, userId, "skin-insight"),
      readJson(req, MAX_BODY_BYTES),
      isPremium(userId),
    );
    const parsed = RequestSchema.safeParse(raw);
    if (!parsed.success) throw new HttpError(400, "bad_request", "Invalid request.");
    if (!groundingAvailable()) {
      throw new HttpError(503, "not_configured", "Search-backed answers aren't set up.");
    }

    await requireSpendHeadroom();
    const r = await reserveUsage({
      userId,
      kind: "insight",
      device: deviceHash(req),
      premium,
      freeLimit: intEnv("FREE_INSIGHTS_PER_WEEK", 10),
      windowDays: 7,
      dailyLimit: intEnv("PREMIUM_DAILY_INSIGHTS", 20),
      attemptLimit: intEnv("INSIGHT_ATTEMPTS_PER_DAY", 30),
    });
    if ("blocked" in r) {
      throw new HttpError(429, "quota_exceeded", "You've had a lot of quick checks today. Try again tomorrow.");
    }
    reservation = r.eventId;

    const { text, usage } = await grounded({
      system: SYSTEM_PROMPT,
      turns: [{ role: "user", text: `MEASUREMENTS:\n${JSON.stringify(parsed.data)}` }],
      maxTokens: 1500,
    });
    await finishUsage(reservation, usage);
    reservation = undefined;

    const insight = InsightSchema.safeParse(extractJson(text));
    if (!insight.success) {
      console.error("skin-insight: unusable answer");
      throw new HttpError(502, "server", "The explanation didn't come through. Your result is still saved.");
    }
    return json({ insight: insight.data });
  } catch (err) {
    if (reservation !== undefined) await releaseUsage(reservation);
    return errorResponse(err);
  }
});
