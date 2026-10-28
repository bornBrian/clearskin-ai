// Proves a call comes from the genuine ClearSkin app on a real phone: Play
// Integrity (standard requests) on Android, App Attest on iPhone. This is
// what stops patched/re-signed apps and scripts that replay the public
// Supabase key from spending our Claude budget.
//
// The app binds its proof to a request hash
//   sha256("<user id>|<function>|<x-cs-ts>")
// and sends it in `x-cs-integrity`: a Play Integrity token, which Google
// decrypts for us, or "ios.<key id>.<assertion>", checked in app_attest.ts
// against the key the app registered.
//
// INTEGRITY_MODE:
//   off      - skip (local development)
//   log      - check and log, never block (default; use while testing
//              sideloaded builds, which Google reports as unrecognised)
//   enforce  - reject anything that isn't a Play-recognised app on a
//              device that meets integrity, or an attested iPhone app
//              (use from the production launch)

import { AttestError, clientDataHash, verifyAssertion } from "./app_attest.ts";
import { adminClient, HttpError } from "./common.ts";

type Mode = "off" | "log" | "enforce";

function mode(): Mode {
  const m = Deno.env.get("INTEGRITY_MODE");
  return m === "off" || m === "enforce" ? m : "log";
}

export function integrityEnforced(): boolean {
  return mode() === "enforce";
}

/** Google refused the token itself (forged, truncated, wrong app): that's
 * a failed check, not an outage. */
class RejectedToken extends Error {}

const MAX_SKEW_MS = 5 * 60 * 1000;

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Verifies the caller's integrity token for [fn]. Throws 403 in enforce
 * mode when the verdict is bad; otherwise logs and returns.
 */
export async function requireIntegrity(req: Request, userId: string, fn: string): Promise<void> {
  const m = mode();
  if (m === "off") return;

  const fail = (why: string) => {
    if (m === "enforce") {
      throw new HttpError(
        403,
        "integrity",
        "This copy of ClearSkin can't be verified. Please install it from the App Store or Google Play.",
      );
    }
    console.warn(`integrity(${fn}) would block: ${why}`);
  };

  const token = req.headers.get("x-cs-integrity") ?? "";
  const ts = Number(req.headers.get("x-cs-ts"));
  if (!token) return fail("no token");
  if (!Number.isFinite(ts) || Math.abs(Date.now() - ts) > MAX_SKEW_MS) {
    return fail("stale or missing timestamp");
  }

  if (token.length > 8000 || !/^[A-Za-z0-9._-]+$/.test(token)) return fail("malformed token");

  if (token.startsWith("ios.")) {
    const why = await checkAppAttest(token, userId, fn, ts);
    return why ? fail(why) : undefined;
  }

  let verdict: Verdict;
  try {
    verdict = await decode(token);
  } catch (err) {
    if (err instanceof RejectedToken) return fail(err.message);
    // Google being unreachable shouldn't take the app down: fail open and
    // log loudly. Quotas and the spend limit still bound the damage.
    console.error("Play Integrity decode failed", err);
    return;
  }

  const expectedHash = await sha256Hex(`${userId}|${fn}|${ts}`);
  const pkg = Deno.env.get("ANDROID_PACKAGE") ?? "com.clearskinai.app";
  const d = verdict.requestDetails ?? {};
  if (d.requestPackageName !== pkg) return fail(`package ${d.requestPackageName}`);
  if (d.requestHash !== expectedHash) return fail("request hash mismatch");
  if (Math.abs(Date.now() - Number(d.timestampMillis ?? 0)) > MAX_SKEW_MS) {
    return fail("token too old");
  }
  if (verdict.appIntegrity?.appRecognitionVerdict !== "PLAY_RECOGNIZED") {
    return fail(`app ${verdict.appIntegrity?.appRecognitionVerdict}`);
  }
  const device = verdict.deviceIntegrity?.deviceRecognitionVerdict ?? [];
  if (!device.includes("MEETS_DEVICE_INTEGRITY")) {
    return fail(`device ${device.join(",") || "none"}`);
  }
}

