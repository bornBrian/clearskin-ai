// A stand-in for Apple's App Attest service: our own root, intermediate and
// per-key certificates, built exactly the way Apple builds theirs, so the
// real verification code in _shared/app_attest.ts runs unchanged against
// genuine-looking and forged attestations alike.

import { concat, sha256 } from "../_shared/encoding.ts";

export const APP_ID = "TEAMID1234.com.clearskinai.app";

// ── DER ───────────────────────────────────────────────────────────────

function derLength(n: number): Uint8Array {
  if (n < 0x80) return new Uint8Array([n]);
  if (n < 0x100) return new Uint8Array([0x81, n]);
  return new Uint8Array([0x82, n >> 8, n & 0xff]);
}
const tlv = (tag: number, ...parts: Uint8Array[]) => {
  const body = concat(...parts);
  return concat(new Uint8Array([tag]), derLength(body.length), body);
};
const seq = (...parts: Uint8Array[]) => tlv(0x30, ...parts);

function oid(text: string): Uint8Array {
  const [a, b, ...rest] = text.split(".").map(Number);
  const out = [40 * a + b];
  for (const arc of rest) {
    const chunk = [arc & 0x7f];
    for (let n = arc >> 7; n > 0; n >>= 7) chunk.unshift((n & 0x7f) | 0x80);
    out.push(...chunk);
  }
  return tlv(0x06, new Uint8Array(out));
}

function derInt(bytes: Uint8Array): Uint8Array {
  let v = bytes;
  while (v.length > 1 && v[0] === 0 && !(v[1] & 0x80)) v = v.subarray(1);
  return tlv(0x02, v[0] & 0x80 ? concat(new Uint8Array([0]), v) : v);
}

const name = (cn: string) => seq(tlv(0x31, seq(oid("2.5.4.3"), tlv(0x0c, new TextEncoder().encode(cn)))));

function utcTime(d: Date): Uint8Array {
  const p = (n: number) => String(n).padStart(2, "0");
  const s = `${p(d.getUTCFullYear() % 100)}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}` +
    `${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`;
  return tlv(0x17, new TextEncoder().encode(s));
}

export function rawToDer(raw: Uint8Array): Uint8Array {
  const half = raw.length / 2;
  return seq(derInt(raw.subarray(0, half)), derInt(raw.subarray(half)));
}

interface Ca {
  keys: CryptoKeyPair;
  der: Uint8Array;
  curve: "P-256" | "P-384";
  cn: string;
}

const ALG = { "SHA-256": "1.2.840.10045.4.3.2", "SHA-384": "1.2.840.10045.4.3.3" };

async function certificate(opts: {
  subject: string;
  issuer: { cn: string; key: CryptoKey };
  publicKey: CryptoKey;
  hash: "SHA-256" | "SHA-384";
  nonce?: Uint8Array;
  notAfter?: Date;
}): Promise<Uint8Array> {
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", opts.publicKey));
  const ext = opts.nonce
    ? [tlv(0xa3, seq(seq(oid("1.2.840.113635.100.8.2"), tlv(0x04, seq(tlv(0xa1, tlv(0x04, opts.nonce)))))))]
    : [];
  const tbs = seq(
    tlv(0xa0, derInt(new Uint8Array([2]))),
    derInt(crypto.getRandomValues(new Uint8Array(8))),
    seq(oid(ALG[opts.hash])),
    name(opts.issuer.cn),
    seq(utcTime(new Date(Date.now() - 86_400_000)), utcTime(opts.notAfter ?? new Date(Date.now() + 86_400_000))),
    name(opts.subject),
    spki,
    ...ext,
  );
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: opts.hash }, opts.issuer.key, tbs));
  return seq(tbs, seq(oid(ALG[opts.hash])), tlv(0x03, new Uint8Array([0]), rawToDer(sig)));
}

async function ca(cn: string, parent?: Ca): Promise<Ca> {
  const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-384" }, true, ["sign", "verify"]);
  const der = await certificate({
    subject: cn,
    issuer: parent ? { cn: parent.cn, key: parent.keys.privateKey } : { cn, key: keys.privateKey },
    publicKey: keys.publicKey,
    hash: "SHA-384",
  });
  return { keys, der, curve: "P-384", cn };
}

/** Stands in for Apple's root; install it with _useRootForTests. */
export const fakeRoot = await ca("Fake App Attestation Root CA");
const fakeIntermediate = await ca("Fake App Attestation CA 1", fakeRoot);

