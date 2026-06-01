# One-time Budget Tracker TestFlight bootstrap (Windows).
# Run from BudgetTracker: powershell -File scripts/setup-testflight.ps1
param(
  [string]$GithubRepo = "https://github.com/dsmccaughan-eng/budget-tracker-ios.git",
  [string]$AscAppId = "",
  [string]$CodemagicAppId = "",
  [string]$CodemagicGroupId = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $RepoRoot

Write-Host "=== 1) Sync shared CI from ios-build ==="
Set-Location (Split-Path $RepoRoot -Parent)
.\ios-build\sync-to-repos.ps1
Set-Location $RepoRoot

Write-Host "`n=== 2) Signing token (Codemagic) ==="
New-Item -ItemType Directory -Force -Path signing | Out-Null
$cmSrc = Join-Path $RepoRoot "..\Optimized\signing\cm_api_token.txt"
if (Test-Path $cmSrc) {
  Copy-Item $cmSrc signing\cm_api_token.txt -Force
  Write-Host "Copied cm_api_token.txt from Optimized"
} else {
  Write-Host "Add signing/cm_api_token.txt (same token as Optimized)"
}

Write-Host "`n=== 3) App Store Connect (manual — API key cannot create apps) ==="
Write-Host @"
  Open https://appstoreconnect.apple.com
  1. Certificates, IDs & Profiles -> Identifiers -> + App ID
     Bundle ID: com.budgettracker.app  Name: Budget Tracker
  2. Apps -> +  New App  (iOS, name Budget Tracker, bundle above, SKU budgettracker-ios)
  3. Profiles -> +  iOS App Store  Name: Budget Tracker Distribution
     App ID: com.budgettracker.app  Cert: Apple Distribution (CHHWVGCKG4)
  Note the numeric App ID from App Information (for APP_STORE_APPLE_ID).
"@

if ($AscAppId) {
  Write-Host "`n=== 4) Download distribution profile ==="
  $env:OPENSSL = "C:\Program Files\Git\usr\bin\openssl.exe"
  Copy-Item "..\Optimized\signing\certs\AuthKey_N99V63R65U.p8" signing\certs\ -Force
  node scripts/download-asc-profiles.mjs
} else {
  Write-Host "`n=== 4) Skip profile download (pass -AscAppId after ASC app exists) ==="
}

Write-Host "`n=== 5) GitHub repo ==="
if (-not (Test-Path .git)) { git init; git branch -M main }
Write-Host "Create private repo: $GithubRepo (empty), then:"
Write-Host "  git remote add origin $GithubRepo"
Write-Host "  git add -A && git commit -m `"Initial Budget Tracker iOS`" && git push -u origin main"

Write-Host "`n=== 6) Codemagic ==="
Write-Host @"
  https://codemagic.io/apps -> Add application -> GitHub -> budget-tracker-ios
  Reconnect GitHub if prepare step is slow.
  Create variable group: budgettracker_secrets
  Copy APP_STORE_CONNECT_* from optimized_secrets (same team).
  Add: GEMINI_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY from Config/SECRETS.local.md
  Upload signing:
    `$env:CM_P12_PATH = path to distribution .p12 (same as Optimized)
    `$env:CM_P12_PASSWORD = ...
    node scripts/upload-codemagic-signing-secrets.mjs
"@

if ($CodemagicAppId -and $CodemagicGroupId) {
  Write-Host "`nUpdating ios-app.config.json..."
  $cfg = Get-Content ios-app.config.json -Raw | ConvertFrom-Json
  $cfg.codemagic.appId = $CodemagicAppId
  $cfg.codemagic.groupId = $CodemagicGroupId
  if ($AscAppId) { $cfg.ascAppId = $AscAppId }
  $cfg | ConvertTo-Json -Depth 6 | Set-Content ios-app.config.json
  Set-Location (Split-Path $RepoRoot -Parent)
  .\ios-build\sync-to-repos.ps1
  Set-Location $RepoRoot
}

Write-Host "`n=== 7) Trigger build ==="
Write-Host "  node scripts/validate-codemagic-prereqs.mjs"
Write-Host "  node scripts/trigger-codemagic-build.mjs"
