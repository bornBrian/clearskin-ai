# ClearSkin AI

AI skin coach for every skin tone and every gender. Flutter (Android + iOS from
one codebase), Supabase Edge Functions, Claude vision, RevenueCat.

## What's inside

| Area | What it does | Where |
|---|---|---|
| AI skin scan | Guided selfie → on-device quality checks (face position, light, blur) → Claude analysis of 9 metrics, findings, red flags | `lib/features/scan`, `lib/services/photo_service.dart`, `supabase/functions/analyze-skin` |
| Routine engine | Deterministic, rule-based AM/PM routine with skin-cycling schedule; pregnancy/sensitivity/skin-tone/shaving aware | `lib/domain/routine` |
| Ingredient intelligence | ~150-ingredient curated knowledge base, INCI parser, per-user product verdicts, shelf conflict checker | `lib/domain/ingredients` |
| Product scanner | Barcode → Open Beauty Facts; label photo → on-device OCR; manual entry | `lib/features/products` |
| Progress | Score trends, photo timeline, before/after slider with share | `lib/features/progress` |
| 12-week journey | Concern-specific programme (clear, fade, calm, smooth, balance, shave, glow): Reset → Treat → Refine → Glow, goal score, pregnancy-safe swaps, "see a dermatologist" escalation | `lib/domain/journey`, `lib/features/journey` |
| Reminders & alerts | Adjustable AM/PM (evening copy names tonight's active), check-in, weekly scan day; smart alerts for streaks, high UV and come-backs; in-app nudges by time of day and activity | `lib/services/notification_service.dart`, `lib/domain/nudges`, `lib/features/settings/reminders_screen.dart` |
| Accounts | Required before onboarding: Continue with Google (linked to the anonymous user, so purchases keep their id) or 6-digit e-mail code. Signed out → welcome screen; another account never sees this phone's data | `lib/services/auth_service.dart`, `lib/features/auth` |
| Trigger insights | Lagged correlation of daily check-ins (diet, sleep, stress…) with breakouts | `lib/domain/insights` |
| Skin forecast | UV, humidity, temperature, air quality → daily advice | `lib/domain/forecast`, `lib/services/weather_service.dart` |
| AI coach | Context-aware chat (profile, scan, routine, shelf) | `lib/features/coach`, `supabase/functions/coach` |
| Monetization | RevenueCat subscriptions, server-verified entitlements, honest trial reminder | `lib/services/purchases_service.dart`, `lib/features/paywall` |
| Privacy | Photos & data on-device only, EXIF stripped, app lock, export, full deletion, backups excluded | throughout |

## Architecture

```
lib/
  core/        config, theme tokens, router, providers (Riverpod), shared widgets
  data/        models, SQLite database + repositories
  domain/      pure Dart business logic — unit tested, no Flutter imports
  services/    platform & network integrations
  features/    screens, one folder per feature
supabase/
  functions/   analyze-skin, coach, delete-account (Deno/TypeScript)
  migrations/  usage_events table (quotas only — no personal data)
```

Design principles:

- **Personal data stays on the phone.** The server stores only usage counters.
- **AI where it adds value, rules where safety matters.** The routine and ingredient checks are deterministic and tested; the AI analyses photos and answers questions.
- **No secrets in the app.** Anthropic, RevenueCat-secret and Supabase service keys live only in Edge Function secrets.
- **Re-skinnable.** Every colour, radius and font is a token in `lib/core/theme/tokens.dart`.

## Run it

```bash
flutter pub get
flutter test                      # domain logic tests
flutter run                       # debug: demo mode (sample AI results) until env is set
flutter run --dart-define-from-file=env/dev.json   # with real backend
```

Design review without a phone (renders real screens with real fonts to `design/renders/`):

```bash
flutter test tool/screenshots --update-goldens
```

Brand assets (logo, launcher icons for Android + iOS, Play Store icon and feature graphic) are generated from one script — edit the colours there and re-run:

```bash
python scripts/brand/generate_brand.py
```

Copy `env/example.json` to `env/dev.json` / `env/prod.json` and fill in values.
In debug builds without a backend, scans return sample data and Settings → Developer lets you toggle Premium.

| Setting | Effect |
|---|---|
| No `SUPABASE_URL` | Demo mode (debug only): sample AI, local sign-in |
| `AI_DEMO: "true"` | Real backend for accounts and quotas, sample AI results (debug or preview builds only) |
| Neither | Fully real: Supabase + Claude analysis |

## Backend

```bash
supabase link --project-ref <ref>
supabase db push
cp supabase/functions/.env.example supabase/functions/.env   # fill in
supabase secrets set --env-file supabase/functions/.env
supabase functions deploy analyze-skin coach delete-account
```

## Release

Signing uses the upload keystore created by `scripts/create-upload-keystore.ps1`
(`android/key.properties` points to it; both stay off git — back them up).

```bash
# Tester build: installable APK, real accounts, sample AI clearly labelled
flutter build apk --release --dart-define-from-file=env/dev.json --dart-define=PREVIEW_BUILD=true

# Store build: real AI only
flutter build appbundle --release --dart-define-from-file=env/prod.json
```

See [docs/LAUNCH_PLAYSTORE.md](docs/LAUNCH_PLAYSTORE.md) for the full Google Play checklist
and [docs/STRATEGY.md](docs/STRATEGY.md) for the business plan.
