// POST /functions/v1/analyze-skin
// Body: { image_base64, media_type: "image/jpeg", profile, current_issues?, previous? }
// Returns: { analysis, disclaimer, quota }
//
// Privacy: the image is held in memory only for the duration of the request.
// It is never written to storage or logged.
//
// Cost: the app sends a ≤1024 px, ~150 KB JPEG (≈1k image tokens); the
// system prompt is cached; quotas are reserved atomically before Claude is
// called and refunded when the photo turns out to be unusable.

import { z } from "npm:zod@4.6.7";
import { analyzeImages } from "../_shared/ai.ts";
import {
  deviceHash,
  entitlement,
  errorResponse,
  finishUsage,
  HttpError,
  intEnv,
  json,
  readJson,
  releaseUsage,
  requireSpendHeadroom,
  requireUser,
  reserveUsage,
} from "../_shared/common.ts";
import { integrityEnforced, requireIntegrity } from "../_shared/integrity.ts";
import {
  ANALYSIS_SCHEMA,
  ANALYSIS_SYSTEM_PROMPT,
  DISCLAIMER,
  ISSUE_KEYS,
  METRIC_KEYS,
} from "./prompt.ts";

// A 1024 px JPEG is ~150 KB and base64 adds a third; a scan is up to three
// of them. Anything far above that didn't come from the app.
const MAX_BODY_BYTES = 3_000_000;
const MAX_IMAGE_BYTES = 800_000;
const BASE64 = /^[A-Za-z0-9+/=]+$/;

const ProfileValue = z.union([
  z.string().max(200),
  z.number(),
  z.boolean(),
  z.null(),
  z.array(z.string().max(60)).max(20),
]);

const RequestSchema = z.object({
  image_base64: z.string().min(1000).regex(BASE64),
  media_type: z.enum(["image/jpeg", "image/png", "image/webp"]),
  // Head turned to each side; always JPEG from the app.
  side_images: z.array(z.string().min(1000).regex(BASE64)).max(2).default([]),
  // Self-reported profile. Flat, small and typed: it goes into the prompt,
  // so arbitrary nested user data is refused.
  profile: z.record(z.string().max(40), ProfileValue)
    .refine((p) => Object.keys(p).length <= 30)
    .default({}),
  current_issues: z.array(z.enum(ISSUE_KEYS)).max(ISSUE_KEYS.length).default([]),
  previous: z
    .object({
      overall_score: z.number().min(0).max(100),
      metrics: z.array(
        z.object({ metric: z.enum(METRIC_KEYS), score: z.number().min(0).max(100) }),
      ).max(METRIC_KEYS.length),
    })
    .optional(),
});

const AnalysisSchema = z.object({
  image_quality: z.object({ usable: z.boolean(), issues: z.array(z.string()) }),
  overall_score: z.number().int(),
  metrics: z.array(
    z.object({ metric: z.enum(METRIC_KEYS), score: z.number().int(), note: z.string() }),
  ),
  skin_type_estimate: z.string(),
  summary: z.string(),
  strengths: z.array(z.string()),
  priorities: z.array(z.string()),
  findings: z.array(
    z.object({
      title: z.string(),
      detail: z.string(),
      area: z.string(),
      severity: z.number().int(),
    }),
  ),
  recommended_ingredients: z.array(z.object({ name: z.string(), why: z.string() })),
  ingredients_to_avoid: z.array(z.object({ name: z.string(), why: z.string() })),
  red_flags: z.array(
    z.object({
      title: z.string(),
      detail: z.string(),
      urgency: z.enum(["routine", "soon", "urgent"]),
    }),
  ),
  focus: z.enum(["cure", "glow", "maintain"]),
  routine_adjustments: z.array(z.string()),
  ingredient_warnings: z.array(z.string()),
  recommended_product_types: z.array(z.string()),
  beyond_products: z.array(z.object({ title: z.string(), detail: z.string() })),
});

