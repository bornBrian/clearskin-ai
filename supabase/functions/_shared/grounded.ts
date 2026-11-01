// Text answers checked against live Google Search, through Gemini's
// "grounding with Google Search" tool. Used where the answer is general
// skincare knowledge (what an ingredient does, what helps redness) so it
// rests on current sources rather than a model's memory alone, and so the
// cheaper Gemini Flash can take work off the vision model.
//
// Only text ever goes in: never a photo. Sources are not shown to users.
// Needs GEMINI_API_KEY (a paid tier, so inputs aren't used for training).
// Grounded requests beyond the free daily allowance are billed per request;
// GROUNDING_COST_USD (default $0.035) books that worst case against the
// daily spend limit.

import { type ClaudeUsage, HttpError } from "./common.ts";

export interface GroundedRequest {
  system: string;
  /** Alternating user/model turns, oldest first, ending with the user. */
  turns: { role: "user" | "model"; text: string }[];
  maxTokens: number;
}

export interface GroundedResult {
  text: string;
  usage: ClaudeUsage;
}

export function groundingAvailable(): boolean {
  return !!Deno.env.get("GEMINI_API_KEY");
}

export function groundedModel(): string {
  return Deno.env.get("GEMINI_GROUNDED_MODEL") ?? "gemini-2.5-flash";
}

export async function grounded(r: GroundedRequest, fetchImpl: typeof fetch = fetch): Promise<GroundedResult> {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) throw new HttpError(503, "not_configured", "Search-backed answers aren't set up.");
  const modelId = groundedModel();
  const res = await fetchImpl(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelId)}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: r.system }] },
        contents: r.turns.map((t) => ({ role: t.role, parts: [{ text: t.text }] })),
        tools: [{ google_search: {} }],
        generationConfig: { maxOutputTokens: r.maxTokens, temperature: 0.4 },
      }),
      signal: AbortSignal.timeout(40_000),
    },
  );
  if (!res.ok) {
    console.error("Grounded Gemini error", res.status);
    throw new HttpError(502, "server", "Our answer service had a hiccup. Please try again.");
  }
  const body = await res.json();
  const searched = (body?.candidates?.[0]?.groundingMetadata?.webSearchQueries ?? []).length > 0;
  const usage: ClaudeUsage = {
    model: modelId,
    input_tokens: body?.usageMetadata?.promptTokenCount ?? null,
    output_tokens: (body?.usageMetadata?.candidatesTokenCount ?? 0) + (body?.usageMetadata?.thoughtsTokenCount ?? 0),
    extra_usd: searched ? Number(Deno.env.get("GROUNDING_COST_USD") ?? 0.035) : 0,
  };
  const text = (body?.candidates?.[0]?.content?.parts ?? [])
    .map((p: { text?: string }) => p.text ?? "")
    .join("")
    .trim();
  if (!text) throw new HttpError(502, "server", "Empty answer. Please try again.");
  return { text, usage };
}

/** The JSON object in a model's answer, even if it wrapped it in prose or a
 * code fence (grounded calls can't use Gemini's strict JSON mode). */
export function extractJson(text: string): unknown {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
}
