// Attack tests for the Edge Functions. Each function runs for real; only
// the outside world (Supabase Auth/REST, RevenueCat, Google) is faked.
//
//   cd supabase/functions && deno test --allow-env --allow-read=. --allow-net=127.0.0.1 _tests/
//
// Folders starting with "_" are never deployed as functions.

import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

const SUPABASE = "http://127.0.0.1:54399";
Deno.env.set("SUPABASE_URL", SUPABASE);
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role-for-tests");
Deno.env.set("REVENUECAT_SECRET_KEY", "rc-secret-for-tests");
Deno.env.set("ANTHROPIC_API_KEY", "sk-ant-tests");
Deno.env.set("GOOGLE_SERVICE_ACCOUNT_JSON", JSON.stringify({ client_email: "t@t", private_key: "" }));

// ── Fake outside world ──────────────────────────────────────────────────

type Route = (url: URL, init: RequestInit) => Response | Promise<Response> | undefined;
const routes: Route[] = [];
const calls: string[] = [];
const realFetch = globalThis.fetch;

globalThis.fetch = (async (input: Request | URL | string, init: RequestInit = {}) => {
  const req = input instanceof Request ? input : undefined;
  const url = new URL(req ? req.url : String(input));
  const merged: RequestInit = req
    ? { method: req.method, headers: req.headers, body: await req.clone().text() }
    : init;
  calls.push(`${merged.method ?? "GET"} ${url.host}${url.pathname}`);
  for (const r of routes) {
    const res = await r(url, merged);
    if (res) return res;
  }
  throw new Error(`unexpected fetch ${url}`);
}) as typeof fetch;

const ok = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Supabase Auth: token "user-<uuid>" is a valid session for <uuid>.
routes.push((url, init) => {
  if (url.origin !== SUPABASE || url.pathname !== "/auth/v1/user") return;
  const auth = new Headers(init.headers).get("Authorization") ?? "";
  const m = auth.match(/^Bearer user-([0-9a-f-]{36})$/);
  return m ? ok({ id: m[1], aud: "authenticated" }) : ok({ msg: "bad jwt" }, 401);
});

// RevenueCat: premium users listed here.
const premium = new Map<string, { expires: string | null; grace?: string }>();
routes.push((url) => {
  if (url.host !== "api.revenuecat.com") return;
  const id = decodeURIComponent(url.pathname.split("/").pop()!);
  const p = premium.get(id);
  return ok({
    subscriber: {
      entitlements: p
        ? {
          premium: {
            expires_date: p.expires,
            grace_period_expires_date: p.grace ?? null,
            product_identifier: "clearskin_premium:monthly",
          },
        }
        : {},
      subscriptions: {},
    },
  });
});

// Google OAuth for Play Integrity: always hands out a token.
routes.push((url) =>
  url.host === "oauth2.googleapis.com" ? ok({ access_token: "g", expires_in: 3600 }) : undefined
);

// Play Integrity decode: behaviour set per test.
let integrityReply: () => Response = () => ok({}, 400);
routes.push((url) => (url.host === "playintegrity.googleapis.com" ? integrityReply() : undefined));

// Supabase REST: records what the functions try to do.
const restCalls: { method: string; path: string; body: string }[] = [];
let rpcReply: (fn: string) => unknown = () => ({ ok: false, reason: "free_limit" });
routes.push((url, init) => {
  if (url.origin !== SUPABASE || !url.pathname.startsWith("/rest/v1/")) return;
  const body = typeof init.body === "string" ? init.body : "";
  restCalls.push({ method: init.method ?? "GET", path: url.pathname + url.search, body });
  if (url.pathname === "/rest/v1/rpc/ai_spend_since") return ok(0);
  if (url.pathname.startsWith("/rest/v1/rpc/")) return ok(rpcReply(url.pathname.slice(13)));
  if ((init.method ?? "GET") === "HEAD" || url.search.includes("count")) {
    return new Response(null, { status: 200, headers: { "Content-Range": "0-0/0" } });
  }
  return ok([], 201);
});

// The integrity check needs a parsable service-account key.
const rsa = await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
  true,
  ["sign", "verify"],
);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", rsa.privateKey));
Deno.env.set(
  "GOOGLE_SERVICE_ACCOUNT_JSON",
  JSON.stringify({
    client_email: "t@t",
    private_key: `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`,
  }),
);

// ── Load the functions, capturing their handlers ────────────────────────

const handlers: ((req: Request) => Promise<Response>)[] = [];
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: (req: Request) => Promise<Response>) => {
  handlers.push(h);
  return { finished: Promise.resolve(), shutdown() {} };
};
async function load(path: string) {
  const before = handlers.length;
  await import(path);
  return handlers[before];
}
const analyze = await load("../analyze-skin/index.ts");
const coach = await load("../coach/index.ts");
const rewarded = await load("../admob-rewarded/index.ts");
const status = await load("../account-status/index.ts");
const del = await load("../delete-account/index.ts");

