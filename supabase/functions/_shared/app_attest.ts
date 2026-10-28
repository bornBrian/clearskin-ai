// Apple App Attest: the iPhone counterpart of Play Integrity. It proves a
// call comes from the genuine ClearSkin app (our team ID and bundle ID,
// signed by Apple) on a real iPhone, using a key that lives in the phone's
// Secure Enclave.
//
// Once per install the app registers a key: Apple certifies it in an
// attestation, which app-attest checks here and stores. Every call after
// that carries an assertion: the key's signature over the call's
// "<user id>|<function>|<x-cs-ts>" hash plus a counter that must go up, so
// assertions can't be forged, moved to another user or call, or replayed.
//
// Follows Apple's "Validating apps that connect to your server".
//
// APPLE_APP_ID                  "<team id>.com.clearskinai.app"; unset = off
// APP_ATTEST_ALLOW_DEVELOPMENT  "true" to accept development keys (builds
//                               run from Xcode); never in production

import {
  base64Decode,
  base64UrlEncode,
  cborBytes,
  cborMap,
  children,
  concat,
  DecodeError,
  decodeCbor,
  ecdsaDerToRaw,
  equalBytes,
  expectTag,
  oid,
  readTlv,
  sha256,
  type Tlv,
} from "./encoding.ts";

/** Apple App Attestation Root CA (valid to 2045), from
 * https://www.apple.com/certificateauthority/private/. SHA-256 fingerprint
 * 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32 */
const APPLE_ROOT_PEM = `
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD`;

let rootDer: Uint8Array = base64Decode(APPLE_ROOT_PEM.replace(/\s+/g, ""));

/** Tests sign with their own root; nothing else may call this. Returns
 * the root it replaced. */
export function _useRootForTests(der: Uint8Array): Uint8Array {
  const previous = rootDer;
  rootDer = der;
  return previous;
}

const NONCE_OID = "1.2.840.113635.100.8.2";
const AAGUID_PRODUCTION = concat(new TextEncoder().encode("appattest"), new Uint8Array(7));
const AAGUID_DEVELOPMENT = new TextEncoder().encode("appattestdevelop");

export type AttestEnvironment = "production" | "development";

export class AttestError extends Error {}

export function appAttestConfigured(): boolean {
  return !!Deno.env.get("APPLE_APP_ID");
}

function appId(): string {
  const id = Deno.env.get("APPLE_APP_ID");
  if (!id) throw new AttestError("APPLE_APP_ID not set");
  return id;
}

/** sha256 of the string the app hashed for this call. */
export async function clientDataHash(userId: string, fn: string, ts: number): Promise<Uint8Array<ArrayBuffer>> {
  return await sha256(new TextEncoder().encode(`${userId}|${fn}|${ts}`));
}

// ── Registration ───────────────────────────────────────────────────────

export interface AttestedKey {
  /** base64url of the 32-byte key id. */
  keyId: string;
  /** Uncompressed P-256 point (65 bytes). */
  publicKey: Uint8Array;
  environment: AttestEnvironment;
}

