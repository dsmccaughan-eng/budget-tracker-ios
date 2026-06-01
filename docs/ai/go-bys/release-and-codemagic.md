# Go-by: Release, TestFlight, Codemagic

Full command chains live in **`AI_PROJECT_INSTRUCTIONS.txt`** (Release / TestFlight section). Do not duplicate or alter archive flags without user approval.

## In-repo

| Topic | File |
|-------|------|
| Codemagic | `docs/CODEMAGIC.md`, `codemagic.yaml` |
| GitHub policy | `docs/GITHUB_POLICY.md` |
| TDD + crashes | `docs/TDD_AND_CRASHES.md` |
| UI canvas before upload | `AI_PROJECT_INSTRUCTIONS.txt` §2c — `canvases/budget-tracker-preview.canvas.tsx` |
| TestFlight setup | `docs/TESTFLIGHT_SETUP.md` |
| Signing example | `pkg.xcconfig.example`, `ExportOptions.plist` (when present) |

## Shared Desktop CI

1. Edit `../ios-build/apps/budgettracker.json` or templates
2. `..\ios-build\sync-to-repos.ps1`
3. Commit in this repo

## Sibling reference

`../Optimized/docs/XCODE_CLOUD_RELEASE.md` — same team (`CHHWVGCKG4`), different bundle ID and profiles.

## Mapping (Optimized → Budget Tracker)

| Optimized | Budget Tracker |
|-----------|----------------|
| `Optimized.xcodeproj` | `BudgetTracker.xcodeproj` |
| scheme `Optimized` | scheme `BudgetTracker` |
| `com.optimizedapp.app` | `com.budgettracker.app` |

Single iOS target (no Watch/Widget).
