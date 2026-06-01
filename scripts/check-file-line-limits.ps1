# Reports Swift files over the line budget (default 400 soft / 500 hard).
param(
  [int]$SoftLimit = 400,
  [int]$HardLimit = 500
)

$root = Split-Path $PSScriptRoot -Parent
$overSoft = @()
$overHard = @()

Get-ChildItem -Path (Join-Path $root 'BudgetTracker') -Recurse -Filter '*.swift' |
  ForEach-Object {
    $lines = (Get-Content $_.FullName | Measure-Object -Line).Lines
    $rel = $_.FullName.Replace("$((Resolve-Path $root).Path)\", '').Replace('\', '/')
    if ($lines -gt $HardLimit) { $overHard += [PSCustomObject]@{ Lines = $lines; Path = $rel } }
    elseif ($lines -gt $SoftLimit) { $overSoft += [PSCustomObject]@{ Lines = $lines; Path = $rel } }
  }

Write-Host "Swift files over soft limit ($SoftLimit):"
$overSoft | Sort-Object Lines -Descending | Format-Table -AutoSize
Write-Host "Swift files over hard limit ($HardLimit) - split required:"
$overHard | Sort-Object Lines -Descending | Format-Table -AutoSize
if ($overHard.Count -gt 0) { exit 1 }
exit 0