export async function verifyAttestation(
  keyIdBase64: string,
  attestationBase64: string,
  hash: Uint8Array,
): Promise<AttestedKey> {
  try {
    const keyId = base64Decode(keyIdBase64);
    if (keyId.length !== 32) throw new AttestError("bad key id");

    const att = cborMap(decodeCbor(base64Decode(attestationBase64)));
    if (att.get("fmt") !== "apple-appattest") throw new AttestError("wrong format");
    const stmt = cborMap(att.get("attStmt") ?? null);
    const x5c = stmt.get("x5c");
    if (!Array.isArray(x5c) || x5c.length !== 2) throw new AttestError("bad certificate chain");
    const authData = cborBytes(att.get("authData"));

    // 1. The chain ends at Apple's root.
    const leaf = parseCert(cborBytes(x5c[0]));
    const intermediate = parseCert(cborBytes(x5c[1]));
    const root = parseCert(rootDer);
    const now = Date.now();
    for (const c of [leaf, intermediate, root]) {
      if (now < c.notBefore || now > c.notAfter) throw new AttestError("certificate expired");
    }
    if (!await signedBy(leaf, intermediate) || !await signedBy(intermediate, root)) {
      throw new AttestError("certificate chain not signed by Apple");
    }

    // 2–4. Apple certified this exact key for this exact request.
    const nonce = await sha256(authData, hash);
    if (!equalBytes(certNonce(leaf), nonce)) throw new AttestError("nonce mismatch");
    if (leaf.curve !== "P-256" || leaf.point.length !== 65) throw new AttestError("unexpected key type");
    if (!equalBytes(await sha256(leaf.point), keyId)) throw new AttestError("key id mismatch");

    // 5–9. For our app, a fresh key, from the environment we expect.
    const data = parseAuthData(authData);
    if (!equalBytes(data.rpIdHash, await sha256(new TextEncoder().encode(appId())))) {
      throw new AttestError("different app");
    }
    if (data.counter !== 0) throw new AttestError("counter not zero");
    let environment: AttestEnvironment;
    if (equalBytes(data.aaguid, AAGUID_PRODUCTION)) environment = "production";
    else if (equalBytes(data.aaguid, AAGUID_DEVELOPMENT)) environment = "development";
    else throw new AttestError("unknown environment");
    if (environment === "development" && Deno.env.get("APP_ATTEST_ALLOW_DEVELOPMENT") !== "true") {
      throw new AttestError("development key");
    }
    if (!data.credentialId || !equalBytes(data.credentialId, keyId)) {
      throw new AttestError("credential id mismatch");
    }
    return { keyId: base64UrlEncode(keyId), publicKey: leaf.point, environment };
  } catch (err) {
    if (err instanceof DecodeError) throw new AttestError(`malformed: ${err.message}`);
    throw err;
  }
}

// ── Per-call assertions ───────────────────────────────────────────────

/** Checks [assertionBase64] against a registered key and returns the new
 * counter, which must be stored (and must exceed [storedCount]). */
export async function verifyAssertion(
  assertionBase64: string,
  publicKey: Uint8Array<ArrayBuffer>,
  storedCount: number,
  hash: Uint8Array,
): Promise<number> {
  try {
    const a = cborMap(decodeCbor(base64Decode(assertionBase64)));
    const signature = cborBytes(a.get("signature"));
    const authData = cborBytes(a.get("authenticatorData"));
    const key = await crypto.subtle.importKey("raw", publicKey, { name: "ECDSA", namedCurve: "P-256" }, false, [
      "verify",
    ]);
    const nonce = await sha256(authData, hash);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      ecdsaDerToRaw(signature, 32),
      nonce,
    );
    if (!valid) throw new AttestError("bad signature");
    const data = parseAuthData(authData);
    if (!equalBytes(data.rpIdHash, await sha256(new TextEncoder().encode(appId())))) {
      throw new AttestError("different app");
    }
    if (data.counter <= storedCount) throw new AttestError("replayed assertion");
    return data.counter;
  } catch (err) {
    if (err instanceof DecodeError) throw new AttestError(`malformed: ${err.message}`);
    throw err;
  }
}

// ── Parsing ───────────────────────────────────────────────────────────

interface AuthData {
  rpIdHash: Uint8Array;
  counter: number;
  aaguid: Uint8Array;
  credentialId?: Uint8Array;
}

function parseAuthData(d: Uint8Array): AuthData {
  if (d.length < 37) throw new AttestError("authenticator data too short");
  const view = new DataView(d.buffer, d.byteOffset, d.byteLength);
  const out: AuthData = { rpIdHash: d.subarray(0, 32), counter: view.getUint32(33), aaguid: new Uint8Array() };
  if (d.length >= 55) {
    out.aaguid = d.subarray(37, 53);
    const len = view.getUint16(53);
    if (55 + len > d.length) throw new AttestError("credential id truncated");
    out.credentialId = d.subarray(55, 55 + len);
  }
  return out;
}

