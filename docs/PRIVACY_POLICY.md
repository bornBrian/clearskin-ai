# ClearSkin AI — Privacy Policy (TEMPLATE)

> **Template only.** Have it reviewed by a lawyer for the countries you launch in before publishing. Replace every [BRACKET].

_Last updated: [DATE]_

[COMPANY LEGAL NAME] ("we") operates the ClearSkin AI mobile app. This policy explains what we process, why, and your choices.

## Summary
- Your face photos, skin scans, check-ins, products and chat history are stored **on your device**.
- To analyse a photo or answer a coach question, we send the photo and/or relevant skin context **encrypted** to our AI provider. It is processed in real time and **not stored on our servers**.
- We do not sell your data, show ads, or use your photos to train AI.
- You can export or permanently delete your data in the app at any time.

## What we process
| Data | Where it lives | Why |
|---|---|---|
| Face photos | Your device. Sent transiently for analysis. | Skin analysis |
| Skin profile (skin type, concerns, age range, optional skin tone, pregnancy status, shaving) | Your device; relevant parts sent with analysis/coach requests | Personalised analysis and routine |
| Check-ins, products, routine logs, chat | Your device; coach requests include a summary | Insights and coaching |
| City (optional) | Your device; coordinates sent to our weather provider | Skin forecast |
| Anonymous account ID | Our servers (Supabase) | Usage limits, linking purchases |
| Usage counters (feature, time, AI token counts) | Our servers, 90 days | Fair-use limits, cost control |
| Purchase status | Google Play / Apple, RevenueCat | Subscriptions |
| Anonymous usage events and crash reports (random install ID, screen/feature used, app version, error details) | PostHog (EU) | Fix crashes, improve the app. Opt out anytime in Settings. Never includes photos, names or skin answers |

We do **not** collect your name (it stays on device), email, contacts, precise location, or advertising ID.

Before any photo leaves your device, we remove location and device metadata (EXIF).

## Processors
- **Anthropic** (AI analysis) — processes photos and skin context to generate results. [Confirm retention terms in your Anthropic agreement; request zero-data-retention if available to you.]
- **Supabase** (backend, [REGION]) — anonymous account and usage counters.
- **RevenueCat** — subscription status.
- **Google Play / Apple** — payments.
- **Open-Meteo** — weather for your chosen city.
- **Open Beauty Facts** — barcode product lookups (the barcode only).
- **PostHog** (EU hosting) — anonymous product analytics and crash reports; opt-out in Settings.

## Sensitive data
Skin photos and health-related information (e.g. pregnancy status, skin conditions) may be considered sensitive or biometric/health data in some jurisdictions. We process it only with your explicit consent (given in-app before your first scan) and only to provide the features you use. We do not create face-recognition templates or identify you from photos.

## Children
ClearSkin AI is not intended for children under 13 and we do not knowingly collect their data. [Adjust minimum age for jurisdictions requiring 16+ consent, e.g. some EU countries.]

## Your rights
In the app: **Settings → Export my data** and **Settings → Delete account & all data** (deletes device data and server records). You can also email [SUPPORT EMAIL]. Depending on where you live (GDPR, UK GDPR, CCPA/CPRA, state health-data laws, etc.) you may have rights to access, correct, delete, restrict or object to processing, and to complain to a regulator.

Uninstalling the app deletes on-device data. Device backups exclude ClearSkin data by design.

## Security
Encryption in transit (TLS), app-private storage on device, optional biometric app lock, server access restricted to backend functions.

## Medical disclaimer
ClearSkin AI provides cosmetic information, not medical advice, diagnosis or treatment.

## Contact
[COMPANY LEGAL NAME], [ADDRESS], [SUPPORT EMAIL]
