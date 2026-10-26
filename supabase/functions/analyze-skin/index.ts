// POST /functions/v1/analyze-skin
// Body: { image_base64, media_type: "image/jpeg", profile, previous? }
// Returns: { analysis } matching the app's SkinAnalysis model.
//
// Privacy: the image is held in memory only for the duration of the request.
// It is never written to storage or logged.

import { z } from "npm:zod@4.6.7";
import { claude, FALLBACK_BETA, finalText, mapClaudeError, model } from "../_shared/claude.ts";
import {
  countUsage,
  errorResponse,
  HttpError,
  intEnv,
  isPremium,
  json,
  recordUsage,
  requireUser,
  startOfUtcDay,
} from "../_shared/common.ts";
import { ANALYSIS_SCHEMA, ANALYSIS_SYSTEM_PROMPT, METRIC_KEYS } from "./prompt.ts";

const MAX_IMAGE_BYTES = 4 * 1024 * 1024;

const RequestSchema = z.object({
  image_base64: z.string().min(1000),
  media_type: z.enum(["image/jpeg", "image/png", "image/webp"]),
  profile: z.record(z.string(), z.unknown()).default({}),
  previous: z
    .object({
      overall_score: z.number(),
      metrics: z.array(z.object({ metric: z.string(), score: z.number() }).loose()),
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
});

const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const userId = await requireUser(req);

    const parsed = RequestSchema.safeParse(await req.json().catch(() => null));
    if (!parsed.success) {
      throw new HttpError(400, "bad_request", "Invalid request.");
    }
    const body = parsed.data;
    // base64 is ~4/3 the binary size.
    if ((body.image_base64.length * 3) / 4 > MAX_IMAGE_BYTES) {
      throw new HttpError(413, "bad_image", "That photo is too large. Please retake it.");
    }

    // ── Quotas ─────────────────────────────────────────────────────────
    const premium = await isPremium(userId);
    if (!premium) {
      const lifetime = await countUsage(userId, "scan");
      if (lifetime >= intEnv("FREE_LIFETIME_SCANS", 1)) {
        throw new HttpError(
          402,
          "premium_required",
          "You've used your free scan. Upgrade to keep tracking your skin.",
        );
      }
    } else {
      const today = await countUsage(userId, "scan", startOfUtcDay());
      if (today >= intEnv("PREMIUM_DAILY_SCANS", 3)) {
        throw new HttpError(
          429,
          "quota_exceeded",
          "You've reached today's scan limit. Skin changes slowly — weekly scans give the clearest picture.",
        );
      }
    }

    // ── Analysis ──────────────────────────────────────────────────────
    const context = {
      user_profile: body.profile,
      previous_scan: body.previous ?? null,
    };

    let message;
    try {
      message = await claude().beta.messages.create({
        model: model(),
        max_tokens: 16000,
        betas: [FALLBACK_BETA],
        fallbacks: "default",
        output_config: {
          effort: "medium",
          format: { type: "json_schema", schema: ANALYSIS_SCHEMA },
        },
        system: ANALYSIS_SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: body.media_type,
                  data: body.image_base64,
                },
              },
              {
                type: "text",
                text:
                  "Analyse the skin in this photo using the rubric. Context (JSON):\n" +
                  JSON.stringify(context),
              },
            ],
          },
        ],
      });
    } catch (err) {
      mapClaudeError(err);
    }

    const raw = JSON.parse(finalText(message));
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
      model: message.model,
    };

    // Only usable analyses consume the quota: a blurry photo shouldn't cost
    // the user their free scan.
    if (analysis.image_quality.usable) {
      await recordUsage(userId, "scan", {
        model: message.model,
        input_tokens: message.usage.input_tokens,
        output_tokens: message.usage.output_tokens,
      });
    }

    return json({ analysis });
  } catch (err) {
    return errorResponse(err);
  }
});
