// Early spend warnings before the daily hard stop.
//
//   cd supabase/functions && deno test --allow-env --allow-read=. --allow-net=127.0.0.1 _tests/

import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("spend alerts fire once per level as the day's spend climbs", async () => {
  const { spendWarning } = await import("../_shared/common.ts");
  assertEquals(spendWarning(5, 25), undefined);
  assertEquals(spendWarning(13, 25), 0.5);
  assertEquals(spendWarning(14, 25), undefined); // already warned at 50%
  assertEquals(spendWarning(21, 25), 0.8);
  assertEquals(spendWarning(24, 25), undefined);
});
