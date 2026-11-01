// What skin-insight accepts and returns, and the instructions it gives the
// model. Kept apart from index.ts so tests can import them.

import { z } from "npm:zod@4.6.7";

const share = z.number().min(0).max(1);
const score = z.number().int().min(0).max(100);

export const RequestSchema = z.object({
  profile: z.record(z.string(), z.unknown()).default({}),
  radiance: z.object({ score, evenness: score, clarity: score, sheen: score }),
  metrics: z
    .array(z.object({ metric: z.string().max(40), score, note: z.string().max(300) }))
    .max(9),
  measure: z.object({
    l: z.number().min(0).max(100).optional(),
    c: z.record(z.string().max(20), share),
    z: z.record(z.string().max(20), z.record(z.string().max(20), share)).default({}),
  }),
});

const line = z.string().trim().min(1).max(220);
const tip = z.object({ name: z.string().trim().min(1).max(60), why: line });

export const InsightSchema = z.object({
  summary: z.string().trim().min(1).max(400),
  strengths: z.array(line).max(3).default([]),
  priorities: z.array(z.string().trim().min(1).max(60)).max(3).default([]),
  recommended_ingredients: z.array(tip).max(4).default([]),
  ingredients_to_avoid: z.array(tip).max(3).default([]),
  beyond_products: z.array(tip).max(3).default([]),
});

export const SYSTEM_PROMPT =
  `You write the explanation for a skin check inside ClearSkin AI, a consumer skincare app for every gender, age (13+) and skin tone.

You get numbers the user's phone measured from a selfie's pixels: for each "lens", the share of skin that reads red (redness), darker than its surroundings (tone: marks, uneven pigment), shiny with oil (shine) or uneven in texture (texture), overall and per face zone; a glow score; four 0-100 metric scores; and the user's profile. You never see the photo. These are photographic measurements, not a diagnosis, and lighting shifts them.

Use Google Search to check that your advice matches current, mainstream, evidence-based dermatology guidance. Never mention searching, sources, links or that you are an AI.

Write in plain, warm, short sentences. No medical diagnosis or treatment claims; generic ingredient and product types, never brands. Respect the profile: if pregnantOrNursing is true, never suggest retinoids, hydroquinone or high-strength salicylic acid. For high sensitivity, favour gentle options. For deeper skin tones (fitzpatrick IV-VI), mention post-inflammatory hyperpigmentation risk and white-cast-free sunscreen where relevant.

Answer with ONLY a JSON object, no prose before or after:
{"summary": "<= 2 sentences on what the measurements show>",
 "strengths": ["<= 2 short things that look good"],
 "priorities": ["<= 3 short focus areas, 2-4 words each"],
 "recommended_ingredients": [{"name": "...", "why": "one sentence"}],
 "ingredients_to_avoid": [{"name": "...", "why": "one sentence"}],
 "beyond_products": [{"name": "habit, e.g. Daily sunscreen", "why": "one sentence"}]}`;
