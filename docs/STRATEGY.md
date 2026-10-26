# ClearSkin AI — strategy, honest rating & path to revenue

_Figures about other companies are approximate public reports as of 2025–2026, not audited numbers. Treat them as order-of-magnitude._

## Honest rating

| Dimension | Score | Why |
|---|---|---|
| Market demand | 9/10 | Skincare is a ~$150B+ global category with daily, lifelong need; men's and Gen-Z skincare are the fastest-growing segments. |
| Willingness to pay | 8/10 | AI "scan yourself" subscription apps have proven people pay $30–70/year (e.g. calorie, looksmaxxing and skin apps). |
| Originality of a basic "AI skin scan" | 3/10 | Crowded: dozens of skin-scan apps, YouCam/Perfect Corp, Haut.AI-powered brand tools, SkinVision (moles), TroveSkin, ingredient scanners (Yuka, INCI Beauty, Think Dirty). |
| Differentiation as built here | 7/10 | Closed loop (scan → routine → shelf → tracking → triggers), skin-tone fairness, men/shaving, conflict checker, privacy-first, honest science instead of fear-marketing. |
| Defensibility | 5/10 → 7/10 over time | Weak on day 1; grows with each user's history (photos, check-ins, shelf) — a real switching cost — and with brand trust. |
| **Overall idea** | **7.5/10** | Strong market, crowded entry. Winners in this category win on **distribution and retention**, not on the scan itself. |

## Will it make $2M/month?

Possible, but it's a top-1% outcome. The math:

- Blended revenue per paying user ≈ $5–7/month (mix of annual $39.99, monthly $9.99, weekly $3.99, with lower regional prices).
- $2M/month ÷ ~$6 ≈ **330,000 active subscribers**.
- At ~4% install→paid and typical churn, that needs **~400k–800k installs every month**, sustained.
- The comparable success story, Cal AI (calorie scanning), reportedly passed ~$30M ARR within about 18 months — mostly on iOS, driven by heavy creator marketing.

**Realistic ladder with strong execution:**
| Stage | MRR | What gets you there |
|---|---|---|
| Month 1–3 | $0–5k | Launch, fix funnel, first 1–5k installs, organic TikTok/Reels |
| Month 6 | $10–50k | One repeatable content format that converts; ASO; regional pricing |
| Month 12 | $100k+ | **iOS launch** (iOS users typically spend 2–3× Android users), paid UGC creators, localisation |
| Year 2–3 | $500k–2M | Reinvesting ~30–50% of revenue into creators/ads at a proven CAC < 1/3 of LTV |

**Most important business advice:** Android-first is fine for learning cheaply, but most subscription revenue in this category is on iOS. Treat the $99/year Apple fee as the highest-ROI expense once Play revenue covers it. The code is already iOS-ready.

## Market gaps this app targets

1. **Meaningless scores.** Most scan apps score whatever photo they get, so lighting changes look like "progress". → Guided capture + on-device quality checks + consistent rubric.
2. **Skin-tone bias.** Dermatology datasets underrepresent deeper skin; apps misread natural pigmentation and recommend white-cast sunscreens. → Explicit fairness rules, PIH-aware routines, no-white-cast SPF guidance. Huge underserved markets: Africa, South Asia, Middle East, Latin America, plus diaspora in US/UK.
3. **Men are an afterthought.** → Gender-neutral design, razor-bump care, minimal routines.
4. **No closed loop.** Scan apps don't know your products; ingredient apps don't know your skin. → Both, plus conflicts, triggers and progress in one place.
5. **Fear-marketing.** "Toxic ingredient" apps erode trust. → Personal, science-based verdicts that also bust myths.
6. **Privacy.** Face photos are sensitive. → On-device storage, no server photo retention, app lock, export/delete.

## Monetisation

- **Free:** onboarding, 1 full scan, routine, 3 product checks/day, check-ins, skin forecast, shelf conflict checks. Safety information (red flags, pregnancy warnings, conflicts) is **never** paywalled.
- **Premium:** unlimited scans (fair-use 3/day), trends per metric, before/after, trigger insights, AI coach, unlimited product checks.
- **Pricing (US):** $39.99/yr with 3-day trial (anchor), $9.99/mo, optional $3.99/wk. Use Play regional pricing — e.g. India, Nigeria and Indonesia at 25–40% of US.
- **Paywall:** shown after onboarding (highest-intent moment), dismissible, honest terms, opt-in "remind me before trial ends" (lowers refunds and 1-star reviews).
- **Later:** affiliate links for routine steps (only if clearly labelled and never ranked by commission), "dermatologist review" referrals via telederm partners.

## Unit economics (AI cost)

Claude Opus 5.5 at $4/$20 per million tokens:
- One scan ≈ 4k input + ~2.5k output (incl. thinking) ≈ **$0.06–0.08**.
- One coach message at low effort ≈ **$0.02–0.03**.
- Heavy Premium user (6 scans + 30 coach messages/month) ≈ **$1.1/month** vs $5–7 revenue → ~80%+ gross margin after store fees.
- Free users cost ~$0.07 each (one scan). Switching `CLAUDE_MODEL` to `claude-sonnet-5-5` roughly halves cost if quality holds — evaluate on real photos first.

## Growth playbook

1. **Built-in virality:** share cards (score, before/after slider export with watermark). Add a referral ("give a friend 7 days of Premium") next.
2. **Short-form video engine:** "I scanned my skin every week for 30 days" / "Rating my skincare shelf" / "Products that are secretly clashing" — pay micro-creators per post plus a CPM bonus. Test 20 creators × 3 hooks before scaling.
3. **ASO:** keywords "skin analysis", "acne", "skincare routine", "ingredient scanner"; screenshots with outcome headlines; respond to every review.
4. **SEO:** auto-generate web pages from the ingredient knowledge base ("Is niacinamide good for oily skin?") linking to the app.
5. **Retention > acquisition:** reminders, streaks, weekly scan ritual, trigger insights at day 14. Retention is what makes paid acquisition profitable.

## Roadmap after launch

- v1.1: crash reporting + analytics funnel, referral programme, home-screen widget (today's routine and UV).
- v1.2: localisation (ES, PT-BR, FR, HI, AR, ID, SW), regional product databases.
- v1.3: iOS App Store launch (StoreKit is already handled by RevenueCat).
- v1.4: left/right profile scans for better analysis, product expiry (PAO) tracker, "dupe finder" for cheaper equivalent products.
- v2: clinically validated on-device model trained with consented, diverse data; dermatologist partnerships; B2B white-label for clinics.
