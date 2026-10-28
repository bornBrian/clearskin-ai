# Builds the Google Play release bundle, refusing anything unsafe to ship.
#
#   powershell -ExecutionPolicy Bypass -File scripts/build-release.ps1
#
# Checks env/prod.json first (no sample AI, no test ad ids, billing and
# anti-tamper configured), then builds an obfuscated, R8-shrunk AAB. Keep
# build/symbols: it's what de-obfuscates crash reports.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root "env\prod.json"

if (-not (Test-Path $envFile)) {
  Write-Host "Missing env\prod.json. Copy env\example.json and fill it in." -ForegroundColor Red
  exit 1
}
if (-not (Test-Path (Join-Path $root "android\key.properties"))) {
  Write-Host "Missing android\key.properties. Run scripts\create-upload-keystore.ps1." -ForegroundColor Red
  exit 1
}

$config = Get-Content $envFile -Raw | ConvertFrom-Json
$problems = @()
function Need($name) {
  $value = $config.$name
  if ($null -eq $value -or "$value".Trim() -eq "" -or "$value" -match "xxx|XXXX|YOUR-") {
    $script:problems += "$name is empty or still a placeholder"
  }
}

foreach ($key in @(
  "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "GOOGLE_WEB_CLIENT_ID",
  "RC_ANDROID_KEY", "PRIVACY_URL", "TERMS_URL", "SUPPORT_EMAIL",
  "ADMOB_APP_ID", "ADMOB_BANNER_ID", "ADMOB_INTERSTITIAL_ID", "ADMOB_REWARDED_ID",
  "EXPECTED_SIGNING_SHA256"
)) { Need $key }

if ("$($config.AI_DEMO)" -eq "true") { $problems += "AI_DEMO must be false for a store build" }
if ("$($config.PREVIEW_BUILD)" -eq "true") { $problems += "PREVIEW_BUILD must not be set for a store build" }
if (-not "$($config.RC_ANDROID_KEY)".StartsWith("goog_")) {
  $problems += "RC_ANDROID_KEY must be RevenueCat's PUBLIC Google key (goog_...), never the secret key"
}
foreach ($key in @("ADMOB_APP_ID", "ADMOB_BANNER_ID", "ADMOB_INTERSTITIAL_ID", "ADMOB_REWARDED_ID")) {
  if ("$($config.$key)".Contains("3940256099942544")) { $problems += "$key is Google's TEST id" }
}
if ([int]"0$($config.PLAY_INTEGRITY_PROJECT_NUMBER)" -le 0) {
  $problems += "PLAY_INTEGRITY_PROJECT_NUMBER is not set (anti-tamper off)"
}
# Secrets must never be in the app's config.
$raw = Get-Content $envFile -Raw
if ($raw -match "sk-ant-|sk_[A-Za-z0-9]{10,}|service_role|BEGIN PRIVATE KEY") {
  $problems += "env\prod.json contains a SECRET key. Secrets belong only in Supabase secrets."
}

if ($problems.Count -gt 0) {
  Write-Host "Not building:" -ForegroundColor Red
  $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
}

Push-Location $root
try {
  flutter clean
  flutter build appbundle --release `
    --dart-define-from-file=env/prod.json `
    --obfuscate --split-debug-info=build/symbols
  Write-Host ""
  Write-Host "Upload: build\app\outputs\bundle\release\app-release.aab" -ForegroundColor Green
  Write-Host "Keep:   build\symbols (crash de-obfuscation)" -ForegroundColor Green
} finally {
  Pop-Location
}
