# Google Play launch checklist

Do these in order. Items marked ⚠️ block approval if skipped.

## 1. Accounts & services (≈1–2 hours)

1. **Google Play Console** — one-time $25. Use an *organization* account if you have a registered business (D-U-N-S number); personal accounts created after Nov 2023 must run a **closed test with ≥12 testers for 14 continuous days** before production access. Recruit testers early (friends, family, Reddit r/AndroidClosedTesting).
2. **Supabase** (free tier) — create project, enable *Anonymous sign-ins* (Auth → Providers).
3. **Anthropic Console** — create API key, add billing, set a monthly spend limit.
4. **RevenueCat** (free up to $2.5k MTR) — create project → Android app with package `com.clearskinai.app`.
5. **PostHog** (free up to 1M events/month) — create an EU project, copy the *Project API key* into `POSTHOG_KEY` in `env/prod.json`. This powers the funnel dashboard (onboarding → plan → paywall → trial → scan) and crash reports. Build these insights first: *Funnel* `onboarding_complete → paywall_view → purchase_result (outcome=success)`, and *Trends* on `app_error`.
6. **Domain + website** — buy one domain (≈$10–15/year) at **Cloudflare Registrar** (sells at cost, free DNS, free SSL). Point it at the existing GitHub Pages site (`/privacy`, `/terms`, `/delete-account`, a landing page with the Play badge). Check the name is free on Play and Instagram/TikTok first; `.app` forces HTTPS, which is good.
7. **Email on the domain** — **Cloudflare Email Routing** (free) forwards `support@`, `privacy@`, `hello@` to your Gmail; to *send* as them, add the address in Gmail → "Send mail as" through a free SMTP relay, or use **Zoho Mail Free** (5 users). Upgrade to Google Workspace (~$7/user/month) once revenue comes in. Use `support@yourdomain` everywhere: Play listing, `SUPPORT_EMAIL`, privacy policy, Supabase sender.
8. **Google AdMob** — create the app (Android, package `com.clearskinai.app`) and three ad units: *Banner* (routine), *Interstitial* (routine complete), *Rewarded* (extra scan). See §6b.
9. **Google Cloud project for Play Integrity** — Play Console → Test and release → App integrity → link a Cloud project; enable the *Play Integrity API*; create a service account with no roles and a JSON key. See §6c.
10. **Affiliate programmes** — Amazon Associates for each marketplace you target (US, UK, DE…); each gives a tag like `yourtag-20`. Add them to `SHOP_CONFIG_JSON` (§2). Links appear only in regions you configure.

## 2. Backend deploy

```bash
npm i -g supabase
supabase login
supabase link --project-ref <your-ref>
supabase db push
cp supabase/functions/.env.example supabase/functions/.env   # fill in real values
supabase secrets set --env-file supabase/functions/.env
supabase functions deploy analyze-skin coach delete-account account-status admob-rewarded app-attest apple-token
```

Before every backend deploy, run the attack tests (forged integrity tokens and iPhone attestations, fake rewards, swapped user ids, injection, oversized bodies, Premium faking) and the database tests (client permissions, data integrity, simultaneous requests) against a local Postgres. GitHub CI runs both on every push:

```bash
cd supabase/functions && deno fmt --check && deno lint && deno test --allow-env --allow-read=. --allow-net=127.0.0.1 _tests/
PGHOST=127.0.0.1 PGUSER=postgres PGPASSWORD=... bash supabase/tests/run.sh   # throwaway local database only
```

Server settings that matter (all in `supabase/functions/.env.example`):

| Setting | Launch value | Why |
|---|---|---|
| `DAILY_SPEND_LIMIT_USD` | 25 | Hard stop on AI cost per day. Raise as revenue grows |
| `CLAUDE_MODEL` / `CLAUDE_FALLBACK_MODEL` | `claude-opus-5-5` / `claude-sonnet-5-5` | Fallback kicks in automatically when the main model is overloaded or down |
| `GEMINI_API_KEY` | empty | Optional third provider. Paid tier only; add Google to the privacy policy first |
| `FREE_SCANS_PER_WINDOW` / `FREE_SCAN_WINDOW_DAYS` | 2 / 30 | Free plan, counted per account **and** per device |
| `REWARDED_SCANS_PER_DAY` | 1 | Extra scans from rewarded videos |
| `SCAN_ATTEMPTS_PER_DAY` / `COACH_ATTEMPTS_PER_DAY` | 10 / 80 | Cap on tries per account or device, including refunded unusable photos |
| `INTEGRITY_MODE` | `log` while testing, **`enforce` at production launch** | Blocks modified/sideloaded copies from using AI |
| `SHOP_CONFIG_JSON` | your affiliate tags | Regional shop links, changeable without an app release |

