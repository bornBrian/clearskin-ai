// Shared helpers for ClearSkin Edge Functions (Deno).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

const SECURITY_HEADERS = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: SECURITY_HEADERS });
}

/** Maps any thrown error to a JSON response the app understands. Internal
 * details are logged, never returned. */
export function errorResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    return json({ error: err.code, message: err.message }, err.status);
  }
  console.error("Unhandled error", err);
  return json(
    { error: "server", message: "Something went wrong on our side. Please try again." },
    500,
  );
}

export function env(name: string, fallback?: string): string {
  const v = Deno.env.get(name) ?? fallback;
  if (v === undefined || v === "") throw new Error(`Missing env var ${name}`);
  return v;
}

export function intEnv(name: string, fallback: number): number {
  const v = Number(Deno.env.get(name));
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

/**
 * Reads a JSON body with a hard size cap, so nobody can make a function
 * buffer hundreds of megabytes. Content-Length is checked first, then the
 * real byte count (the header can lie).
 */
export async function readJson(req: Request, maxBytes: number): Promise<unknown> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > maxBytes) throw new HttpError(413, "too_large", "That request is too large.");
  const reader = req.body?.getReader();
  if (!reader) return null;
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw new HttpError(413, "too_large", "That request is too large.");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    bytes.set(c, offset);
    offset += c.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new HttpError(400, "bad_request", "Invalid request.");
  }
}

let admin: SupabaseClient | undefined;

/** Service-role client. Never exposed to the app. */
export function adminClient(): SupabaseClient {
  admin ??= createClient(
    env("SUPABASE_URL"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  return admin;
}

/** Verifies the caller's Supabase JWT and returns their user id. */
export async function requireUser(req: Request): Promise<string> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) throw new HttpError(401, "unauthorized", "Please restart the app and try again.");
  const { data, error } = await adminClient().auth.getUser(token);
  if (error || !data.user) {
    throw new HttpError(401, "unauthorized", "Your session expired. Please restart the app.");
  }
  return data.user.id;
}

/** The app-scoped device hash from `x-cs-device`, or null. Strictly
 * validated: it goes into a parameterised query, but garbage is still
 * rejected rather than stored. */
export function deviceHash(req: Request): string | null {
  const v = (req.headers.get("x-cs-device") ?? "").toLowerCase();
  return /^[0-9a-f]{64}$/.test(v) ? v : null;
}

// ── Entitlements (RevenueCat) ─────────────────────────────────────────

export interface Entitlement {
  premium: boolean;
  expiresAt: string | null;
  willRenew: boolean;
  billingIssue: boolean;
}

const FREE: Entitlement = { premium: false, expiresAt: null, willRenew: false, billingIssue: false };
const entitlementCache = new Map<string, { value: Entitlement; at: number }>();
const CACHE_MS = 2 * 60 * 1000;

/**
 * Server-side Premium check against RevenueCat's REST API. RevenueCat
 * validates every purchase token with Google, so a patched app that fakes
 * a purchase gets nothing here. The app's own Premium flag is never
 * trusted for paid AI features.
 */
export async function entitlement(userId: string): Promise<Entitlement> {
  const cached = entitlementCache.get(userId);
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.value;

  const secret = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!secret) {
    console.warn("REVENUECAT_SECRET_KEY not set; treating all users as free");
    return FREE;
  }
  const name = Deno.env.get("REVENUECAT_ENTITLEMENT") ?? "premium";
  let res: Response;
  try {
    res = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
      { headers: { Authorization: `Bearer ${secret}` }, signal: AbortSignal.timeout(8000) },
    );
  } catch (err) {
    console.error("RevenueCat unreachable", err);
    return FREE;
  }
  if (!res.ok) {
    console.error("RevenueCat lookup failed", res.status);
    // Fail closed for paid features, but don't cache the failure.
    return FREE;
  }
  const body = await res.json();
  const ent = body?.subscriber?.entitlements?.[name];
  if (!ent) {
    entitlementCache.set(userId, { value: FREE, at: Date.now() });
    return FREE;
  }
  const expires = ent.expires_date ? Date.parse(ent.expires_date) : null;
  const grace = ent.grace_period_expires_date ? Date.parse(ent.grace_period_expires_date) : null;
  const until = expires === null ? null : Math.max(expires, grace ?? 0);
  const sub = body?.subscriber?.subscriptions?.[ent.product_identifier] ?? {};
  const value: Entitlement = {
    premium: until === null || until > Date.now(),
    expiresAt: until === null ? null : new Date(until).toISOString(),
    willRenew: !sub.unsubscribe_detected_at && !sub.billing_issues_detected_at &&
      sub.period_type !== "prepaid",
    billingIssue: !!sub.billing_issues_detected_at,
  };
  entitlementCache.set(userId, { value, at: Date.now() });
  return value;
}