interface Cert {
  tbs: Uint8Array<ArrayBuffer>;
  signatureAlg: string;
  signature: Uint8Array;
  spki: Uint8Array<ArrayBuffer>;
  curve: "P-256" | "P-384";
  point: Uint8Array<ArrayBuffer>;
  notBefore: number;
  notAfter: number;
  extensions: Map<string, Uint8Array>;
}

const CURVES: Record<string, "P-256" | "P-384"> = {
  "1.2.840.10045.3.1.7": "P-256",
  "1.3.132.0.34": "P-384",
};
const SIGNATURE_HASHES: Record<string, string> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};

function parseCert(der: Uint8Array): Cert {
  const cert = expectTag(readTlv(der), 0x30);
  if (cert.raw.length !== der.length) throw new DecodeError("certificate trailing bytes");
  const [tbs, alg, sig] = children(cert);
  const fields = children(expectTag(tbs, 0x30));
  let i = fields[0]?.tag === 0xa0 ? 1 : 0; // version
  i++; // serial
  i++; // signature algorithm (repeated outside the TBS)
  i++; // issuer
  const validity = children(expectTag(fields[i++], 0x30));
  i++; // subject
  const spki = expectTag(fields[i++], 0x30);
  const extensions = new Map<string, Uint8Array>();
  for (; i < fields.length; i++) {
    if (fields[i].tag !== 0xa3) continue;
    for (const ext of children(expectTag(children(fields[i])[0], 0x30))) {
      const parts = children(expectTag(ext, 0x30));
      extensions.set(oid(parts[0]), expectTag(parts[parts.length - 1], 0x04).value);
    }
  }
  const [keyAlg, keyBits] = children(spki);
  const keyAlgParts = children(expectTag(keyAlg, 0x30));
  if (oid(keyAlgParts[0]) !== "1.2.840.10045.2.1") throw new DecodeError("not an EC key");
  const curve = CURVES[oid(keyAlgParts[1])];
  if (!curve) throw new DecodeError("unsupported curve");
  const bits = expectTag(keyBits, 0x03).value;
  const sigBits = expectTag(sig, 0x03).value;
  if (bits[0] !== 0 || sigBits[0] !== 0) throw new DecodeError("unused bits");
  return {
    tbs: tbs.raw.slice(),
    signatureAlg: oid(children(expectTag(alg, 0x30))[0]),
    signature: sigBits.subarray(1),
    spki: spki.raw.slice(),
    curve,
    point: bits.slice(1),
    notBefore: derTime(validity[0]),
    notAfter: derTime(validity[1]),
    extensions,
  };
}

function derTime(t: Tlv | undefined): number {
  const s = new TextDecoder().decode(t?.value ?? new Uint8Array());
  const m = t?.tag === 0x17
    ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s)
    : t?.tag === 0x18
    ? /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s)
    : null;
  if (!m) throw new DecodeError("bad certificate time");
  let year = Number(m[1]);
  if (t?.tag === 0x17) year += year < 50 ? 2000 : 1900;
  return Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
}

async function signedBy(cert: Cert, issuer: Cert): Promise<boolean> {
  const hash = SIGNATURE_HASHES[cert.signatureAlg];
  if (!hash) return false;
  const key = await crypto.subtle.importKey("spki", issuer.spki, { name: "ECDSA", namedCurve: issuer.curve }, false, [
    "verify",
  ]);
  const size = issuer.curve === "P-256" ? 32 : 48;
  return await crypto.subtle.verify({ name: "ECDSA", hash }, key, ecdsaDerToRaw(cert.signature, size), cert.tbs);
}

/** The nonce Apple put in the leaf certificate:
 * SEQUENCE { [1] { OCTET STRING nonce } }. */
function certNonce(leaf: Cert): Uint8Array {
  const ext = leaf.extensions.get(NONCE_OID);
  if (!ext) throw new AttestError("no nonce extension");
  const tagged = children(expectTag(readTlv(ext), 0x30)).find((t) => t.tag === 0xa1);
  return expectTag(children(expectTag(tagged, 0xa1))[0], 0x04).value;
}
