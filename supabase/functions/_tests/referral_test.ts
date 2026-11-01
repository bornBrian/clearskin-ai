// Invite codes: readable, unambiguous, and the right shape for the database.
//
//   cd supabase/functions && deno test --allow-env --allow-read=. --allow-net=127.0.0.1 _tests/

import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1.0.14";
import { CODE, newCode } from "../_shared/referral.ts";

Deno.test("invite codes are 6 characters with no 0/O or 1/I/L", () => {
  for (let i = 0; i < 500; i++) {
    const c = newCode();
    assertMatch(c, CODE);
    assert(!/[01OIL]/.test(c), c);
  }
});

Deno.test("invite codes use the whole alphabet evenly enough", () => {
  assertEquals(newCode(() => new Uint8Array([0, 1, 2, 3, 4, 5])), "ABCDEF");
  const seen = new Set<string>();
  for (let i = 0; i < 2000; i++) seen.add(newCode());
  assert(seen.size > 1990, "codes repeat too often");
});
