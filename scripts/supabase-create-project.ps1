# Creates a Supabase project via Management API, updates SECRETS.local.md, then links + deploys.
# Prerequisite: SUPABASE_ACCESS_TOKEN in Config/SECRETS.local.md (NOT your login password).
param(
    [string]$ProjectName = "Budget Tracker",
    [string]$OrganizationSlug = "",
    [switch]$Deploy,
    [switch]$SkipSecretsUpdate,
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location $ProjectRoot

function Get-SecretsMap {
    $path = Join-Path $ProjectRoot "Config\SECRETS.local.md"
    if (-not (Test-Path $path)) {
        throw "Missing Config/SECRETS.local.md"
    }
    $map = @{}
    Get-Content $path | ForEach-Object {
        if ($_ -match '^\s*([A-Z0-9_]+)=(.*)$') {
            $map[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return @{ Path = $path; Map = $map }
}

function Set-SecretValue {
    param([hashtable]$Map, [string]$Path, [string]$Key, [string]$Value)
    $Map[$Key] = $Value
    $lines = Get-Content $Path
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$Key=") {
            $lines[$i] = "$Key=$Value"
            $found = $true
            break
        }
    }
    if (-not $found) {
        $lines += "$Key=$Value"
    }
    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Invoke-SupabaseManagement {
    param(
        [string]$Token,
        [string]$Method,
        [string]$Path,
        [object]$Body = $null
    )
    $headers = @{
        Authorization = "Bearer $Token"
        "Content-Type" = "application/json"
    }
    $uri = "https://api.supabase.com$Path"
    if ($Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body ($Body | ConvertTo-Json -Depth 6)
    }
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
}

$secretsFile = Get-SecretsMap
$secrets = $secretsFile.Map
$pat = $secrets["SUPABASE_ACCESS_TOKEN"]

if (-not $pat) {
    Write-Host @"

I cannot log into the Supabase website for you, but I CAN create the project automatically
once you add a Personal Access Token (this is NOT your Supabase password).

One-time setup (~2 minutes):
1. Sign in at https://supabase.com/dashboard (you do this in your browser)
2. Open https://supabase.com/dashboard/account/tokens
3. Create token: name it budget-tracker-cli
4. Add to Config/SECRETS.local.md:
   SUPABASE_ACCESS_TOKEN=sbp_...

Optional (auto-picks first org if omitted):
   SUPABASE_ORG_SLUG=your-org-slug

Then tell Cursor: "Create the Supabase project" and I will run:
   .\scripts\supabase-create-project.ps1 -Deploy

"@
    exit 1
}

if (-not $OrganizationSlug) {
    $OrganizationSlug = $secrets["SUPABASE_ORG_SLUG"]
}

if (-not $OrganizationSlug) {
    Write-Host "==> Fetching your Supabase organizations"
    $orgs = Invoke-SupabaseManagement -Token $pat -Method GET -Path "/v1/organizations"
    if (-not $orgs -or $orgs.Count -eq 0) {
        throw "No organizations found. Create one at https://supabase.com/dashboard/org"
    }
    $OrganizationSlug = $orgs[0].slug
    Write-Host "Using organization: $OrganizationSlug ($($orgs[0].name))"
}

$dbPassword = $secrets["SUPABASE_DB_PASSWORD"]
if (-not $dbPassword) {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $dbPassword = [Convert]::ToBase64String($bytes) -replace '[^a-zA-Z0-9]', 'x'
    if ($dbPassword.Length -lt 16) { $dbPassword = "$dbPassword`ExtraSecure1" }
}

Write-Host "==> Creating Supabase project '$ProjectName'"
$createBody = @{
    name              = $ProjectName
    organization_slug = $OrganizationSlug
    db_pass           = $dbPassword
    region_selection  = @{ type = "smartGroup"; code = "americas" }
}
$created = Invoke-SupabaseManagement -Token $pat -Method POST -Path "/v1/projects" -Body $createBody

$ref = $created.ref
if (-not $ref) { throw "Create project response missing ref" }
Write-Host "Created project ref: $ref"

Write-Host "==> Waiting for project to become healthy (may take several minutes)"
$deadline = (Get-Date).AddMinutes(15)
do {
    Start-Sleep -Seconds 15
    try {
        $health = Invoke-SupabaseManagement -Token $pat -Method GET -Path "/v1/projects/$ref/health"
        $status = ($health | ConvertTo-Json -Compress)
        Write-Host "  health: $status"
        if ($health -is [array]) {
            $unhealthy = $health | Where-Object { $_.status -ne "ACTIVE_HEALTHY" -and $_.healthy -ne $true }
            if (-not $unhealthy -or $unhealthy.Count -eq 0) { break }
        }
    } catch {
        Write-Host "  still provisioning..."
    }
} while ((Get-Date) -lt $deadline)

Write-Host "==> Fetching API keys"
$keys = Invoke-SupabaseManagement -Token $pat -Method GET -Path "/v1/projects/$ref/api-keys"
$anon = ($keys | Where-Object { $_.name -eq "anon" -or $_.name -eq "anon key" } | Select-Object -First 1).api_key
$service = ($keys | Where-Object { $_.name -match "service" } | Select-Object -First 1).api_key
if (-not $anon) {
    $anon = ($keys | Where-Object { $_.tags -contains "anon" } | Select-Object -First 1).api_key
}
if (-not $service) {
    $service = ($keys | Where-Object { $_.tags -contains "service_role" } | Select-Object -First 1).api_key
}

$url = "https://$ref.supabase.co"

if (-not $SkipSecretsUpdate) {
    Write-Host "==> Updating Config/SECRETS.local.md"
    Set-SecretValue -Map $secrets -Path $secretsFile.Path -Key "SUPABASE_PROJECT_REF" -Value $ref
    Set-SecretValue -Map $secrets -Path $secretsFile.Path -Key "SUPABASE_URL" -Value $url
    if ($anon) { Set-SecretValue -Map $secrets -Path $secretsFile.Path -Key "SUPABASE_ANON_KEY" -Value $anon }
    if ($service) { Set-SecretValue -Map $secrets -Path $secretsFile.Path -Key "SUPABASE_SERVICE_ROLE_KEY" -Value $service }
    Set-SecretValue -Map $secrets -Path $secretsFile.Path -Key "SUPABASE_ORG_SLUG" -Value $OrganizationSlug
    Set-SecretValue -Map $secrets -Path $secretsFile.Path -Key "SUPABASE_DB_PASSWORD" -Value $dbPassword
}

Write-Host @"

Project ready:
  ref: $ref
  url: $url

"@

Write-Host "==> Linking CLI"
if ($Deploy) {
    & (Join-Path $ProjectRoot "scripts\supabase-auto-connect.ps1") -Deploy -TestSandbox
} else {
    & (Join-Path $ProjectRoot "scripts\supabase-auto-connect.ps1")
}

Write-Host "Done. Update Config/LocalAPIKeys.plist with the new Supabase URL and anon key for Simulator."