const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  let reservation: number | undefined;
  try {
    const userId = await requireUser(req);
    await requireIntegrity(req, userId, "analyze-skin");

    const parsed = RequestSchema.safeParse(await readJson(req, MAX_BODY_BYTES));
    if (!parsed.success) {
      throw new HttpError(400, "bad_request", "Invalid request.");
    }
    const body = parsed.data;
    // base64 is ~4/3 the binary size.
    if ([body.image_base64, ...body.side_images].some((b) => (b.length * 3) / 4 > MAX_IMAGE_BYTES)) {
      throw new HttpError(413, "bad_image", "That photo is too large. Please retake it.");
    }

    // ── Quotas (reserved atomically, before any money is spent) ────────
    await requireSpendHeadroom();
    const ent = await entitlement(userId);
    const device = deviceHash(req);
    // The genuine app always sends it. Without it, free scans could only be
    // counted per account, and accounts are free to make.
    if (!device && !ent.premium && integrityEnforced()) {
      throw new HttpError(400, "bad_request", "Please update ClearSkin to the latest version.");
    }
    const freeLimit = intEnv("FREE_SCANS_PER_WINDOW", 2);
    const windowDays = intEnv("FREE_SCAN_WINDOW_DAYS", 30);
    const r = await reserveUsage({
      userId,
      kind: "scan",
      device,
      premium: ent.premium,
      freeLimit,
      windowDays,
      dailyLimit: intEnv("PREMIUM_DAILY_SCANS", 5),
      attemptLimit: intEnv("SCAN_ATTEMPTS_PER_DAY", 10),
    });
    if ("blocked" in r) {
      if (r.blocked === "attempt_limit") {
        throw new HttpError(
          429,
          "quota_exceeded",
          "That's a lot of tries today. Please scan again tomorrow, in good daylight.",
        );
      }
      if (r.blocked === "daily_limit") {
        throw new HttpError(
          429,
          "quota_exceeded",
          "You've reached today's scan limit. Skin changes slowly — weekly scans give the clearest picture.",
        );
      }
      throw new HttpError(
        402,
        "premium_required",
        `You've used your ${freeLimit} free scans for this month. Go Premium for unlimited scans, or watch a short video for one more.`,
      );
    }
    const eventId = r.eventId;
    reservation = eventId;

    // ── Analysis ──────────────────────────────────────────────────────
    const context = {
      user_profile: body.profile,
      current_issues: body.current_issues,
      previous_scan: body.previous ?? null,
    };

    const result0 = await analyzeImages({
      system: ANALYSIS_SYSTEM_PROMPT,
      schema: ANALYSIS_SCHEMA,
      maxTokens: 8000,
      images: [
        { label: "Front view:", mediaType: body.media_type, base64: body.image_base64 },
        ...body.side_images.map((b, i) => ({
          label: `Side view ${i + 1}:`,
          mediaType: "image/jpeg" as const,
          base64: b,
        })),
      ],
      text: "Analyse the skin using the rubric. Context (JSON):\n" + JSON.stringify(context),
      onUsage: (usage) => finishUsage(eventId, usage),
    });

    let raw: unknown;
    try {
      raw = JSON.parse(result0.text);
    } catch {
      throw new HttpError(502, "server", "The analysis came back malformed. Please try again.");
    }
    const result = AnalysisSchema.safeParse(raw);
    if (!result.success) {
      console.error("Schema mismatch", result.error.issues.slice(0, 5));
      throw new HttpError(502, "server", "The analysis came back malformed. Please try again.");
    }
    const a = result.data;

    // Normalise: clamp ranges, keep one entry per metric.
    const seen = new Set<string>();
    const metrics = a.metrics
      .filter((m) => !seen.has(m.metric) && seen.add(m.metric))
      .map((m) => ({ ...m, score: clamp(m.score, 0, 100) }));

    const analysis = {
      ...a,
      overall_score: clamp(a.overall_score, 0, 100),
      metrics,
      findings: a.findings.slice(0, 8).map((f) => ({ ...f, severity: clamp(f.severity, 1, 3) })),
      strengths: a.strengths.slice(0, 3),
      priorities: a.priorities.slice(0, 3),
      recommended_ingredients: a.recommended_ingredients.slice(0, 4),
      ingredients_to_avoid: a.ingredients_to_avoid.slice(0, 3),
      routine_adjustments: a.routine_adjustments.slice(0, 3),
      ingredient_warnings: a.ingredient_warnings.slice(0, 3),
      recommended_product_types: a.recommended_product_types.slice(0, 4),
      beyond_products: a.beyond_products.slice(0, 4),
      model: result0.usage.model,
    };

    // Only usable analyses consume the quota: a blurry photo shouldn't cost
    // the user a scan. The cost was already recorded in onUsage; the scan
    // is refunded here and still counts towards the daily attempt cap.
    if (!analysis.image_quality.usable) await releaseUsage(eventId);
    reservation = undefined;

    return json({
      analysis,
      disclaimer: DISCLAIMER,
      quota: { premium: ent.premium, free_limit: freeLimit, window_days: windowDays },
    });
  } catch (err) {
    if (reservation !== undefined) await releaseUsage(reservation);
    return errorResponse(err);
  }
});