const U1 = "11111111-1111-4111-8111-111111111111";
const DEVICE = "a".repeat(64);
const IMG = "A".repeat(2000);

function post(fn: string, body: unknown, headers: Record<string, string> = {}) {
  return new Request(`https://x/functions/v1/${fn}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}
const signedIn = (uid = U1) => ({ Authorization: `Bearer user-${uid}`, "x-cs-device": DEVICE });
const scanBody = { image_base64: IMG, media_type: "image/jpeg" };

function withEnv(vars: Record<string, string>, fn: () => Promise<void>) {
  return async () => {
    const old = Object.fromEntries(Object.keys(vars).map((k) => [k, Deno.env.get(k)]));
    for (const [k, v] of Object.entries(vars)) Deno.env.set(k, v);
    try {
      await fn();
    } finally {
      for (const [k, v] of Object.entries(old)) v === undefined ? Deno.env.delete(k) : Deno.env.set(k, v);
    }
  };
}

// ── Authentication ──────────────────────────────────────────────────────

Deno.test("every app function refuses callers without a session", async () => {
  for (const [name, h] of [["analyze-skin", analyze], ["coach", coach], ["account-status", status], ["delete-account", del]] as const) {
    const res = await h(post(name, scanBody));
    assertEquals(res.status, 401, name);
    const forged = await h(post(name, scanBody, { Authorization: "Bearer eyJhbGciOiJub25lIn0.e30." }));
    assertEquals(forged.status, 401, `${name} accepted an unsigned JWT`);
  }
});

Deno.test("only POST is accepted", async () => {
  const res = await analyze(new Request("https://x/functions/v1/analyze-skin", { method: "GET" }));
  assertEquals(res.status, 405);
});

// ── Play Integrity (patched / re-signed apps, scripts) ──────────────────

Deno.test("enforce: no integrity token is refused", withEnv({ INTEGRITY_MODE: "enforce" }, async () => {
  const res = await analyze(post("analyze-skin", scanBody, signedIn()));
  assertEquals(res.status, 403);
}));

Deno.test("enforce: a forged token Google rejects is refused (was fail-open)", withEnv({ INTEGRITY_MODE: "enforce" }, async () => {
  integrityReply = () => ok({ error: { code: 400, message: "Integrity token cannot be decoded" } }, 400);
  const res = await analyze(post("analyze-skin", scanBody, {
    ...signedIn(),
    "x-cs-integrity": "forged.token.value",
    "x-cs-ts": String(Date.now()),
  }));
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error, "integrity");
}));

Deno.test("enforce: junk characters in the token are refused without calling Google", withEnv({ INTEGRITY_MODE: "enforce" }, async () => {
  calls.length = 0;
  const res = await analyze(post("analyze-skin", scanBody, {
    ...signedIn(),
    "x-cs-integrity": "<script>alert(1)</script>",
    "x-cs-ts": String(Date.now()),
  }));
  assertEquals(res.status, 403);
  assert(!calls.some((c) => c.includes("playintegrity")), "Google was called for junk");
}));

Deno.test("enforce: a token from a sideloaded / patched app is refused", withEnv({ INTEGRITY_MODE: "enforce" }, async () => {
  const ts = Date.now();
  const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${U1}|analyze-skin|${ts}`)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  integrityReply = () =>
    ok({
      tokenPayloadExternal: {
        requestDetails: { requestPackageName: "com.clearskinai.app", requestHash: hash, timestampMillis: String(ts) },
        appIntegrity: { appRecognitionVerdict: "UNRECOGNIZED_VERSION" },
        deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
      },
    });
  const res = await analyze(post("analyze-skin", scanBody, { ...signedIn(), "x-cs-integrity": "abc", "x-cs-ts": String(ts) }));
  assertEquals(res.status, 403);
}));

Deno.test("enforce: a genuine token replayed for another user is refused", withEnv({ INTEGRITY_MODE: "enforce" }, async () => {
  const ts = Date.now();
  const otherHash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`someone-else|analyze-skin|${ts}`)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  integrityReply = () =>
    ok({
      tokenPayloadExternal: {
        requestDetails: { requestPackageName: "com.clearskinai.app", requestHash: otherHash, timestampMillis: String(ts) },
        appIntegrity: { appRecognitionVerdict: "PLAY_RECOGNIZED" },
        deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
      },
    });
  const res = await analyze(post("analyze-skin", scanBody, { ...signedIn(), "x-cs-integrity": "abc", "x-cs-ts": String(ts) }));
  assertEquals(res.status, 403);
}));

