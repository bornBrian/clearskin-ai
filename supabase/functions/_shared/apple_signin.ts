// Sign in with Apple, server side: turning the app's one-time authorization
// code into a refresh token, and revoking it when the account is deleted
// (App Store Review Guideline 5.1.1(v)).
//
// APPLE_TEAM_ID         10-character team id
// APPLE_SIGN_IN_KEY_ID  key id of a "Sign in with Apple" key
// APPLE_SIGN_IN_KEY     that key's .p8 contents (PEM, or base64 of it)
// APPLE_CLIENT_ID       the bundle id, com.clearskinai.app (default)

import { base64Decode, base64UrlEncode } from "./encoding.ts";

const APPLE = "https://appleid.apple.com";

export function appleSignInConfigured(): boolean {
  return !!(Deno.env.get("APPLE_TEAM_ID") && Deno.env.get("APPLE_SIGN_IN_KEY_ID") &&
    Deno.env.get("APPLE_SIGN_IN_KEY"));
}

function clientId(): string {
  return Deno.env.get("APPLE_CLIENT_ID") ?? "com.clearskinai.app";
}

/** The ES256 JWT Apple takes as client_secret (valid 5 minutes). */
async function clientSecret(): Promise<string> {
  let pem = Deno.env.get("APPLE_SIGN_IN_KEY") ?? "";
  if (!pem.includes("BEGIN")) pem = new TextDecoder().decode(base64Decode(pem.trim()));
  const der = base64Decode(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, ""));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = (o: unknown) => base64UrlEncode(new TextEncoder().encode(JSON.stringify(o)));
  const now = Math.floor(Date.now() / 1000);
  const body = `${enc({ alg: "ES256", kid: Deno.env.get("APPLE_SIGN_IN_KEY_ID") })}.${
    enc({ iss: Deno.env.get("APPLE_TEAM_ID"), iat: now, exp: now + 300, aud: APPLE, sub: clientId() })
  }`;
  // WebCrypto's ECDSA output is already JWS's raw r‖s.
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(body)),
  );
  return `${body}.${base64UrlEncode(sig)}`;
}

/** Exchanges the app's authorization code; null if Apple refuses it. */
export async function exchangeCode(code: string): Promise<string | null> {
  const res = await fetch(`${APPLE}/auth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: await clientSecret(),
      code,
      grant_type: "authorization_code",
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (res.status === 400) return null;
  if (!res.ok) throw new Error(`Apple token ${res.status}`);
  const body = await res.json() as { refresh_token?: unknown };
  return typeof body.refresh_token === "string" ? body.refresh_token : null;
}

/** Revokes ClearSkin's access; true when Apple confirms. */
export async function revokeToken(refreshToken: string): Promise<boolean> {
  const res = await fetch(`${APPLE}/auth/revoke`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: await clientSecret(),
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
    signal: AbortSignal.timeout(10_000),
  });
  return res.ok;
}
