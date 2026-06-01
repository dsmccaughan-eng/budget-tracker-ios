# Windows-friendly pre-ship checks (no Mac required for these steps).
# On Mac/Codemagic, also run: bash scripts/run-unit-tests.sh
param(
  [switch]$SkipLineLimits
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Write-Host "=== Budget Tracker pre-ship gate ===" -ForegroundColor Cyan

if (-not $SkipLineLimits) {
  Write-Host "`n[1/4] Swift file line limits..." -ForegroundColor Yellow
  & powershell -File (Join-Path $PSScriptRoot "check-file-line-limits.ps1")
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
  Write-Host "`n[1/4] Line limits skipped." -ForegroundColor DarkGray
}

Write-Host "`n[2/4] Plaid OAuth pages (required for Robinhood / OAuth banks):" -ForegroundColor Yellow
Write-Host "  powershell -File scripts/verify-plaid-oauth-pages.ps1"
Write-Host "  (fix 404s before expecting OAuth link to return to the app)"

Write-Host "`n[3/4] UI canvas preview (required before TestFlight):" -ForegroundColor Yellow
Write-Host "  Open canvases/budget-tracker-preview.canvas.tsx in Cursor (see AI_PROJECT_INSTRUCTIONS.txt §2c)"
Write-Host "  Confirm canvas matches current UI; user must review before upload"

Write-Host "`n[4/4] Mac-only steps (run before TestFlight):" -ForegroundColor Yellow
Write-Host "  xcodegen generate"
Write-Host "  xcodebuild -resolvePackageDependencies -project BudgetTracker.xcodeproj -scheme BudgetTracker"
Write-Host "  bash scripts/verify-supabase-package.sh"
Write-Host "  bash scripts/run-unit-tests.sh"
Write-Host "  Review crashes: docs/TDD_AND_CRASHES.md (Xcode Organizer)"
Write-Host "`nPre-ship gate (Windows checks) passed." -ForegroundColor Green