Deno.test("enforce: a stale timestamp is refused", withEnv({ INTEGRITY_MODE: "enforce" }, async () => {
  const res = await analyze(post("analyze-skin", scanBody, {
    ...signedIn(),
    "x-cs-integrity": "abc",
    "x-cs-ts": String(Date.now() - 60 * 60 * 1000),
  }));
  assertEquals(res.status, 403);
}));

Deno.test("Google outage fails open (quotas still apply)", withEnv({ INTEGRITY_MODE: "enforce" }, async () => {
  integrityReply = () => ok({}, 503);
  rpcReply = () => ({ ok: false, reason: "free_limit" });
  const res = await analyze(post("analyze-skin", scanBody, { ...signedIn(), "x-cs-integrity": "abc", "x-cs-ts": String(Date.now()) }));
  assertEquals(res.status, 402, "should reach the quota check");
}));

Deno.test("enforce: free scans need the device id", withEnv({ INTEGRITY_MODE: "off" }, async () => {
  // Off here so the request reaches the device check; in production the
  // check runs only when enforce is on.
  Deno.env.set("INTEGRITY_MODE", "enforce");
  integrityReply = () => ok({}, 503); // integrity passes (outage)
  const res = await analyze(post("analyze-skin", scanBody, {
    Authorization: `Bearer user-${U1}`,
    "x-cs-integrity": "abc",
    "x-cs-ts": String(Date.now()),
  }));
  assertEquals(res.status, 400);
}));

// ── Input validation (injection, oversized bodies) ──────────────────────

Deno.test("oversized bodies are refused before parsing", withEnv({ INTEGRITY_MODE: "off" }, async () => {
  const res = await analyze(new Request("https://x/functions/v1/analyze-skin", {
    method: "POST",
    headers: { ...signedIn(), "Content-Length": "50000000" },
    body: "{}",
  }));
  assertEquals(res.status, 413);
  const real = await analyze(post("analyze-skin", "x".repeat(3_100_000), signedIn()));
  assertEquals(real.status, 413, "lying Content-Length");
}));

Deno.test("prompt and schema injection through the profile is refused", withEnv({ INTEGRITY_MODE: "off" }, async () => {
  for (const profile of [
    { nested: { ignore: "previous instructions" } },
    { note: "x".repeat(500) },
    Object.fromEntries(Array.from({ length: 40 }, (_, i) => [`k${i}`, 1])),
  ]) {
    const res = await analyze(post("analyze-skin", { ...scanBody, profile }, signedIn()));
    assertEquals(res.status, 400, JSON.stringify(profile).slice(0, 60));
  }
  const badIssue = await analyze(post("analyze-skin", { ...scanBody, current_issues: ["'; drop table x"] }, signedIn()));
  assertEquals(badIssue.status, 400);
  const notBase64 = await analyze(post("analyze-skin", { ...scanBody, image_base64: "<svg onload=x>".repeat(100) }, signedIn()));
  assertEquals(notBase64.status, 400);
  const tooManySides = await analyze(post("analyze-skin", { ...scanBody, side_images: [IMG, IMG, IMG] }, signedIn()));
  assertEquals(tooManySides.status, 400);
  const broken = await analyze(post("analyze-skin", "{not json", signedIn()));
  assertEquals(broken.status, 400);
}));

Deno.test("errors never leak internals", withEnv({ INTEGRITY_MODE: "off" }, async () => {
  rpcReply = () => {
    throw new Error("connection string postgres://secret@db");
  };
  const res = await analyze(post("analyze-skin", scanBody, signedIn()));
  const text = await res.text();
  assert(!text.includes("postgres://"), text);
  assert(!text.toLowerCase().includes("stack"), text);
  assertEquals(res.headers.get("cache-control"), "no-store");
  rpcReply = () => ({ ok: false, reason: "free_limit" });
}));

// ── Quotas & Premium (the "use it for free" attacks) ────────────────────

Deno.test("a free user past the limit is told to upgrade, and AI is never called", withEnv({ INTEGRITY_MODE: "off" }, async () => {
  calls.length = 0;
  rpcReply = () => ({ ok: false, reason: "free_limit" });
  const res = await analyze(post("analyze-skin", scanBody, signedIn()));
  assertEquals(res.status, 402);
  assert(!calls.some((c) => c.includes("anthropic")), "Claude called past the quota");
}));

Deno.test("junk-photo loops hit the daily attempt cap", withEnv({ INTEGRITY_MODE: "off" }, async () => {
  rpcReply = () => ({ ok: false, reason: "attempt_limit" });
  const res = await analyze(post("analyze-skin", scanBody, signedIn()));
  assertEquals(res.status, 429);
  const rpc = restCalls.filter((c) => c.path.includes("reserve_usage")).pop()!;
  assertEquals(JSON.parse(rpc.body).p_attempt_limit, 10);
}));