Cost per scan (front + two side photos at ≤1024 px, cached system prompt, medium effort) is roughly **$0.03–0.06 on Opus 5.5**, about half that on Sonnet 5.5. Check real numbers any time:

```sql
select model, count(*), round(avg(cost_usd)::numeric, 4) as avg_usd, sum(cost_usd) as total
from usage_events where created_at > now() - interval '7 days' group by model;
```

### Sign in with Google + e-mail codes

1. **Google Cloud Console → APIs & Services → Credentials** (same Google account as Play is easiest):
   - Configure the **OAuth consent screen** (app name *ClearSkin*, support e-mail, privacy URL, logo `docs/store/play-icon-512.png`). Scopes: `email`, `profile`, `openid` only.
   - Create a **Web application** client → this is `GOOGLE_WEB_CLIENT_ID`.
   - Create an **Android** client with package **`com.clearskinai.app`** (the `applicationId` in `android/app/build.gradle.kts`) for **each** key that signs the app — one client per SHA-1:
     - your **debug** key, for `flutter run` on your phone. Print it with
       `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android` (on this PC: `46:F8:CD:A3:00:1C:A7:65:0D:8E:61:57:C0:00:8C:50:B8:18:49:EE`);
     - your **upload** key;
     - **Play's app-signing key** (Play Console → Setup → App signing). Missing it is the #1 reason Google sign-in works in testing and fails in production.
   - Put the Web client id in `env/dev.json` as `GOOGLE_WEB_CLIENT_ID` and run `flutter run --dart-define-from-file=env/dev.json`. Real Google sign-in works from that moment, even before Supabase is connected (the account is then kept on the phone only).
   - (Later, for iOS) create an **iOS** client → `GOOGLE_IOS_CLIENT_ID`, and add its reversed id as a URL scheme in `ios/Runner/Info.plist`.
2. **Supabase → Authentication → Providers → Google**: enable, paste the Web client id + secret, and add the Android/iOS client ids to *Authorized Client IDs*. Turn on **Allow anonymous sign-ins** and **Manual linking** (Authentication → Settings) — the app links Google to the existing anonymous user so purchases keep the same id.
3. **Supabase → Authentication → Providers → Email**: enable, and edit the *Magic Link / OTP* template so it shows `{{ .Token }}` (the app asks for the 6-digit code, not a link). Use a custom SMTP sender (Resend/Postmark) before launch — Supabase's built-in mailer is rate-limited.

## 3. App config

```bash
copy env\example.json env\prod.json      # fill in real values
powershell -ExecutionPolicy Bypass -File scripts/create-upload-keystore.ps1
```

`env/prod.json` must have: `RC_ANDROID_KEY` (RevenueCat **public** Google key, starts `goog_`), the four `ADMOB_*` ids, `PLAY_INTEGRITY_PROJECT_NUMBER`, and `EXPECTED_SIGNING_SHA256` = the SHA-256 of **Play's app-signing certificate** plus your **upload** certificate, comma-separated (Play Console → App integrity → App signing shows both). With it set, any re-signed copy of the APK refuses to run. Leave `AI_DEMO` false.

⚠️ Back up `%USERPROFILE%\.clearskin\clearskin-upload.jks` and its password.

## 4. App icon

Already generated: cream "C·skin" mark on charcoal for Android (legacy + adaptive + themed), iOS, and `docs/store/play-icon-512.png`. To change it, edit `scripts/brand/generate_brand.py` and run `python scripts/brand/generate_brand.py`. Do a trademark search on the name and mark before launch.

## 4b. Notification sounds

Each kind of notification has its own sound, made by `python scripts/brand/generate_sounds.py` (files in `android/app/src/main/res/raw/`):

| Sound | Used for | Android channel |
|---|---|---|
| `clearskin_morning` | Morning routine | Morning routine |
| `clearskin_evening` | Evening routine, daily check-in | Evening routine |
| `clearskin_streak` | Streak about to end | Streak alerts |
| `clearskin_milestone` | Day 30 / 60 / 90 | Milestones |
| `clearskin_chime` | Scan day, sun alerts, product expiry, Premium | Tips & updates |

