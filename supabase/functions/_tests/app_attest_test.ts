// App Attest verification against a fake Apple (see fake_apple.ts): the
// genuine flow passes, and every forgery we could think of fails.

import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  _useRootForTests,
  AttestError,
  clientDataHash,
  verifyAssertion,
  verifyAttestation,
} from "../_shared/app_attest.ts";
import { APP_ID, assertion, attest, b64, cbor, clientData, fakeRoot, rogueChain } from "./fake_apple.ts";

Deno.env.set("APPLE_APP_ID", APP_ID);
const appleRoot = _useRootForTests(fakeRoot.der);

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";
const TS = 1_800_000_000_000;

const refused = (p: Promise<unknown>, why?: string) => assertRejects(() => p, AttestError, why);

Deno.test("Apple's real root parses and is trusted (fakes are not)", async () => {
  _useRootForTests(appleRoot);
  try {
    const hash = await clientData(U1, "app-attest", TS);
    const { key, attestation } = await attest({ hash });
    await refused(verifyAttestation(key.keyId, attestation, hash), "not signed by Apple");
  } finally {
    _useRootForTests(fakeRoot.der);
  }
});

Deno.test("genuine attestation registers the key", async () => {
  const hash = await clientData(U1, "app-attest", TS);
  const { key, attestation } = await attest({ hash });
  const out = await verifyAttestation(key.keyId, attestation, hash);
  assertEquals(out.keyId, key.keyIdUrl);
  assertEquals(out.environment, "production");
  assertEquals([...out.publicKey], [...key.point]);
});

Deno.test("attestation made for another user is refused", async () => {
  const { key, attestation } = await attest({ hash: await clientData(U2, "app-attest", TS) });
  await refused(verifyAttestation(key.keyId, attestation, await clientData(U1, "app-attest", TS)), "nonce");
});

Deno.test("attestation from an old timestamp is refused", async () => {
  const { key, attestation } = await attest({ hash: await clientData(U1, "app-attest", TS - 1) });
  await refused(verifyAttestation(key.keyId, attestation, await clientData(U1, "app-attest", TS)), "nonce");
});

Deno.test("certificates from a look-alike 'Apple' root are refused", async () => {
  const hash = await clientData(U1, "app-attest", TS);
  const { key, attestation } = await attest({ hash, chain: await rogueChain() });
  await refused(verifyAttestation(key.keyId, attestation, hash), "not signed by Apple");
});

Deno.test("another developer's app is refused", async () => {
  const hash = await clientData(U1, "app-attest", TS);
  const { key, attestation } = await attest({ hash, appId: "EVILTEAM00.com.clearskinai.app" });
  await refused(verifyAttestation(key.keyId, attestation, hash), "different app");
});

Deno.test("development keys are refused unless allowed", async () => {
  const hash = await clientData(U1, "app-attest", TS);
  const { key, attestation } = await attest({ hash, environment: "development" });
  await refused(verifyAttestation(key.keyId, attestation, hash), "development");
  Deno.env.set("APP_ATTEST_ALLOW_DEVELOPMENT", "true");
  try {
    assertEquals((await verifyAttestation(key.keyId, attestation, hash)).environment, "development");
  } finally {
    Deno.env.delete("APP_ATTEST_ALLOW_DEVELOPMENT");
  }
});

Deno.test("a used key (counter above zero) is refused", async () => {
  const hash = await clientData(U1, "app-attest", TS);
  const { key, attestation } = await attest({ hash, counter: 3 });
  await refused(verifyAttestation(key.keyId, attestation, hash), "counter");
});

Deno.test("claiming someone else's key id is refused", async () => {
  const hash = await clientData(U1, "app-attest", TS);
  const mine = await attest({ hash });
  const theirs = await attest({ hash });
  await refused(verifyAttestation(theirs.key.keyId, mine.attestation, hash), "key id");
});

Deno.test("a certificate for a different key is refused", async () => {
  const hash = await clientData(U1, "app-attest", TS);
  const { key, attestation } = await attest({ hash, swapKey: true });
  await refused(verifyAttestation(key.keyId, attestation, hash), "key id");
});

Deno.test("junk attestations fail cleanly", async () => {
  const hash = await clientData(U1, "app-attest", TS);
  const keyId = b64(new Uint8Array(32));
  const junk = [
    "",
    "not base64!",
    b64(new Uint8Array(200)),
    b64(cbor({ fmt: "packed" })),
    b64(cbor({ fmt: "apple-appattest", attStmt: { x5c: [] }, authData: new Uint8Array(10) })),
    b64(
      cbor({
        fmt: "apple-appattest",
        attStmt: { x5c: [new Uint8Array(5), new Uint8Array(5)] },
        authData: new Uint8Array(60),
      }),
    ),
    b64(new Uint8Array([0x9f, 0x01, 0xff])), // indefinite-length array
    b64(new Uint8Array(Array(40).fill(0x81))), // nested 40 deep
    b64(new Uint8Array([0x5a, 0xff, 0xff, 0xff, 0xff])), // 4 GB byte string
  ];
  for (const a of junk) await refused(verifyAttestation(keyId, a, hash));
  await refused(verifyAttestation("short", junk[2], hash));
});

Deno.test("assertions: genuine passes, replay and forgeries fail", async () => {
  const reg = await attest({ hash: await clientData(U1, "app-attest", TS) });
  const key = await verifyAttestation(reg.key.keyId, reg.attestation, await clientData(U1, "app-attest", TS));
  const pub = new Uint8Array(key.publicKey);
  const call = await clientDataHash(U1, "analyze-skin", TS);

  const a1 = await assertion(reg.key, call, 1);
  assertEquals(await verifyAssertion(a1, pub, 0, call), 1);
  // Same assertion again: counter didn't go up.
  await refused(verifyAssertion(a1, pub, 1, call), "replayed");
  // Moved to another user, function or time.
  await refused(verifyAssertion(a1, pub, 0, await clientDataHash(U2, "analyze-skin", TS)), "bad signature");
  await refused(verifyAssertion(a1, pub, 0, await clientDataHash(U1, "coach", TS)), "bad signature");
  await refused(verifyAssertion(a1, pub, 0, await clientDataHash(U1, "analyze-skin", TS + 1)), "bad signature");
  // Signed by a different key.
  const other = await attest({ hash: call });
  await refused(verifyAssertion(await assertion(other.key, call, 5), pub, 0, call), "bad signature");
  // Another app's assertion.
  await refused(verifyAssertion(await assertion(reg.key, call, 2, "EVILTEAM00.x"), pub, 0, call), "different app");
  // Junk.
  for (const j of ["", "AAAA", b64(cbor({ signature: new Uint8Array(3), authenticatorData: new Uint8Array(37) }))]) {
    await refused(verifyAssertion(j, pub, 0, call));
  }
});
