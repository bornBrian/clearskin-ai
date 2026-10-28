# ClearSkin AI — Privacy Policy (TEMPLATE)

> **Template only.** Have it reviewed by a lawyer for the countries you launch in before publishing. Replace every [BRACKET]. Publish it at your PRIVACY_URL and keep the in-app link, the Play listing and the Data safety form in sync with it.

_Last updated: [DATE]_

[COMPANY LEGAL NAME] ("we") operates the ClearSkin AI mobile app. This policy explains what we process, why, and your choices.

## Summary
- Your face photos, skin scans, check-ins, products and chat history are stored **on your device**.
- **Your face images are processed in memory for analysis and are never stored on our servers, sold, or shared with advertising networks.** To analyse your skin we send up to three photos (front and both sides) encrypted to our AI provider; they are processed in real time and discarded. Side photos are not kept on your phone either.
- We never use your photos to train AI.
- The free version shows ads. Ads never receive your photos, skin data or answers. Premium has no ads.
- You can export or permanently delete your data in the app at any time.

## What we process
| Data | Where it lives | Why |
|---|---|---|
| Face photos (front, plus optional left and right side views) | Front photo: your device. All photos: sent transiently for analysis, never stored on our servers | Skin analysis |
| Issues you flag before a scan (e.g. dryness, redness) | Sent with the analysis request | Focus the analysis |
| Skin profile (skin type, concerns, age range, optional skin tone, pregnancy status, shaving) | Your device; relevant parts sent with analysis/coach requests | Personalised analysis and routine |
| Check-ins, products, routine logs, chat | Your device; coach requests include a summary | Insights and coaching |
| City (optional) | Your device; coordinates sent to our weather provider | Skin forecast |
| Anonymous account ID | Our servers (Supabase) | Usage limits, linking purchases |
| Device fraud-prevention ID (a one-way SHA-256 hash of the app-specific Android ID) | Our servers, with usage counters | Stopping abuse of free scans. Never linked to advertising |
| Usage counters (feature, time, AI token counts and cost) | Our servers, 90 days. If you delete your account they are unlinked from it and kept with only the device fraud-prevention ID until the 90 days end | Fair-use limits, cost control, stopping free-scan resets |
| Rewarded-video credits (ad network transaction ID) | Our servers | Granting the extra scan you earned |
| App integrity verdict (from Google Play Integrity) | Checked by our servers, not stored | Blocking modified copies of the app |
| Purchase status | Google Play / Apple, RevenueCat | Subscriptions and renewal reminders |
| Advertising ID, approximate location from IP, device and ad-interaction data (**free version only, and only after the consent prompt where required**) | Google AdMob and its mediation partners | Showing and measuring ads |
| Anonymous usage events and crash reports (random install ID, screen/feature used, app version, error details) | PostHog (EU) | Fix crashes, improve the app. Opt out anytime in Settings. Never includes photos, names or skin answers |

We do **not** collect your name (it stays on device), contacts or precise location. Before any photo leaves your device, we remove location and device metadata (EXIF).

## Advertising
Free users see a banner on the routine screen, an occasional full-screen ad after finishing a routine (capped per day, never in your first days), and optional rewarded videos you choose to watch for an extra scan.
- Where the law requires consent (e.g. EEA, UK, Switzerland and some US states), Google's consent form asks you before any ad is requested. Change your choice anytime in **Settings → Ad privacy choices**.
- For users aged 13–17 we request only non-personalised ads rated PG or below.
- We block sensitive ad categories, including gambling, dating, alcohol and weight loss.
- Premium removes all ads; the ad SDK makes no ad requests for Premium users.

## Shopping links
Some routine steps and reports link to a search for that product type at an online store in your region (based on your phone's region setting). These are affiliate links: we may earn a commission if you buy, at no cost to you. The store sees that you came from ClearSkin; we never send it your skin data. Our recommendations are made by our routine engine and never depend on commissions.

## Processors
- **Anthropic** (AI analysis and coach) — processes photos and skin context to generate results. [Confirm retention terms in your Anthropic agreement; request zero-data-retention if available to you.]
- **Google (Gemini API)** — [Only if you enable the backup AI provider. Paid tier only. Remove this line if not used.]
- **Supabase** (backend, [REGION]) — anonymous account, usage counters, rewarded-video credits.
- **RevenueCat** — subscription status.
- **Google Play / Apple** — payments; **Google Play Integrity** — app authenticity checks.
- **Google AdMob**, with mediation partners **AppLovin**, **Meta Audience Network** and **Unity Ads** — ads for free users.
- **[Affiliate programmes, e.g. Amazon Associates]** — shopping links.
- **Open-Meteo** — weather for your chosen city.
- **Open Beauty Facts** — barcode product lookups (the barcode only).
- **PostHog** (EU hosting) — anonymous product analytics and crash reports; opt-out in Settings.

## Sensitive data
Skin photos and health-related information (e.g. pregnancy status, skin conditions) may be considered sensitive, biometric or consumer health data in some jurisdictions. We process it only with your explicit consent (given in-app before your first scan) and only to provide the features you use. We do not create face-recognition templates, identify you from photos, or share this data with advertisers.

## Children
ClearSkin AI is not intended for children under 13 and we do not knowingly collect their data. Users aged 13–17 receive only non-personalised, PG-rated ads. [Adjust minimum age for jurisdictions requiring 16+ consent, e.g. some EU countries.]

## Your rights
In the app: **Settings → Export my data** and **Settings → Delete account & all data** (deletes device data, your account, credits and purchase record; usage counters are unlinked from you and expire within 90 days). You can also email [SUPPORT EMAIL]. Depending on where you live (GDPR, UK GDPR, CCPA/CPRA, Washington My Health My Data Act and other state health-data laws, Tanzania's Personal Data Protection Act 2022, Kenya's Data Protection Act 2019, etc.) you may have rights to access, correct, delete, restrict or object to processing, and to complain to a regulator.

Uninstalling the app deletes on-device data. Device backups exclude ClearSkin data by design.

## Security
Encryption in transit (TLS only; the app refuses unencrypted connections), app-private storage on device, optional biometric app lock, server-side checks of every paid feature, signed purchase and reward verification, and app-integrity checks. Our servers never hold AI provider keys in the app; they live only in our backend.

## Medical disclaimer
ClearSkin AI provides cosmetic information, not medical advice, diagnosis or treatment. You acknowledge this before using the app.

## Contact
[COMPANY LEGAL NAME], [ADDRESS], [SUPPORT EMAIL]
