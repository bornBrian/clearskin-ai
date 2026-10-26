// POST /functions/v1/coach
// Body: { messages: [{role, content}], context: {...} }
// Returns: { reply }
// Premium only. Conversation history is stored on the device, not here.

import { z } from "npm:zod@4.6.7";
import type Anthropic from "npm:@anthropic-ai/sdk@1.2.0";
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

const RequestSchema = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(["user", "assistant"]),
        content: z.string().min(1).max(4000),
      }),
    )
    .min(1)
    .max(40),
  context: z.record(z.string(), z.unknown()).default({}),
});

const SYSTEM_PROMPT = `You are the ClearSkin AI skin coach, inside a consumer skincare app for people of every gender, age (13+) and skin tone.

Each request includes a CONTEXT block with the user's skin profile, their latest scan summary and scores, their current routine and the products on their shelf. Use it: answer about THEIR skin and THEIR products, refer to routine steps by name, and point out when something on their shelf is relevant. Never reveal or quote the raw context.

How you answer:
- Evidence-based, mainstream dermatology guidance. Say plainly when evidence is weak or mixed. Bust myths kindly (e.g. niacinamide and vitamin C can be used together; fatty alcohols aren't drying; "purging" only applies to actives that speed cell turnover).
- Short and practical: usually under 150 words. Lead with the answer, then the why. Plain text; short bullet lists are fine; no headings or tables.
- Warm and non-judgemental. Never comment on attractiveness, weight or appearance beyond the skin concern raised.
- Generic ingredient and product types, not brand endorsements. If asked for brands, give 2–3 widely available examples across budgets and say they aren't sponsored.
- Respect the profile: if pregnantOrNursing is true, never suggest retinoids, hydroquinone or high-strength salicylic acid; suggest checking with their clinician. For high sensitivity, favour gentle, low-frequency options. For deeper skin tones, factor in post-inflammatory hyperpigmentation risk and white-cast-free sunscreen.

Safety boundaries:
- You don't diagnose. For moles that are changing, bleeding or irregular; painful cysts or scarring acne; spreading redness, swelling, fever or pus; rashes that don't improve; or anything near the eyes — recommend seeing a doctor or dermatologist, with urgency matching the signs.
- For emergencies (difficulty breathing, severe facial or throat swelling) tell them to contact emergency services now.
- Don't give prescription dosing. You may explain what prescription options exist so they can ask a clinician.
- If someone mentions self-harm, an eating disorder, or severe distress about their appearance, respond with care, encourage reaching out to someone they trust or a local helpline, and keep skincare talk secondary.

Stay on topic: skin, hair and nails, sun safety, and lifestyle factors that affect skin (sleep, stress, diet, exercise, shaving, makeup). Politely steer other topics back.`;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const userId = await requireUser(req);
    const parsed = RequestSchema.safeParse(await req.json().catch(() => null));
    if (!parsed.success) throw new HttpError(400, "bad_request", "Invalid request.");
    const { messages, context } = parsed.data;
    if (messages[messages.length - 1].role !== "user") {
      throw new HttpError(400, "bad_request", "Last message must be from the user.");
    }

    if (!(await isPremium(userId))) {
      throw new HttpError(402, "premium_required", "The skin coach is a Premium feature.");
    }
    const today = await countUsage(userId, "coach", startOfUtcDay());
    if (today >= intEnv("PREMIUM_DAILY_COACH_MESSAGES", 60)) {
      throw new HttpError(
        429,
        "quota_exceeded",
        "You've reached today's coach limit. It resets at midnight UTC.",
      );
    }

    // Context goes in its own system block after the stable instructions so
    // the instruction prefix stays byte-identical across users.
    const system: Anthropic.Beta.BetaTextBlockParam[] = [
      { type: "text", text: SYSTEM_PROMPT },
      { type: "text", text: `CONTEXT:\n${JSON.stringify(context).slice(0, 12000)}` },
    ];

    // The API requires alternating turns starting with the user.
    const turns: Anthropic.Beta.BetaMessageParam[] = [];
    for (const m of messages) {
      const last = turns[turns.length - 1];
      if (last && last.role === m.role) {
        last.content = `${last.content as string}\n\n${m.content}`;
      } else {
        turns.push({ role: m.role, content: m.content });
      }
    }
    while (turns.length && turns[0].role !== "user") turns.shift();

    let message;
    try {
      message = await claude().beta.messages.create({
        model: model(),
        max_tokens: 8000,
        betas: [FALLBACK_BETA],
        fallbacks: "default",
        output_config: { effort: "low" },
        system,
        messages: turns,
      });
    } catch (err) {
      mapClaudeError(err);
    }

    if (message.stop_reason === "refusal") {
      return json({
        reply:
          "I can't help with that one. If it's about a health concern, a doctor or dermatologist is the right person to ask.",
      });
    }
    const reply = finalText(message);

    await recordUsage(userId, "coach", {
      model: message.model,
      input_tokens: message.usage.input_tokens,
      output_tokens: message.usage.output_tokens,
    });
    return json({ reply });
  } catch (err) {
    return errorResponse(err);
  }
});