/** A second, untrusted "Apple" (what an attacker can make). */
export async function rogueChain(): Promise<{ root: Ca; intermediate: Ca }> {
  const root = await ca("Apple App Attestation Root CA");
  return { root, intermediate: await ca("Apple App Attestation CA 1", root) };
}

// ── CBOR ──────────────────────────────────────────────────────────────

type CborIn = number | string | Uint8Array | CborIn[] | { [k: string]: CborIn };

function cborHead(major: number, n: number): Uint8Array {
  if (n < 24) return new Uint8Array([(major << 5) | n]);
  if (n < 0x100) return new Uint8Array([(major << 5) | 24, n]);
  if (n < 0x10000) return new Uint8Array([(major << 5) | 25, n >> 8, n & 0xff]);
  return new Uint8Array([(major << 5) | 26, n >>> 24, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]);
}

export function cbor(v: CborIn): Uint8Array {
  if (typeof v === "number") return cborHead(0, v);
  if (typeof v === "string") {
    const b = new TextEncoder().encode(v);
    return concat(cborHead(3, b.length), b);
  }
  if (v instanceof Uint8Array) return concat(cborHead(2, v.length), v);
  if (Array.isArray(v)) return concat(cborHead(4, v.length), ...v.map(cbor));
  const entries = Object.entries(v);
  return concat(cborHead(5, entries.length), ...entries.flatMap(([k, x]) => [cbor(k), cbor(x)]));
}

// ── Attestations and assertions ───────────────────────────────────────

export const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
const u32 = (n: number) => new Uint8Array([n >>> 24, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]);
const AAGUID = {
  production: concat(new TextEncoder().encode("appattest"), new Uint8Array(7)),
  development: new TextEncoder().encode("appattestdevelop"),
};

export interface FakeKey {
  keyId: string; // base64, as Apple's API returns it
  keyIdUrl: string; // base64url, as the app sends it
  point: Uint8Array;
  privateKey: CryptoKey;
}

export const clientData = async (userId: string, fn: string, ts: number) =>
  await sha256(new TextEncoder().encode(`${userId}|${fn}|${ts}`));

/** What the iPhone produces for DCAppAttestService.attestKey. */
export async function attest(opts: {
  hash: Uint8Array;
  appId?: string;
  environment?: "production" | "development";
  counter?: number;
  chain?: { intermediate: Ca };
  /** Certify a different key than the one the attestation names. */
  swapKey?: boolean;
}): Promise<{ key: FakeKey; attestation: string }> {
  const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const point = new Uint8Array(await crypto.subtle.exportKey("raw", keys.publicKey));
  const keyId = await sha256(point);
  const authData = concat(
    await sha256(new TextEncoder().encode(opts.appId ?? APP_ID)),
    new Uint8Array([0x41]),
    u32(opts.counter ?? 0),
    AAGUID[opts.environment ?? "production"],
    new Uint8Array([0, 32]),
    keyId,
    cbor({ "1": 2 }),
  );
  const intermediate = opts.chain?.intermediate ?? fakeIntermediate;
  const certified = opts.swapKey
    ? (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])).publicKey
    : keys.publicKey;
  const leaf = await certificate({
    subject: "leaf",
    issuer: { cn: intermediate.cn, key: intermediate.keys.privateKey },
    publicKey: certified,
    hash: "SHA-256",
    nonce: await sha256(authData, opts.hash),
  });
  const attestation = cbor({
    fmt: "apple-appattest",
    attStmt: { x5c: [leaf, intermediate.der], receipt: new Uint8Array([1, 2, 3]) },
    authData,
  });
  const keyIdB64 = b64(keyId);
  return {
    key: {
      keyId: keyIdB64,
      keyIdUrl: keyIdB64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""),
      point,
      privateKey: keys.privateKey,
    },
    attestation: b64(attestation),
  };
}

/** What the iPhone produces for DCAppAttestService.generateAssertion. */
export async function assertion(
  key: FakeKey,
  hash: Uint8Array,
  counter: number,
  appId = APP_ID,
): Promise<string> {
  const authData = concat(await sha256(new TextEncoder().encode(appId)), new Uint8Array([0x40]), u32(counter));
  const nonce = await sha256(authData, hash);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key.privateKey, nonce));
  return b64(cbor({ signature: rawToDer(sig), authenticatorData: authData }));
}
