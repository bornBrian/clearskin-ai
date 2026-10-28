import Anthropic from "npm:@anthropic-ai/sdk@1.2.0";
import { env, HttpError } from "./common.ts";

let client: Anthropic | undefined;

export function claude(): Anthropic {
  client ??= new Anthropic({
    apiKey: env("ANTHROPIC_API_KEY"),
    // Vision analysis with adaptive thinking can take a while; the app waits
    // up to 90 s, so give the API a little less than that.
    timeout: 80_000,
    maxRetries: 1,
  });
  return client;
}

/** Model is configurable without an app release (set CLAUDE_MODEL). */
export function model(): string {
  return Deno.env.get("CLAUDE_MODEL") ?? "claude-opus-5-5";
}

/** Used when the primary model is overloaded or down (see ai.ts). Set
 * CLAUDE_FALLBACK_MODEL to "" to disable. */
export function fallbackModel(): string {
  return Deno.env.get("CLAUDE_FALLBACK_MODEL") ?? "claude-sonnet-5-5";
}

/**
 * Server-side refusal fallback: if a safety classifier declines a request
 * (rare false positives on medical-adjacent photos), the API re-runs it on
 * Anthropic's recommended fallback model inside the same call.
 */
export const FALLBACK_BETA = "server-side-fallback-2026-07-01";

/** Extracts the final text block, after checking why generation stopped. */
export function finalText(msg: Anthropic.Beta.BetaMessage): string {
  if (msg.stop_reason === "refusal") {
    throw new HttpError(
      422,
      "bad_image",
      "We couldn't analyse that photo. Please retake a clear, front-facing selfie.",
    );
  }
  if (msg.stop_reason === "max_tokens") {
    throw new HttpError(502, "server", "The analysis was cut short. Please try again.");
  }
  const text = msg.content
    .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();
  if (!text) throw new HttpError(502, "server", "Empty response. Please try again.");
  return text;
}

export function mapClaudeError(err: unknown): never {
  if (err instanceof HttpError) throw err;
  if (err instanceof Anthropic.RateLimitError) {
    throw new HttpError(503, "server", "We're very busy right now. Please try again in a minute.");
  }
  if (err instanceof Anthropic.APIConnectionTimeoutError) {
    throw new HttpError(504, "server", "The analysis took too long. Please try again.");
  }
  if (err instanceof Anthropic.BadRequestError) {
    console.error("Claude bad request", err.message);
    throw new HttpError(422, "bad_image", "We couldn't process that photo. Please try another.");
  }
  if (err instanceof Anthropic.APIError) {
    console.error("Claude API error", err.status, err.message);
    throw new HttpError(502, "server", "Our AI service had a hiccup. Please try again.");
  }
  throw err;
}
