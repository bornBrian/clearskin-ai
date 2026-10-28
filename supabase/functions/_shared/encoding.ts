// Small, strict decoders for the binary formats Apple and Google sign
// things with: base64url, CBOR (App Attest objects) and DER (X.509
// certificates, ECDSA signatures). Each covers only what those formats use
// and throws on anything else, so hostile input fails closed.

export class DecodeError extends Error {}

export function base64Decode(text: string): Uint8Array<ArrayBuffer> {
  const std = text.replace(/-/g, "+").replace(/_/g, "/");
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(std)) throw new DecodeError("not base64");
  try {
    return Uint8Array.from(atob(std.padEnd(Math.ceil(std.length / 4) * 4, "=")), (c) => c.charCodeAt(0));
  } catch {
    throw new DecodeError("not base64");
  }
}

export function base64UrlEncode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function concat(...parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

export function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function sha256(...parts: Uint8Array[]): Promise<Uint8Array<ArrayBuffer>> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", concat(...parts)));
}

// ── CBOR (RFC 8949): definite-length items only ───────────────────────

export type Cbor = number | Uint8Array | string | boolean | null | Cbor[] | Map<string | number, Cbor>;

const MAX_DEPTH = 8;
const MAX_ITEMS = 64;

export function decodeCbor(bytes: Uint8Array): Cbor {
  let pos = 0;
  const take = (n: number) => {
    if (n < 0 || pos + n > bytes.length) throw new DecodeError("CBOR truncated");
    const out = bytes.subarray(pos, pos + n);
    pos += n;
    return out;
  };
  const length = (info: number): number => {
    if (info < 24) return info;
    const size = { 24: 1, 25: 2, 26: 4 }[info];
    if (!size) throw new DecodeError("CBOR length unsupported");
    return take(size).reduce((n, b) => n * 256 + b, 0);
  };
  const item = (depth: number): Cbor => {
    if (depth > MAX_DEPTH) throw new DecodeError("CBOR too deep");
    const head = take(1)[0];
    const major = head >> 5;
    const info = head & 31;
    if (major === 7) {
      if (info === 20) return false;
      if (info === 21) return true;
      if (info === 22) return null;
      throw new DecodeError("CBOR simple value unsupported");
    }
    const n = length(info);
    switch (major) {
      case 0:
        return n;
      case 1:
        return -1 - n;
      case 2:
        return take(n);
      case 3:
        try {
          return new TextDecoder("utf-8", { fatal: true }).decode(take(n));
        } catch {
          throw new DecodeError("CBOR text not UTF-8");
        }
      case 4: {
        if (n > MAX_ITEMS) throw new DecodeError("CBOR array too long");
        return Array.from({ length: n }, () => item(depth + 1));
      }
      case 5: {
        if (n > MAX_ITEMS) throw new DecodeError("CBOR map too long");
        const map = new Map<string | number, Cbor>();
        for (let i = 0; i < n; i++) {
          const key = item(depth + 1);
          if (typeof key !== "string" && typeof key !== "number") throw new DecodeError("CBOR key type");
          if (map.has(key)) throw new DecodeError("CBOR duplicate key");
          map.set(key, item(depth + 1));
        }
        return map;
      }
      default:
        throw new DecodeError("CBOR type unsupported");
    }
  };
  const value = item(0);
  if (pos !== bytes.length) throw new DecodeError("CBOR trailing bytes");
  return value;
}

export function cborMap(v: Cbor): Map<string | number, Cbor> {
  if (!(v instanceof Map)) throw new DecodeError("expected CBOR map");
  return v;
}

export function cborBytes(v: Cbor | undefined): Uint8Array {
  if (!(v instanceof Uint8Array)) throw new DecodeError("expected CBOR bytes");
  return v;
}

// ── DER (X.690) ───────────────────────────────────────────────────────

export interface Tlv {
  tag: number;
  /** The whole element, header included (what gets signed for a TBS). */
  raw: Uint8Array;
  value: Uint8Array;
}

export function readTlv(bytes: Uint8Array, at = 0): Tlv {
  if (at + 2 > bytes.length) throw new DecodeError("DER truncated");
  const tag = bytes[at];
  if ((tag & 0x1f) === 0x1f) throw new DecodeError("DER high tag");
  let len = bytes[at + 1];
  let head = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 3 || at + 2 + n > bytes.length) throw new DecodeError("DER length");
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + bytes[at + 2 + i];
    head += n;
  }
  const end = at + head + len;
  if (end > bytes.length) throw new DecodeError("DER truncated");
  return { tag, raw: bytes.subarray(at, end), value: bytes.subarray(at + head, end) };
}

/** The elements inside a constructed element. */
export function children(tlv: Tlv): Tlv[] {
  const out: Tlv[] = [];
  for (let at = 0; at < tlv.value.length;) {
    const child = readTlv(tlv.value, at);
    out.push(child);
    at += child.raw.length;
    if (out.length > 64) throw new DecodeError("DER too many elements");
  }
  return out;
}

export function expectTag(tlv: Tlv | undefined, tag: number): Tlv {
  if (!tlv || tlv.tag !== tag) throw new DecodeError(`DER expected tag ${tag}`);
  return tlv;
}

export function oid(tlv: Tlv): string {
  const v = expectTag(tlv, 0x06).value;
  if (v.length === 0) throw new DecodeError("DER empty OID");
  const parts = [Math.floor(v[0] / 40), v[0] % 40];
  let n = 0;
  for (let i = 1; i < v.length; i++) {
    n = n * 128 + (v[i] & 0x7f);
    if (!(v[i] & 0x80)) {
      parts.push(n);
      n = 0;
    }
  }
  return parts.join(".");
}

/** ECDSA signature: DER SEQUENCE { r, s } → the raw r‖s WebCrypto wants. */
export function ecdsaDerToRaw(der: Uint8Array, size: number): Uint8Array<ArrayBuffer> {
  const seq = readTlv(der);
  if (seq.tag !== 0x30 || seq.raw.length !== der.length) throw new DecodeError("bad ECDSA signature");
  const ints = children(seq);
  if (ints.length !== 2) throw new DecodeError("bad ECDSA signature");
  const raw = new Uint8Array(size * 2);
  ints.forEach((t, i) => {
    let v = expectTag(t, 0x02).value;
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    if (v.length > size) throw new DecodeError("bad ECDSA signature");
    raw.set(v, i * size + size - v.length);
  });
  return raw;
}
