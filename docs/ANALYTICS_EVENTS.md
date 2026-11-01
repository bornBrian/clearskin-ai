# ClearSkin AI: analytics event dictionary

One list of events and definitions, shared by product, growth and engineering. It is the source for the weekly dashboard (playbook sections 5 and 12). Events go to PostHog (EU) from `lib/services/telemetry.dart`. Names never change once shipped, because dashboards depend on them.

## Sent with every event

| Property | Meaning |
|---|---|
| `distinct_id` | Random install ID. Not linked to name, email or account. |
| `platform` | `android` / `iOS` |
| `app_version` | e.g. `1.0.0+7` |
| `locale` | Language and region setting, e.g. `en-TZ`. Used to read results by market. |
| `timestamp` | UTC |

**Never sent:** photos, skin readings beyond a single score, health answers, names, emails, product ingredient lists. Users can turn analytics off in Settings, and then nothing is sent.

## Events by funnel stage

| Stage | Event | Properties | Decision it informs |
|---|---|---|---|
| Open | `app_open` |  | Daily and weekly actives (DAU/WAU), D1/D7/D30 retention |
| Onboarding | `onboarding_started` |  | Where setup begins |
| Onboarding | `onboarding_complete` | `gender`, `age`, `skin_type`, `complexity`, `concerns` (count), `has_city` | Setup completion rate; segments |
| Onboarding | `plan_reveal_view` |  | Did they see the 12-week plan |
| Consent | `consent_given` | `kind`: `medical` or `photos` | Consent completion (the Trust scorecard row) |
| Activation | `scan_started` |  | First-scan start rate |
| Activation | `scan_auto_captured` |  | Capture guidance working |
| Activation | `scan_quality_issue` | `issues` (blur, dark, angle...) | Which capture problems block people |
| Activation | `scan_completed` | `score`, `usable`, `red_flags` (count), `on_device`, `reason` (if on-device), `scan_number`, `ms` (time to result) | Scan success, time to value, how often the phone fallback is used |
| Activation | `scan_failed` | `kind`: offline, server, badImage, quotaExceeded, premiumRequired... | Failure reasons to fix |
| Activation | `scan_result_viewed` | `scan_number`, `on_device`, `usable` | **Activation**: `scan_number = 1` is first value, `scan_number = 2` is the second-scan habit |
| Retention | `routine_completed` | `slot`: am / pm | Routine adherence |
| Retention | `checkin_saved` | `tags` (count) | Journal use |
| Retention | `tip_opened` | `id` (tip or `guide_<id>`) | Which education gets read |
| Retention | `coach_message_sent` | `turn` | Coach engagement (Premium) |
| Retention | `product_added` | `source`: barcode or manual_or_ocr, `category` | Shelf use |
| Monetisation | `paywall_view` | `source` (where it opened) | Paywall reach by placement |
| Monetisation | `purchase_result` | `outcome`, `plan`, `trial`, `source` | Conversion by plan and placement |
| Monetisation | `renewal_action` | `action`, `banner` | Renewal saves |
| Monetisation | `rewarded_result` | `earned` | Rewarded-ad scans |
| Monetisation | `out_of_scans` |  | Free-limit pressure |
| Monetisation | `shop_link_opened` | `source`, `store` | Shop revenue potential |
| Referral | `share_card_shared` | `style`, `format` or `days` | Organic sharing |
| Quality | `app_error` | `type`, `message` (capped), `stack` (capped), `context` | Crash-free sessions |

Server-side, every AI call is written to `usage_events` with its model, tokens, cost in dollars and kind (`scan`, `coach`, `insight`). This is kept apart from user analytics, as the playbook requires. Daily spend alerts go to the function logs at 50% and 80% of `DAILY_SPEND_LIMIT_USD` (search for "SPEND ALERT"). New AI calls stop at 100%.

## Where installs come from (acquisition)

Every Google Play link on the websites carries a UTM referrer, so **Play Console → Statistics / Store performance → acquisition by UTM** shows which source sent each install:

| Source | Link tag |
|---|---|
| clearskin.britechapps.com pages | `utm_source=clearskin_site&utm_medium=website` |
| The 8 guide pages | `utm_source=clearskin_guides&utm_medium=website` |
| britechapps.com | `utm_source=britechapps&utm_medium=website` |

For social posts, use the same pattern, e.g. Instagram bio:
`https://play.google.com/store/apps/details?id=com.clearskinai.app&referrer=utm_source%3Dinstagram%26utm_medium%3Dsocial`
TikTok: `utm_source%3Dtiktok`, WhatsApp: `utm_source%3Dwhatsapp`, each creator: `utm_source%3Dcreator_<name>`.

## Weekly dashboard (PostHog)

1. **Activation funnel**, by `locale` and `app_version`:
   `onboarding_started` → `onboarding_complete` → `consent_given (photos)` → `scan_started` → `scan_completed` → `scan_result_viewed (scan_number = 1)`
2. **Second-scan funnel**: `scan_result_viewed (scan_number = 1)` → `scan_result_viewed (scan_number = 2)` within 14 days.
3. **Retention**: `app_open` returning on day 1, 7 and 30 after `onboarding_complete`.
4. **Monetisation**: `paywall_view` → `purchase_result (outcome = success)`, broken down by `source` and `plan`.
5. **Quality**: `scan_failed` by `kind`; `app_error` count per 1,000 `app_open`; median `ms` on `scan_completed`; share of scans with `on_device = true`.
6. **Cost**: from Supabase, `select kind, count(*), sum(cost_usd) from usage_events where created_at > now() - interval '7 days' group by kind;`. Divide by new users from the activation funnel to get AI cost per activated user.
7. **Acquisition**: Play Console installs by UTM source, against `onboarding_complete` and paying users by week.

Scorecard decision rules are in the playbook, section 12. Set exact targets only after 30 to 60 days of real data.
