# Verify GitHub Pages files required for Plaid OAuth (Robinhood, Chase, etc.).
param(
  [string]$BaseUrl = "https://dsmccaughan-eng.github.io/budget-tracker-ios"
)

$ErrorActionPreference = "Stop"

$paths = @(
  "/.well-known/apple-app-site-association",
  "/plaid/oauth.html"
)

Write-Host "=== Plaid OAuth page check ===" -ForegroundColor Cyan
Write-Host "Base: $BaseUrl`n"

$failed = 0
foreach ($path in $paths) {
  $url = "$BaseUrl$path"
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -MaximumRedirection 0
    Write-Host "[OK] $url ($($response.StatusCode))" -ForegroundColor Green
    if ($path -like "*apple-app-site-association*") {
      $json = $response.Content | ConvertFrom-Json
      $appIds = $json.applinks.details[0].appIDs
      Write-Host "     appIDs: $($appIds -join ', ')"
    }
  } catch {
    $status = $_.Exception.Response.StatusCode.value__
    if (-not $status) { $status = "error" }
    Write-Host "[FAIL] $url ($status)" -ForegroundColor Red
    $failed++
  }
}

if ($failed -gt 0) {
  Write-Host "`nFix: enable GitHub Pages on dsmccaughan-eng/budget-tracker-ios" -ForegroundColor Yellow
  Write-Host "  Settings -> Pages -> Deploy from branch main, folder /docs"
  Write-Host "  Push docs/.nojekyll, docs/.well-known/, docs/plaid/oauth.html"
  Write-Host "  See docs/PLAID_OAUTH_SETUP.md"
  exit 1
}

Write-Host "`nOAuth pages look reachable." -ForegroundColor Green
