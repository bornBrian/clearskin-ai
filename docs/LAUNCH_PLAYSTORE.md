# Google Play launch checklist

Do these in order. Items marked ⚠️ block approval if skipped.

## 1. Accounts & services (≈1–2 hours)

1. **Google Play Console** — one-time $25. Use an *organization* account if you have a registered business (D-U-N-S number); personal accounts created after Nov 2023 must run a **closed test with ≥12 testers for 14 continuous days** before production access. Recruit testers early (friends, family, Reddit r/AndroidClosedTesting).
2. **Supabase** (free tier) — create project, enable *Anonymous sign-ins* (Auth → Providers).
3. **Anthropic Console** — create API key, add billing, set a monthly spend limit.
4. **RevenueCat** (free up to $2.5k MTR) — create project → Android app with package `com.clearskinai.app`.
5. **PostHog** (free up to 1M events/month) — create an EU project, copy the *Project API key* into `POSTHOG_KEY` in `env/prod.json`. This powers the funnel dashboard (onboarding → plan → paywall → trial → scan) and crash reports. Build these insights first: *Funnel* `onboarding_complete → paywall_view → purchase_result (outcome=success)`, and *Trends* on `app_error`.
6. **Domain + website** — a one-page site hosting `/privacy` and `/terms` (templates in `docs/`). Free options: GitHub Pages, Carrd, Notion public page.
7. **Support email** — e.g. support@yourdomain.

## 2. Backend deploy

```bash
npm i -g supabase
supabase login
supabase link --project-ref <your-ref>
supabase db push
cp supabase/functions/.env.example supabase/functions/.env   # fill in real values
supabase secrets set --env-file supabase/functions/.env
supabase functions deploy analyze-skin coach delete-account
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

⚠️ Back up `%USERPROFILE%\.clearskin\clearskin-upload.jks` and its password.

## 4. App icon

Already generated: cream "C·skin" mark on charcoal for Android (legacy + adaptive + themed), iOS, and `docs/store/play-icon-512.png`. To change it, edit `scripts/brand/generate_brand.py` and run `python scripts/brand/generate_brand.py`. Do a trademark search on the name and mark before launch.

## 5. Build

```bash
flutter clean
flutter build appbundle --release --dart-define-from-file=env/prod.json --obfuscate --split-debug-info=build/symbols
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Keep `build/symbols` for crash de-obfuscation.
Bump `version:` in `pubspec.yaml` (the `+N` build number) for every upload.

## 6. Subscriptions (Play Console → Monetize → Subscriptions)

Create one subscription `clearskin_premium` with base plans:

| Base plan | Price (US) | Offer |
|---|---|---|
| `annual` | $39.99 / year | 3-day free trial (new customers) |
| `monthly` | $9.99 / month | — |
| `weekly` | $3.99 / week | — (optional; test whether it helps or hurts) |

Use Play's **regional pricing templates** — set lower prices in India, Nigeria, Brazil, Indonesia, etc. Then in RevenueCat: import products → entitlement `premium` → offering `default` with packages `$rc_annual`, `$rc_monthly`, `$rc_weekly`. Link Play service-account credentials in RevenueCat (required for receipt validation).

## 7. Store listing ⚠️

Copy from `docs/STORE_LISTING.md`. Assets: icon 512×512, feature graphic 1024×500, 4–8 phone screenshots (1080×1920+). Screenshots convert best with a headline on each ("See your skin score in 10 seconds").

## 8. Policy forms ⚠️ (Play Console → App content)

- **Privacy policy URL** — required.
- **App access** — an account is required (created right after the intro). Choose "All or some functionality is restricted" and tell reviewers: *"Tap Get started → Next through the intro → Continue with Google, using any Google account. No invitation or test credentials are needed."* Google sign-in must work on Play's app-signing key before you submit, or the review fails.
- **Ads** — No ads.
- **Content rating** — complete IARC questionnaire (no violence etc.) → likely "Everyone"/"PEGI 3".
- **Target audience** — 13+ (select 13–15, 16–17, 18+). Do NOT select under-13 (Families policy). Because 13–17 is included, avoid any mature content; the app has none.
- **Health apps declaration** — category "Health & fitness / wellness". State it is not a medical device and does not diagnose.
- **Data safety** — declare:
  - *Photos* — collected, **not stored on server**, processed ephemerally (sent to AI provider for analysis), not shared for advertising. Purpose: App functionality.
  - *Health & fitness info* (skin data, check-ins) — stored on device only → "not collected" by Play's definition *only if it never leaves the device*. Skin context IS sent to the AI for analysis/coach, so declare it as collected, processed ephemerally, purpose App functionality.
  - *App activity / identifiers* — user ID for quotas & purchases.
  - *Personal info → Email address and Name* — only if the person signs in with Google or e-mail. Purpose: Account management. Not shared.
  - *Purchase history* — via Google Play/RevenueCat.
  - Data encrypted in transit: Yes. Users can request deletion: Yes (in-app).
- **Account deletion** — in-app path: Settings → Delete account & all data. Also provide a web URL (a simple page with instructions + support email) — Play requires a web link too.
- **Government apps / financial / news** — not applicable.

## 9. Testing tracks

1. **Internal testing** (instant, up to 100 testers) — upload the AAB, add yourself as license tester (Settings → License testing) to test purchases free.
2. **Closed testing** — 12+ testers × 14 days (if personal account).
3. **Production** — staged rollout 20% → 50% → 100%.

Test on a real device: scan in good/bad light, product barcode (try a CeraVe/La Roche-Posay barcode), OCR label, reminders after reboot, app lock, purchase + restore, delete account.

## 10. Before scaling

- Wire crash reporting (Firebase Crashlytics or Sentry) in `lib/main.dart` `_report()`.
- Add analytics (PostHog/Firebase) for the funnel: onboarding complete → paywall view → trial start → day-3 conversion.
- Buy an Open-Meteo commercial key (or switch provider) once you have revenue — their free tier is non-commercial.
- Anthropic: monitor cost per scan in `usage_events` (input/output tokens are recorded). Set `CLAUDE_MODEL` to change model without an app update.
- Legal review of privacy policy & terms for your jurisdiction (GDPR/UK, CCPA/CPRA, Illinois/Texas/Washington biometric & health-data laws, Nigeria NDPA, etc.).
