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

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Maps any thrown error to a JSON response the app understands. */
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

// ── Entitlements (RevenueCat) ─────────────────────────────────────────

const entitlementCache = new Map<string, { premium: boolean; at: number }>();
const CACHE_MS = 5 * 60 * 1000;

/**
 * Server-side Premium check against RevenueCat's REST API. The app's own
 * Premium flag is never trusted for paid AI features.
 */
export async function isPremium(userId: string): Promise<boolean> {
  const cached = entitlementCache.get(userId);
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.premium;

  const secret = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!secret) {
    console.warn("REVENUECAT_SECRET_KEY not set; treating all users as free");
    return false;
  }
  const entitlement = Deno.env.get("REVENUECAT_ENTITLEMENT") ?? "premium";
  const res = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
    { headers: { Authorization: `Bearer ${secret}` } },
  );
  if (!res.ok) {
    console.error("RevenueCat lookup failed", res.status);
    // Fail closed for paid features, but don't cache the failure.
    return false;
  }
  const body = await res.json();
  const ent = body?.subscriber?.entitlements?.[entitlement];
  const expires = ent?.expires_date ? Date.parse(ent.expires_date) : null;
  const premium = !!ent && (expires === null || expires > Date.now());
  entitlementCache.set(userId, { premium, at: Date.now() });
  return premium;
}

// ── Usage quotas ───────────────────────────────────────────────────────

export type UsageKind = "scan" | "coach";

export async function countUsage(
  userId: string,
  kind: UsageKind,
  since?: Date,
): Promise<number> {
  let q = adminClient()
    .from("usage_events")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("kind", kind);
  if (since) q = q.gte("created_at", since.toISOString());
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

export async function recordUsage(
  userId: string,
  kind: UsageKind,
  usage: { model: string; input_tokens?: number; output_tokens?: number },
): Promise<void> {
  const { error } = await adminClient().from("usage_events").insert({
    user_id: userId,
    kind,
    model: usage.model,
    input_tokens: usage.input_tokens ?? null,
    output_tokens: usage.output_tokens ?? null,
  });
  if (error) console.error("Failed to record usage", error);
}

export function startOfUtcDay(): Date {
  const d = new Date();
  d.setUTCHours(0, 0, 0, 0);
  return d;
}

export function intEnv(name: string, fallback: number): number {
  const v = Number(Deno.env.get(name));
  return Number.isFinite(v) && v > 0 ? v : fallback;
}
