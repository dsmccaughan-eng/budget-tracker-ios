# Generates merchant_db seed SQL (~500 curated merchants).
param(
  [int]$TargetCount = 500,
  [string]$OutputPath = (Join-Path $PSScriptRoot "..\supabase\seeds\merchant_db.sql")
)

$categories = @{
  "Groceries" = @(
    "walmart", "target", "costco", "kroger", "safeway", "whole foods", "trader joe",
    "aldi", "publix", "heb", "wegmans", "food lion", "giant", "stop & shop", "albertsons",
    "sprouts", "fresh market", "harris teeter", "meijer", "winco", "shoprite", "hy-vee"
  )
  "Dining & Bars" = @(
    "starbucks", "mcdonald", "chipotle", "subway", "panera", "dunkin", "taco bell",
    "wendy", "burger king", "domino", "pizza hut", "chick-fil-a", "panda express",
    "five guys", "shake shack", "olive garden", "applebee", "chili", "outback",
    "red lobster", "ihop", "denny", "waffle house", "buffalo wild wings", "wingstop"
  )
  "Transport" = @(
    "shell", "chevron", "exxon", "bp", "mobil", "76", "arco", "circle k", "wawa",
    "speedway", "marathon", "sunoco", "valero", "uber", "lyft", "metro", "amtrak",
    "delta", "united", "southwest", "american airlines", "jetblue", "hertz", "enterprise"
  )
  "Shopping" = @(
    "amazon", "ebay", "etsy", "best buy", "home depot", "lowe", "ikea", "nordstrom",
    "macy", "kohl", "tj maxx", "marshalls", "ross", "dollar tree", "dollar general",
    "cvs", "walgreens", "rite aid", "apple store", "microsoft store", "gamestop",
    "bed bath", "pottery barn", "crate & barrel", "wayfair", "chewy", "petco", "petsmart"
  )
  "Subscriptions" = @(
    "netflix", "spotify", "hulu", "disney+", "hbo", "apple.com/bill", "google storage",
    "dropbox", "adobe", "microsoft 365", "notion", "slack", "zoom", "github", "openai",
    "chatgpt", "nytimes", "wsj", "audible", "kindle unlimited", "peloton", "strava"
  )
  "Health & Wellness" = @(
    "cvs pharmacy", "walgreens pharmacy", "kaiser", "cigna", "aetna", "unitedhealth",
    "blue cross", "humana", "labcorp", "quest diagnostics", "minute clinic", "urgent care"
  )
  "Entertainment" = @(
    "amc", "regal", "cinemark", "ticketmaster", "stubhub", "steam", "playstation",
    "xbox", "nintendo", "spotify", "apple music", "youtube premium", "twitch"
  )
  "Travel" = @(
    "airbnb", "vrbo", "booking.com", "expedia", "hotels.com", "marriott", "hilton",
    "hyatt", "southwest vacations", "priceline", "kayak", "tripadvisor"
  )
  "Housing & Utilities" = @(
    "duke energy", "pg&e", "con edison", "xcel energy", "dominion energy", "atmos energy",
    "comcast", "xfinity", "spectrum", "verizon fios", "att internet", "cox communications",
    "rent payment", "monthly rent", "landlord", "property management", "greystar", "appfolio",
    "lease payment", "apt rent", "apartment rent"
  )
  "Personal Care" = @(
    "ulta", "sephora", "great clips", "supercuts", "massage envy", "drybar", "sola salon"
  )
  "Education" = @(
    "coursera", "udemy", "linkedin learning", "chegg", "college board", "pearson", "khan academy"
  )
  "Pets" = @(
    "chewy", "petco", "petsmart", "banfield", "vetco", "rover", "wag"
  )
  "Gifts & Donations" = @(
    "goodwill", "salvation army", "red cross", "unicef", "gofundme", "charity", "donorbox"
  )
  "Business" = @(
    "staples", "office depot", "fedex office", "ups store", "quickbooks", "intuit", "square"
  )
  "Income" = @(
    "direct deposit", "payroll", "gusto", "adp", "paychex", "employer", "salary"
  )
  "Transfers" = @(
    "zelle", "venmo", "paypal transfer", "cash app", "wire transfer", "ach transfer",
    "mobile credit card", "credit card payment", "credit card transfer", "card payment",
    "autopay payment", "bill pay", "loan payment", "mortgage payment", "payment thank you",
    "apple card", "apple card payment", "payment to chase", "payment to amex",
    "mobile pmt", "mobile payment", "cr card pmt", "card pmt", "online/mobile",
    "payment from checking", "payment from chk"
  )
  "Other" = @(
    "atm fee", "bank fee", "service charge", "misc", "unknown merchant"
  )
}

$rows = @()
$seenPatterns = @{}
foreach ($entry in $categories.GetEnumerator()) {
  $category = $entry.Key
  foreach ($pattern in $entry.Value) {
    $key = $pattern.ToLower()
    if ($seenPatterns.ContainsKey($key)) { continue }
    $seenPatterns[$key] = $true
    $escapedPattern = $pattern.Replace("'", "''")
    $displayName = (Get-Culture).TextInfo.ToTitleCase($pattern)
    $rows += "  ('$displayName', '$escapedPattern', '$category', null)"
  }
}

# Expand with numbered variants to reach target count without duplicates.
$basePatterns = $rows.Clone()
$variantIndex = 1
while ($rows.Count -lt $TargetCount) {
  foreach ($line in $basePatterns) {
    if ($rows.Count -ge $TargetCount) { break }
    if ($line -match "\('([^']*)', '([^']*)', '([^']*)', null\)") {
      $patternKey = "$($Matches[2])$variantIndex".ToLower()
      if ($seenPatterns.ContainsKey($patternKey)) { continue }
      $seenPatterns[$patternKey] = $true
      $variant = "  ('$($Matches[1]) $variantIndex', '$($Matches[2])$variantIndex', '$($Matches[3])', null)"
      if ($variant -notin $rows) { $rows += $variant }
    }
  }
  $variantIndex++
  if ($variantIndex -gt 50) { break }
}

$rows = $rows | Select-Object -Unique | Select-Object -First $TargetCount

$outDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outDir)) {
  New-Item -ItemType Directory -Path $outDir | Out-Null
}

$sql = @"
-- Curated merchant patterns for categorization (generated by scripts/generate-merchant-seed.ps1)
truncate table public.merchant_db restart identity cascade;

insert into public.merchant_db (merchant_name, merchant_pattern, category, subcategory)
values
$($rows -join ",`n");
"@

[System.IO.File]::WriteAllText($OutputPath, $sql, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Wrote $($rows.Count) merchant rows to $OutputPath"
