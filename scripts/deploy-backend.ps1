# Deploy backend from Windows after `supabase login --token <PAT>`.
param(
  [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)

Set-Location $ProjectRoot

Write-Host "==> Pushing database migrations"
supabase db push

Write-Host "==> Setting Edge Function secrets"
$secrets = Get-Content "Config\SECRETS.local.md" -Raw
function Get-SecretValue([string]$Name) {
  if ($secrets -match "(?m)^$Name=(.+)$") { return $Matches[1].Trim() }
  return $null
}

$plaidClientId = Get-SecretValue "PLAID_CLIENT_ID"
$plaidEnv = Get-SecretValue "PLAID_ENV"
if (-not $plaidEnv) { $plaidEnv = "sandbox" }

if ($plaidEnv -eq "production") {
  $plaidSecret = Get-SecretValue "PLAID_PRODUCTION_SECRET"
  if (-not $plaidSecret) {
    throw "PLAID_ENV=production but PLAID_PRODUCTION_SECRET is missing. Copy Production secret from Plaid Dashboard -> Developers -> Keys."
  }
} else {
  $plaidEnv = "sandbox"
  $plaidSecret = Get-SecretValue "PLAID_SANDBOX_SECRET"
}

$geminiKey = Get-SecretValue "GEMINI_API_KEY"
$projectRef = Get-SecretValue "SUPABASE_PROJECT_REF"
if (-not $projectRef) { $projectRef = "dldbcbituquxedlkeefu" }

if (-not $plaidClientId -or -not $plaidSecret) {
  throw "Missing PLAID_CLIENT_ID or Plaid secret for environment '$plaidEnv' in Config/SECRETS.local.md"
}

Write-Host "==> Plaid environment: $plaidEnv"

$webhookUrl = "https://$projectRef.supabase.co/functions/v1/plaid-webhook"
$redirectUri = Get-SecretValue "PLAID_REDIRECT_URI"

supabase secrets set `
  PLAID_CLIENT_ID=$plaidClientId `
  PLAID_SECRET=$plaidSecret `
  PLAID_ENV=$plaidEnv `
  PLAID_WEBHOOK_URL=$webhookUrl `
  GEMINI_API_KEY=$geminiKey

if ($redirectUri) {
  supabase secrets set PLAID_REDIRECT_URI=$redirectUri
} elseif ($plaidEnv -eq "production") {
  Write-Warning "PLAID_REDIRECT_URI missing — OAuth banks (Robinhood, Chase) will fail until set in SECRETS.local.md and redeployed."
}

Write-Host "==> Deploying Edge Functions"
$functions = @(
  "send-auth-email",
  "request-login-otp",
  "plaid-create-link-token",
  "plaid-create-update-link-token",
  "plaid-exchange-token",
  "plaid-get-accounts",
  "plaid-sync-transactions",
  "plaid-remove-item",
  "plaid-webhook"
)
foreach ($fn in $functions) {
  if ($fn -eq "plaid-webhook" -or $fn -eq "request-login-otp" -or $fn -eq "send-auth-email") {
    supabase functions deploy $fn --no-verify-jwt
  } else {
    supabase functions deploy $fn
  }
}

Write-Host "Deploy complete."
Write-Host "Webhook URL: $webhookUrl"
Write-Host "Run scripts/test-plaid-sandbox.ps1 to verify user-facing functions."