export async function isPremium(userId: string): Promise<boolean> {
  return (await entitlement(userId)).premium;
}

// ── Usage reservations (atomic quotas, see the SQL migration) ─────────

export type UsageKind = "scan" | "coach";

export interface Reservation {
  eventId: number;
  usedCredit: boolean;
}

export async function reserveUsage(opts: {
  userId: string;
  kind: UsageKind;
  device: string | null;
  premium: boolean;
  freeLimit: number;
  windowDays: number;
  dailyLimit: number;
  /** Attempts per account or device in 24 h, refunded ones included. */
  attemptLimit: number;
}): Promise<Reservation | { blocked: "free_limit" | "daily_limit" | "attempt_limit" }> {
  const { data, error } = await adminClient().rpc("reserve_usage", {
    p_user: opts.userId,
    p_kind: opts.kind,
    p_device: opts.device,
    p_premium: opts.premium,
    p_free_limit: opts.freeLimit,
    p_window: `${opts.windowDays} days`,
    p_daily_limit: opts.dailyLimit,
    p_attempt_limit: opts.attemptLimit,
  });
  if (error) throw error;
  if (!data?.ok) return { blocked: data?.reason ?? "free_limit" };
  return { eventId: data.event_id, usedCredit: !!data.used_credit };
}

export async function releaseUsage(eventId: number): Promise<void> {
  const { error } = await adminClient().rpc("release_usage", { p_event: eventId });
  if (error) console.error("Failed to release usage", error);
}

export interface ClaudeUsage {
  model: string;
  input_tokens?: number | null;
  output_tokens?: number | null;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
}

/** Marks a reservation as spent and records what it cost. */
export async function finishUsage(eventId: number, usage: ClaudeUsage): Promise<void> {
  const { error } = await adminClient()
    .from("usage_events")
    .update({
      status: "done",
      model: usage.model,
      input_tokens: usage.input_tokens ?? null,
      output_tokens: usage.output_tokens ?? null,
      cache_read_tokens: usage.cache_read_input_tokens ?? null,
      cache_write_tokens: usage.cache_creation_input_tokens ?? null,
      cost_usd: costUsd(usage),
    })
    .eq("id", eventId);
  if (error) console.error("Failed to record usage", error);
  spendCache = undefined;
}

// ── Cost control ───────────────────────────────────────────────────────

/** USD per million tokens: [input, output]. Cache reads bill at 0.1x of
 * input on most models (Opus 5.5 and Sonnet 5.5 at a flat $0.20) and cache
 * writes at 1.25x. Thinking tokens are part of output_tokens. */
const PRICES: Record<string, [number, number, number]> = {
  "claude-opus-5-5": [4, 20, 0.2],
  "claude-sonnet-5-5": [2, 10, 0.2],
  "claude-haiku-5-5": [0.1, 0.5, 0.01],
};

export function costUsd(u: ClaudeUsage): number {
  const key = Object.keys(PRICES).find((k) => u.model.startsWith(k));
  const [inp, out, read] = key ? PRICES[key] : [4, 20, 0.4];
  const usd = ((u.input_tokens ?? 0) * inp +
    (u.cache_creation_input_tokens ?? 0) * inp * 1.25 +
    (u.cache_read_input_tokens ?? 0) * read +
    (u.output_tokens ?? 0) * out) / 1_000_000;
  return Math.round(usd * 1_000_000) / 1_000_000;
}

let spendCache: { usd: number; at: number } | undefined;

/**
 * Circuit breaker: once today's total AI spend passes DAILY_SPEND_LIMIT_USD,
 * new AI calls are refused until midnight UTC. Protects the Anthropic bill
 * from abuse, bugs or a viral spike you haven't budgeted for.
 */
export async function requireSpendHeadroom(): Promise<void> {
  const limit = intEnv("DAILY_SPEND_LIMIT_USD", 25);
  if (!spendCache || Date.now() - spendCache.at > 60_000) {
    const since = new Date();
    since.setUTCHours(0, 0, 0, 0);
    const { data, error } = await adminClient().rpc("ai_spend_since", {
      p_since: since.toISOString(),
    });
    if (error) {
      console.error("Spend check failed", error);
      return;
    }
    spendCache = { usd: Number(data ?? 0), at: Date.now() };
  }
  if (spendCache.usd >= limit) {
    console.error(`Daily AI spend limit reached: $${spendCache.usd.toFixed(2)} >= $${limit}`);
    throw new HttpError(
      503,
      "busy",
      "ClearSkin is very busy right now. Please try again in a few hours.",
    );
  }
}