/** Null when the assertion is good; otherwise why not. Database errors fail
 * open, like a Google outage. */
async function checkAppAttest(token: string, userId: string, fn: string, ts: number): Promise<string | null> {
  const [, keyId, assertion, extra] = token.split(".");
  if (!keyId || !assertion || extra !== undefined || !/^[A-Za-z0-9_-]{43}$/.test(keyId)) {
    return "malformed App Attest token";
  }
  const db = adminClient();
  const { data: key, error } = await db.from("app_attest_keys")
    .select("public_key, sign_count")
    .eq("key_id", keyId)
    .maybeSingle();
  if (error) {
    console.error("App Attest key lookup failed", error.message);
    return null;
  }
  if (!key) return "unknown App Attest key";
  let counter: number;
  try {
    counter = await verifyAssertion(
      assertion,
      hexToBytes(key.public_key as string),
      Number(key.sign_count),
      await clientDataHash(userId, fn, ts),
    );
  } catch (err) {
    if (err instanceof AttestError) return err.message;
    console.error("App Attest check failed", err);
    return null;
  }
  // Only a higher counter is stored, in one statement: two calls racing
  // with the same assertion can't both get through.
  const { data: bumped, error: bumpError } = await db.from("app_attest_keys")
    .update({ sign_count: counter, last_used_at: new Date().toISOString() })
    .eq("key_id", keyId)
    .lt("sign_count", counter)
    .select("key_id");
  if (bumpError) {
    console.error("App Attest counter update failed", bumpError.message);
    return null;
  }
  return bumped?.length ? null : "replayed assertion";
}

/** PostgREST returns bytea as "\x<hex>". */
function hexToBytes(value: string): Uint8Array<ArrayBuffer> {
  const hex = value.startsWith("\\x") ? value.slice(2) : value;
  if (!/^(?:[0-9a-f]{2})+$/i.test(hex)) throw new Error("stored key isn't hex");
  return Uint8Array.from(hex.match(/../g)!, (h) => parseInt(h, 16));
}

interface Verdict {
  requestDetails?: { requestPackageName?: string; requestHash?: string; timestampMillis?: string };
  appIntegrity?: { appRecognitionVerdict?: string };
  deviceIntegrity?: { deviceRecognitionVerdict?: string[] };
}

async function decode(token: string): Promise<Verdict> {
  const pkg = Deno.env.get("ANDROID_PACKAGE") ?? "com.clearskinai.app";
  const res = await fetch(
    `https://playintegrity.googleapis.com/v1/${encodeURIComponent(pkg)}:decodeIntegrityToken`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await googleAccessToken()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ integrity_token: token }),
      signal: AbortSignal.timeout(8000),
    },
  );
  // 400 means Google looked at the token and refused it. 401/403 are our
  // own credentials (a setup problem) and 5xx is Google being down; those
  // are logged and let through rather than locking every user out.
  if (res.status === 400) throw new RejectedToken("token rejected");
  if (!res.ok) throw new Error(`decodeIntegrityToken ${res.status}`);
  const body = await res.json();
  return body.tokenPayloadExternal ?? {};
}

// ── Google service-account OAuth (JWT bearer grant) ────────────────────

let cachedToken: { value: string; expires: number } | undefined;

async function googleAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expires > Date.now() + 60_000) return cachedToken.value;

  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON not set");
  // Accept the JSON as-is or base64-encoded (easier to paste into secrets).
  const sa = JSON.parse(raw.trim().startsWith("{") ? raw : atob(raw));

  const now = Math.floor(Date.now() / 1000);
  const b64url = (data: Uint8Array | string) => {
    const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
    let s = "";
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/playintegrity",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const pem = (sa.private_key as string)
    .replace(/-----[^-]+-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  const assertion = `${header}.${claims}.${b64url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`Google OAuth ${res.status}`);
  const body = await res.json();
  cachedToken = { value: body.access_token, expires: Date.now() + body.expires_in * 1000 };
  return cachedToken.value;
}
