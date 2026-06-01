# Reads Config/SECRETS.local.md and connects Supabase CLI (login + link + optional deploy).
# One-time: add SUPABASE_ACCESS_TOKEN from https://supabase.com/dashboard/account/tokens
param(
    [switch]$Deploy,
    [switch]$TestSandbox,
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location $ProjectRoot

function Get-SecretsMap {
    $path = Join-Path $ProjectRoot "Config\SECRETS.local.md"
    if (-not (Test-Path $path)) {
        throw "Missing Config/SECRETS.local.md - copy from Config/SECRETS.local.md.example"
    }
    $map = @{}
    Get-Content $path | ForEach-Object {
        if ($_ -match '^\s*([A-Z0-9_]+)=(.*)$') {
            $map[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $map
}

$secrets = Get-SecretsMap
$pat = $secrets["SUPABASE_ACCESS_TOKEN"]
$ref = $secrets["SUPABASE_PROJECT_REF"]
$url = $secrets["SUPABASE_URL"]

if (-not $pat) {
    Write-Host @"

Cannot auto-connect yet - SUPABASE_ACCESS_TOKEN is missing.

Do this once (takes ~2 minutes):
1. Open https://supabase.com/dashboard/account/tokens
2. Create token named budget-tracker-cli
3. Add to Config/SECRETS.local.md:
   SUPABASE_ACCESS_TOKEN=sbp_...

Then re-run: .\scripts\supabase-auto-connect.ps1 -Deploy

"@
    exit 1
}

if (-not $ref) { throw "SUPABASE_PROJECT_REF missing in SECRETS.local.md" }
if (-not $url) { throw "SUPABASE_URL missing in SECRETS.local.md" }

Write-Host "==> Checking project URL resolves: $url"
try {
    $null = Resolve-DnsName ([Uri]$url).Host -ErrorAction Stop
} catch {
    Write-Host @"

Project URL does not resolve: $url

The Supabase project may not exist yet. Create it in the dashboard:
https://supabase.com/dashboard/new/$ref

Or update SUPABASE_PROJECT_REF / SUPABASE_URL in SECRETS.local.md if the ref changed.

"@
    exit 1
}

Write-Host "==> Logging in to Supabase CLI"
$env:SUPABASE_ACCESS_TOKEN = $pat
supabase login --token $pat | Out-Host

Write-Host "==> Linking project $ref"
supabase link --project-ref $ref | Out-Host

if ($Deploy) {
    Write-Host "==> Deploying backend"
    & (Join-Path $ProjectRoot "scripts\deploy-backend.ps1")
}

if ($TestSandbox) {
    Write-Host "==> Running Plaid Sandbox smoke test"
    $env:SUPABASE_URL = $url
    $env:SUPABASE_ANON_KEY = $secrets["SUPABASE_ANON_KEY"]
    $env:PLAID_CLIENT_ID = $secrets["PLAID_CLIENT_ID"]
    $env:PLAID_SECRET = $secrets["PLAID_SANDBOX_SECRET"]
    & (Join-Path $ProjectRoot "scripts\test-plaid-sandbox.ps1")
}

Write-Host "Supabase auto-connect complete."
