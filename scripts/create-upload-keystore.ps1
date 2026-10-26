# Creates the Google Play UPLOAD keystore and android/key.properties.
#
#   powershell -ExecutionPolicy Bypass -File scripts/create-upload-keystore.ps1
#
# BACK UP the .jks file and passwords somewhere safe (password manager +
# offline copy). With Play App Signing, Google holds the real app-signing key,
# so a lost upload key can be reset via Play Console support — but it takes
# days and blocks releases.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$keystoreDir = Join-Path $env:USERPROFILE ".clearskin"
New-Item -ItemType Directory -Force -Path $keystoreDir | Out-Null
$keystore = Join-Path $keystoreDir "clearskin-upload.jks"

if (Test-Path $keystore) {
  Write-Host "Keystore already exists at $keystore — not overwriting." -ForegroundColor Yellow
  exit 1
}

$pass = Read-Host "Choose a strong keystore password (min 8 chars)" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
if ($plain.Length -lt 8) { throw "Password too short" }

$keytool = "keytool"
if ($env:JAVA_HOME) { $keytool = Join-Path $env:JAVA_HOME "bin\keytool.exe" }

& $keytool -genkeypair -v `
  -keystore $keystore `
  -storetype JKS `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias upload `
  -storepass $plain -keypass $plain `
  -dname "CN=ClearSkin AI, OU=Mobile, O=ClearSkin AI, C=US"

$props = @"
storePassword=$plain
keyPassword=$plain
keyAlias=upload
storeFile=$($keystore -replace '\','/')
"@
Set-Content -Path (Join-Path $root "android\key.properties") -Value $props -Encoding ascii
Write-Host "Created $keystore and android/key.properties" -ForegroundColor Green
Write-Host "Back up the keystore and password NOW." -ForegroundColor Yellow