Android fixes a channel's sound when it's created, so if you change a sound, give its channel a new id in `lib/services/notification_service.dart` (e.g. `morning_v1` → `morning_v2`) and add the old id to `_retiredChannels`. New sound files must also be listed in `res/raw/keep.xml`, or release builds strip them. **iOS (later):** drag the five `ios/Runner/clearskin_*.wav` files into the Runner target in Xcode; until then iOS plays the default sound.

## 5. Build

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-release.ps1
```

It refuses to build with a missing key, sample ids or `AI_DEMO=true`, then runs `flutter build appbundle` with `--obfuscate --split-debug-info` (R8 minification and resource shrinking are on in Gradle).

Before a release, also run the small-phone pass: every screen at 320 dp wide with the largest text size, failing on any cut-off layout (PowerShell: `$env:QA='small'; flutter test tool/screenshots/render_screens_test.dart`).

Output: `build/app/outputs/bundle/release/app-release.aab`. Keep `build/symbols` for crash de-obfuscation.
Bump `version:` in `pubspec.yaml` (the `+N` build number) for every upload.

## 6. Subscriptions (Play Console → Monetize → Subscriptions)

**Why the paywall shows no prices today:** `RC_ANDROID_KEY` is empty in `env/dev.json`, and no products exist yet. Prices come from Google Play through RevenueCat, so they appear only after *all* of these are done. The paywall now says which step is missing.

1. Upload any signed AAB to **Internal testing** first. Play won't let you create subscriptions for an app with no upload.
2. Create subscription `clearskin_premium` with base plans:

| Base plan | Type | Price (US) | Offer |
|---|---|---|---|
| `monthly` | Auto-renewing | $4.99 / month | — |
| `annual` | Auto-renewing | $29.99 / year | 3-day free trial (new customers) |
| `monthly-prepaid` | **Prepaid** | $4.99 / month | — (lets people pay once with mobile money or carrier billing, no card) |

   Set local prices with Play's pricing templates. In Tanzania, round to friendly TZS amounts (e.g. ~TZS 9,900/month, ~TZS 59,000/year); Google converts and shows local currency.
3. RevenueCat → Project → Google Play app → upload the **Play service-account JSON** (required for receipt validation; takes up to 36 hours to activate at Google).
4. RevenueCat → Products → import → Entitlement `premium` (attach all three) → Offering `default` with packages `$rc_monthly`, `$rc_annual` and a custom package for the prepaid plan → make it *Current*.
5. Copy RevenueCat's **public** Google API key into `RC_ANDROID_KEY` in `env/dev.json` and `env/prod.json`. Copy the **secret** key into `REVENUECAT_SECRET_KEY` on the server only.
6. Add yourself under Play Console → Settings → **License testing** to buy without being charged.

How expiry works: RevenueCat tracks every period. When a cancelled or prepaid plan is a week from ending, the app shows a banner and notification; people can renew, pick a reminder date and time, or turn reminders off (Settings → Renewal reminders). At expiry the entitlement goes inactive in RevenueCat and on our server, so Premium stops on its own. Failed renewals show "Fix payment" during Google's grace period.

## 6b. AdMob (free users only)

1. App + three units (banner, interstitial, rewarded). Put the app id in `ADMOB_APP_ID` and the units in `ADMOB_BANNER_ID`, `ADMOB_INTERSTITIAL_ID`, `ADMOB_REWARDED_ID`.
2. **Rewarded unit → Server-side verification**: callback URL `https://<project-ref>.supabase.co/functions/v1/admob-rewarded`. This is what grants the extra scan; without it the video plays but no scan is credited.
3. **Blocking controls → Sensitive categories**: block *Gambling, Dating, Alcohol, Weight loss, Cosmetic procedures & body modification, Get rich quick, Politics, Religion, References to sex & sexuality*. **General categories**: block *Drugs & supplements*. **Content rating**: max *T*. The app also caps teens at PG with non-personalised ads.
4. **Privacy & messaging → GDPR and US state messages**: create both (Google's consent form). Without them, EEA/UK users get no ads.
5. **Mediation**: add groups for Banner, Interstitial and Rewarded with **AppLovin**, **Meta Audience Network** and **Unity Ads** as bidding sources (create accounts at each, paste their ids into AdMob). The SDK adapters are already in the app.
6. Play Console → App content → **Ads: Yes**. Data safety: add *Device or other IDs* (advertising ID, shared with AdMob for advertising, optional via consent) and *App interactions*.

## 6c. Play Integrity (anti-tamper)

1. Play Console → App integrity → *Integrity API* → link your Cloud project; copy the **project number** into `PLAY_INTEGRITY_PROJECT_NUMBER`.
2. In that Cloud project enable *Google Play Integrity API*; create a service account and JSON key; `supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON="$(base64 key.json)"`.
3. Keep `INTEGRITY_MODE=log` for sideloaded tester APKs (Google reports them as unrecognised). Switch to `enforce` the day production opens: from then on only the Play-installed, unmodified app on a genuine device can use AI.

What this protects against, plainly: a patched or re-signed APK can't get AI scans or the coach (server checks integrity, Premium via RevenueCat, quotas per account and device), can't fake purchases (Google validates receipts through RevenueCat), and can't mint rewarded scans (Google signs every reward). No keys or secrets are in the app to extract. Purely on-device screens could in theory be unlocked in a modified copy, but such copies refuse to run when `EXPECTED_SIGNING_SHA256` is set, and they get nothing that costs money.

## 7. Store listing ⚠️

Copy from `docs/STORE_LISTING.md`. Assets: icon 512×512, feature graphic 1024×500, 4–8 phone screenshots (1080×1920+). Screenshots convert best with a headline on each ("See your skin score in 10 seconds").

## 8. Policy forms ⚠️ (Play Console → App content)

- **Privacy policy URL** — required.
- **App access** — an account is required (created right after the intro). Choose "All or some functionality is restricted" and tell reviewers: *"Tap Get started → Next through the intro → Continue with Google, using any Google account. No invitation or test credentials are needed."* Google sign-in must work on Play's app-signing key before you submit, or the review fails.
- **Ads** — Yes, the app contains ads (free users).
- **Content rating** — complete IARC questionnaire (no violence etc.) → likely "Everyone"/"PEGI 3".
- **Target audience** — 13+ (select 13–15, 16–17, 18+). Do NOT select under-13 (Families policy). Because 13–17 is included, avoid any mature content; the app has none.
- **Health apps declaration** — category "Health & fitness / wellness". State it is not a medical device and does not diagnose.
- **Data safety** — declare:
  - *Photos* — collected, **not stored on server**, processed ephemerally (sent to AI provider for analysis), not shared for advertising. Purpose: App functionality.
  - *Health & fitness info* (skin data, check-ins) — stored on device only → "not collected" by Play's definition *only if it never leaves the device*. Skin context IS sent to the AI for analysis/coach, so declare it as collected, processed ephemerally, purpose App functionality.
  - *App activity / identifiers* — user ID for quotas & purchases; a hashed device ID for fraud prevention (not shared).
  - *Device or other IDs → Advertising ID* — collected and shared with AdMob for advertising (free users, after consent).
  - *Photos* also covers the two side views; all are processed ephemerally and never shared.
  - *Personal info → Email address and Name* — only if the person signs in with Google or e-mail. Purpose: Account management. Not shared.
  - *Purchase history* — via Google Play/RevenueCat.
  - Data encrypted in transit: Yes. Users can request deletion: Yes (in-app).
- **Account deletion** — in-app path: Settings → Delete account & all data. Also provide a web URL (a simple page with instructions + support email) — Play requires a web link too.
- **Government apps / financial / news** — not applicable.

## 9. Testing tracks

1. **Internal testing** (instant, up to 100 testers) — upload the AAB, add yourself as license tester (Settings → License testing) to test purchases free.
2. **Closed testing** — 12+ testers opted in for **14 consecutive days** (personal accounts created after Nov 2023), then apply for production; Google's review of that application usually takes up to 7 days. Start this as early as possible; it is the longest lead time in the whole launch.
3. **Production** — staged rollout 20% → 50% → 100%.

Test on a real device: scan in good/bad light, product barcode (try a CeraVe/La Roche-Posay barcode), OCR label, reminders after reboot, app lock, purchase + restore, delete account.

## 10. Before scaling

- Wire crash reporting (Firebase Crashlytics or Sentry) in `lib/main.dart` `_report()`.
- Add analytics (PostHog/Firebase) for the funnel: onboarding complete → paywall view → trial start → day-3 conversion.
- Buy an Open-Meteo commercial key (or switch provider) once you have revenue — their free tier is non-commercial.
- Anthropic: monitor cost per scan in `usage_events` (input/output tokens are recorded). Set `CLAUDE_MODEL` to change model without an app update.
- Legal review of privacy policy & terms for your jurisdiction (GDPR/UK, CCPA/CPRA, Illinois/Texas/Washington biometric & health-data laws, Nigeria NDPA, etc.).
