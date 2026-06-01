# Switch Supabase Edge Functions to Plaid Production (Trial) after Dashboard approval.
# 1. Paste PLAID_PRODUCTION_SECRET in Config/SECRETS.local.md (Dashboard -> Keys -> Production)
# 2. Run: powershell -File scripts/switch-plaid-production.ps1

param(
  [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)

Set-Location $ProjectRoot

$secretsPath = Join-Path $ProjectRoot "Config\SECRETS.local.md"
$secrets = Get-Content $secretsPath -Raw

if ($secrets -notmatch "(?m)^PLAID_PRODUCTION_SECRET=(.+)$" -or $Matches[1].Trim().Length -lt 8) {
  throw @"
PLAID_PRODUCTION_SECRET is missing in Config/SECRETS.local.md.

Steps:
  1. Open https://dashboard.plaid.com/developers/keys
  2. Under Production, click Show -> Copy secret
  3. Set PLAID_PRODUCTION_SECRET=<paste> in Config/SECRETS.local.md
  4. Re-run this script
"@
}

if ($secrets -match "(?m)^PLAID_ENV=.+$") {
  $secrets = $secrets -replace "(?m)^PLAID_ENV=.+$", "PLAID_ENV=production"
} else {
  $secrets += "`nPLAID_ENV=production`n"
}

Set-Content -Path $secretsPath -Value $secrets -NoNewline
Write-Host "Set PLAID_ENV=production in Config/SECRETS.local.md"
Write-Host "Deploying backend with Production Plaid..."
powershell -File (Join-Path $ProjectRoot "scripts\deploy-backend.ps1")
