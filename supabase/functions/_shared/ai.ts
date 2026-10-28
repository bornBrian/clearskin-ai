// Vision analysis with a fallback chain, so a provider outage doesn't take
// scans down:
//
//   1. Claude, CLAUDE_MODEL (default claude-opus-5-5). Policy declines are
//      re-run server-side on Anthropic's fallback model inside the same call.
//   2. Claude, CLAUDE_FALLBACK_MODEL (default claude-sonnet-5-5) when the
//      primary is overloaded, rate-limited, timing out or erroring.
//   3. Google Gemini, only if GEMINI_API_KEY is set, when Anthropic is
//      unreachable altogether. Use a paid Gemini tier (free-tier inputs may
//      be used for training) and list Google in the privacy policy before
//      turning it on.
//
// Every provider gets the same system prompt and JSON schema, and every
// answer is validated by the same Zod schema in the caller.

import Anthropic from "npm:@anthropic-ai/sdk@1.2.0";
import { claude, FALLBACK_BETA, fallbackModel, finalText, mapClaudeError, model } from "./claude.ts";
import { type ClaudeUsage, HttpError } from "./common.ts";

export interface VisionImage {
  mediaType: "image/jpeg" | "image/png" | "image/webp";
  base64: string;
  /** Short label placed before the image ("Front view"). */
  label: string;
}

export interface VisionRequest {
  system: string;
  schema: Record<string, unknown>;
  images: VisionImage[];
  text: string;
  maxTokens: number;
  /** Called with the token usage as soon as a provider answers, before the
   * answer is checked. A refusal, a cut-off or malformed JSON still cost
   * money, so the cost is on the books even when the request then fails. */
  onUsage?: (usage: ClaudeUsage) => Promise<void>;
}

export interface VisionResult {
  text: string;
  usage: ClaudeUsage;
}

/** Errors worth trying the next provider for: capacity, outages, timeouts. */
function retryable(err: unknown): boolean {
  if (err instanceof Anthropic.RateLimitError) return true;
  if (err instanceof Anthropic.APIConnectionError) return true; // includes timeouts
  if (err instanceof Anthropic.InternalServerError) return true; // 5xx, 529 overloaded
  if (err instanceof Anthropic.AuthenticationError) return true; // key missing/revoked
  if (err instanceof Error && err.message.startsWith("Missing env var ANTHROPIC")) return true;
  return false;
}

async function viaClaude(modelId: string, r: VisionRequest): Promise<VisionResult> {
  const content: Anthropic.Beta.BetaContentBlockParam[] = [];
  for (const img of r.images) {
    content.push({ type: "text", text: img.label });
    content.push({
      type: "image",
      source: { type: "base64", media_type: img.mediaType, data: img.base64 },
    });
  }
  content.push({ type: "text", text: r.text });

  const message = await claude().beta.messages.create({
    model: modelId,
    max_tokens: r.maxTokens,
    betas: [FALLBACK_BETA],
    fallbacks: "default",
    output_config: {
      effort: "medium",
      format: { type: "json_schema", schema: r.schema },
    },
    // Identical for every user, so it's written to the cache once and then
    // read at a fraction of the input price.
    system: [{ type: "text", text: r.system, cache_control: { type: "ephemeral" } }],
    messages: [{ role: "user", content }],
  });
  const usage = { model: message.model, ...message.usage };
  await r.onUsage?.(usage);
  return { text: finalText(message), usage };
}

async function viaGemini(r: VisionRequest): Promise<VisionResult> {
  const key = Deno.env.get("GEMINI_API_KEY")!;
  const modelId = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-pro";
  const parts: Record<string, unknown>[] = [];
  for (const img of r.images) {
    parts.push({ text: img.label });
    parts.push({ inlineData: { mimeType: img.mediaType, data: img.base64 } });
  }
  parts.push({ text: r.text });

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelId)}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: r.system }] },
        contents: [{ role: "user", parts }],
        generationConfig: {
          responseMimeType: "application/json",
          responseJsonSchema: r.schema,
          maxOutputTokens: r.maxTokens,
        },
      }),
      signal: AbortSignal.timeout(80_000),
    },
  );
  if (!res.ok) {
    console.error("Gemini error", res.status);
    throw new HttpError(502, "server", "Our AI service had a hiccup. Please try again.");
  }
  const body = await res.json();
  const usage: ClaudeUsage = {
    model: modelId,
    input_tokens: body?.usageMetadata?.promptTokenCount ?? null,
    output_tokens: body?.usageMetadata?.candidatesTokenCount ?? null,
  };
  await r.onUsage?.(usage);
  const text = (body?.candidates?.[0]?.content?.parts ?? [])
    .map((p: { text?: string }) => p.text ?? "")
    .join("")
    .trim();
  if (!text) throw new HttpError(502, "server", "Empty response. Please try again.");
  return { text, usage };
}

export async function analyzeImages(r: VisionRequest): Promise<VisionResult> {
  const chain: { name: string; run: () => Promise<VisionResult> }[] = [
    { name: model(), run: () => viaClaude(model(), r) },
  ];
  const backup = fallbackModel();
  if (backup && backup !== model()) {
    chain.push({ name: backup, run: () => viaClaude(backup, r) });
  }
  if (Deno.env.get("GEMINI_API_KEY")) {
    chain.push({ name: "gemini", run: () => viaGemini(r) });
  }

  let last: unknown;
  for (const step of chain) {
    try {
      return await step.run();
    } catch (err) {
      last = err;
      if (!retryable(err)) break;
      console.warn(`AI provider ${step.name} unavailable, trying the next one`);
    }
  }
  if (last instanceof HttpError) throw last;
  mapClaudeError(last);
}