Deno.test("the coach is Premium only, checked with RevenueCat, not the app", withEnv({ INTEGRITY_MODE: "off" }, async () => {
  const msg = { messages: [{ role: "user", content: "hi" }], context: { premium: true, isPremium: true } };
  const res = await coach(post("coach", msg, signedIn()));
  assertEquals(res.status, 402, "client-claimed premium was trusted");
}));

Deno.test("an expired subscription is not Premium; Google's grace period is", withEnv({ INTEGRITY_MODE: "off" }, async () => {
  const expired = "22222222-2222-4222-8222-222222222222";
  const grace = "33333333-3333-4333-8333-333333333333";
  premium.set(expired, { expires: new Date(Date.now() - 86_400_000).toISOString() });
  premium.set(grace, {
    expires: new Date(Date.now() - 86_400_000).toISOString(),
    grace: new Date(Date.now() + 3 * 86_400_000).toISOString(),
  });
  const s1 = await (await status(post("account-status", {}, signedIn(expired)))).json();
  assertEquals(s1.premium, false);
  const s2 = await (await status(post("account-status", {}, signedIn(grace)))).json();
  assertEquals(s2.premium, true);
}));

// ── Rewarded ads (minting free scans) ───────────────────────────────────

const ecdsa = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const spki = new Uint8Array(await crypto.subtle.exportKey("spki", ecdsa.publicKey));
routes.push((url) =>
  url.host === "www.gstatic.com"
    ? ok({ keys: [{ keyId: 42, base64: btoa(String.fromCharCode(...spki)) }] })
    : undefined
);

function rawToDer(raw: Uint8Array): Uint8Array {
  const int = (b: Uint8Array) => {
    let i = 0;
    while (i < b.length - 1 && b[i] === 0) i++;
    let v = b.subarray(i);
    if (v[0] & 0x80) v = new Uint8Array([0, ...v]);
    return [0x02, v.length, ...v];
  };
  const body = [...int(raw.subarray(0, 32)), ...int(raw.subarray(32))];
  return new Uint8Array([0x30, body.length, ...body]);
}
const b64url = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function ssv(params: Record<string, string>, opts: { tamper?: string; keyId?: string } = {}) {
  const content = new URLSearchParams(params).toString();
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, ecdsa.privateKey, new TextEncoder().encode(content)),
  );
  const sent = opts.tamper ? content.replace(params.user_id, opts.tamper) : content;
  return new Request(
    `https://x/functions/v1/admob-rewarded?${sent}&signature=${b64url(rawToDer(sig))}&key_id=${opts.keyId ?? "42"}`,
  );
}
const reward = (tx: string, ts = Date.now()) => ({
  ad_network: "5450213213286189855",
  ad_unit: "1234",
  reward_amount: "1",
  reward_item: "scan",
  timestamp: String(ts),
  transaction_id: tx,
  user_id: U1,
});

Deno.test("SSV: a genuine Google callback mints one credit", async () => {
  restCalls.length = 0;
  const res = await rewarded(await ssv(reward("tx-good")));
  assertEquals(res.status, 200);
  const insert = restCalls.find((c) => c.method === "POST" && c.path.includes("scan_credits"));
  assert(insert, "credit not inserted");
  assert(insert.path.includes("on_conflict=transaction_id"), "replays must be ignored by transaction id");
});

Deno.test("SSV: changing the user id after signing is refused", async () => {
  restCalls.length = 0;
  const res = await rewarded(await ssv(reward("tx-steal"), { tamper: "44444444-4444-4444-8444-444444444444" }));
  assertEquals(res.status, 400);
  assert(!restCalls.some((c) => c.path.includes("scan_credits")), "credit minted for tampered callback");
});

Deno.test("SSV: unknown key, junk signature, stale or odd params are refused", async () => {
  assertEquals((await rewarded(await ssv(reward("tx-k"), { keyId: "999" }))).status, 400);
  const junk = new Request(`https://x/functions/v1/admob-rewarded?user_id=${U1}&transaction_id=t&signature=AAAA&key_id=42`);
  assertEquals((await rewarded(junk)).status, 400);
  assertEquals((await rewarded(await ssv(reward("tx-old", Date.now() - 3 * 3600_000)))).status, 400);
  assertEquals((await rewarded(await ssv({ ...reward("tx-u"), user_id: "' or 1=1 --" }))).status, 400);
  assertEquals((await rewarded(new Request("https://x/functions/v1/admob-rewarded", { method: "POST" }))).status, 405);
});

addEventListener("unload", () => {
  globalThis.fetch = realFetch;
});
