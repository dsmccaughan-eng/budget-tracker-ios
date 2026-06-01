# End-to-end Plaid Sandbox smoke test for deployed Edge Functions.
param(
  [string]$SupabaseUrl = $env:SUPABASE_URL,
  [string]$AnonKey = $env:SUPABASE_ANON_KEY,
  [string]$TestEmail = "budget-tracker-test@example.com",
  [string]$TestPassword = "BudgetTrackerTest123!"
)

$ErrorActionPreference = "Stop"

if (-not $SupabaseUrl -or -not $AnonKey) {
  throw "Set SUPABASE_URL and SUPABASE_ANON_KEY (or pass -SupabaseUrl / -AnonKey)."
}

function Invoke-Supabase {
  param(
    [string]$Method,
    [string]$Path,
    [hashtable]$Body = $null,
    [string]$Token = $null
  )

  $headers = @{
    apikey = $AnonKey
    "Content-Type" = "application/json"
  }
  if ($Token) { $headers.Authorization = "Bearer $Token" }

  $uri = "$SupabaseUrl$Path"
  if ($Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body ($Body | ConvertTo-Json)
  }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
}

Write-Host "==> Sign up / sign in test user"
try {
  $signUp = Invoke-Supabase -Method POST -Path "/auth/v1/signup" -Body @{
    email = $TestEmail
    password = $TestPassword
  }
} catch {
  $signUp = Invoke-Supabase -Method POST -Path "/auth/v1/token?grant_type=password" -Body @{
    email = $TestEmail
    password = $TestPassword
  }
}

$accessToken = $signUp.access_token
if (-not $accessToken) { throw "Could not obtain access token" }

Write-Host "==> plaid-create-link-token"
$link = Invoke-Supabase -Method POST -Path "/functions/v1/plaid-create-link-token" -Body @{} -Token $accessToken
if (-not $link.link_token) { throw "Missing link_token" }
Write-Host "link_token OK"

Write-Host "==> Sandbox public token (Plaid sandbox only)"
$plaidClientId = $env:PLAID_CLIENT_ID
$plaidSecret = $env:PLAID_SECRET
if (-not $plaidClientId -or -not $plaidSecret) {
  Write-Warning "Skip exchange/sync - set PLAID_CLIENT_ID and PLAID_SECRET to complete full test."
  exit 0
}

$sandbox = Invoke-RestMethod -Method POST -Uri "https://sandbox.plaid.com/sandbox/public_token/create" -Headers @{
  "Content-Type" = "application/json"
} -Body (@{
  client_id = $plaidClientId
  secret = $plaidSecret
  institution_id = "ins_109508"
  initial_products = @("transactions")
} | ConvertTo-Json)

Write-Host "==> plaid-exchange-token"
$exchange = Invoke-Supabase -Method POST -Path "/functions/v1/plaid-exchange-token" -Body @{
  public_token = $sandbox.public_token
  institution_name = "First Platypus Bank"
} -Token $accessToken
Write-Host "item_id: $($exchange.item_id)"

Write-Host "==> plaid-get-accounts"
$accounts = Invoke-Supabase -Method POST -Path "/functions/v1/plaid-get-accounts" -Body @{} -Token $accessToken
Write-Host "accounts: $($accounts.accounts.Count)"

Write-Host "==> plaid-sync-transactions"
$sync = Invoke-Supabase -Method POST -Path "/functions/v1/plaid-sync-transactions" -Body @{} -Token $accessToken
Write-Host "synced: $($sync.synced), categorized: $($sync.categorized)"

Write-Host "All Edge Function smoke tests passed."
