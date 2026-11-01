// The grounded (Google Search) helper and skin-insight's contract.
//
//   cd supabase/functions && deno test --allow-env --allow-read=. --allow-net=127.0.0.1 _tests/

import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { costUsd } from "../_shared/common.ts";
import { extractJson, grounded } from "../_shared/grounded.ts";
import { InsightSchema, RequestSchema } from "../skin-insight/insight.ts";

Deno.env.set("GEMINI_API_KEY", "gemini-for-tests");

const answer = (text: string, searched = true) =>
  new Response(
    JSON.stringify({
      candidates: [{
        content: { parts: [{ text }] },
        groundingMetadata: { webSearchQueries: searched ? ["azelaic acid redness"] : [] },
      }],
      usageMetadata: { promptTokenCount: 1000, candidatesTokenCount: 200 },
    }),
    { status: 200 },
  );

Deno.test("grounded asks Gemini with the Google Search tool and never sends images", async () => {
  let sent: Record<string, unknown> = {};
  const res = await grounded(
    { system: "sys", turns: [{ role: "user", text: "hi" }], maxTokens: 100 },
    (async (_url: string | URL | Request, init?: RequestInit) => {
      sent = JSON.parse(String(init?.body));
      return answer("ok");
    }) as typeof fetch,
  );
  assertEquals(res.text, "ok");
  assertEquals(sent.tools, [{ google_search: {} }]);
  assert(!JSON.stringify(sent).includes("inlineData"));
  // A searched answer books the grounding charge on top of tokens.
  assert(costUsd(res.usage) > 0.035);
});

Deno.test("an answer that didn't search costs only its tokens", async () => {
  const res = await grounded(
    { system: "s", turns: [{ role: "user", text: "q" }], maxTokens: 50 },
    (async () => answer("ok", false)) as typeof fetch,
  );
  assert(costUsd(res.usage) < 0.01);
});

Deno.test("a Gemini error becomes a retryable server error", async () => {
  await assertRejects(() =>
    grounded(
      { system: "s", turns: [{ role: "user", text: "q" }], maxTokens: 50 },
      (async () => new Response("no", { status: 500 })) as typeof fetch,
    )
  );
});

Deno.test("extractJson finds the object inside prose or a code fence", () => {
  assertEquals(extractJson('Here you go:\n```json\n{"a": 1}\n```'), { a: 1 });
  assertEquals(extractJson("no json here"), null);
  assertEquals(extractJson("{broken"), null);
});

Deno.test("skin-insight accepts numbers only and rejects out-of-range values", () => {
  const ok = {
    profile: { selfReportedSkinType: "oily" },
    radiance: { score: 60, evenness: 60, clarity: 70, sheen: 50 },
    metrics: [{ metric: "redness", score: 55, note: "About 5% of your skin reads red." }],
    measure: { l: 62, c: { redness: 0.05 }, z: { redness: { cheeks: 0.09 } } },
  };
  assert(RequestSchema.safeParse(ok).success);
  assert(!RequestSchema.safeParse({ ...ok, radiance: { ...ok.radiance, score: 140 } }).success);
  assert(!RequestSchema.safeParse({ ...ok, measure: { c: { redness: 3 } } }).success);
});

Deno.test("skin-insight answers are trimmed to the shape the app shows", () => {
  const parsed = InsightSchema.safeParse({
    summary: "Mild redness on the cheeks.",
    priorities: ["Calm redness"],
    recommended_ingredients: [{ name: "Azelaic acid", why: "Calms redness gently." }],
  });
  assert(parsed.success);
  assertEquals(parsed.data.strengths, []);
  assert(!InsightSchema.safeParse({ summary: "" }).success);
  assert(!InsightSchema.safeParse({ summary: "x", priorities: ["a", "b", "c", "d"] }).success);
});
