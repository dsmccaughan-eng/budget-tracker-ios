# Budget Tracker — writing guide (for agents)

Canonical product/security rules stay in [`AI_PROJECT_INSTRUCTIONS.txt`](../../AI_PROJECT_INSTRUCTIONS.txt). This file is **how to implement** consistently.

**Which doc when (full map):** [`../../ai/DOCUMENTATION_MAP.md`](../../ai/DOCUMENTATION_MAP.md)

## Repo root

Windows: `C:\Users\dsmcc\Projects\Users\m1\Desktop\BudgetTracker`

## Commands

| Task | Command |
|------|---------|
| Line limit check | `powershell -File scripts/check-file-line-limits.ps1` |
| Pre-ship gate | `powershell -File scripts/pre-ship-gate.ps1` |
| Supabase package verify (Mac/CI) | `bash scripts/verify-supabase-package.sh` |
| Unit tests (Mac/CI) | `bash scripts/run-unit-tests.sh` |
| Link Supabase project | `.\scripts\supabase-auto-connect.ps1` |
| Deploy Edge Functions | `.\scripts\deploy-backend.ps1` |
| Plaid sandbox smoke | `.\scripts\test-plaid-sandbox.ps1` |
| Plaid production switch | `.\scripts\switch-plaid-production.ps1` (when approved) |
| Regenerate Xcode project (Mac) | `xcodegen generate` |
| Codemagic build | `node scripts/trigger-codemagic-build.mjs` |
| Sync shared CI from Desktop | `..\ios-build\sync-to-repos.ps1` |

## Backend layout (do not recreate `Services/`)

```
BudgetTracker/Backend/
  AI/          Gemini, normalizers
  Auth/        AuthStore, OTP bridge
  Cloud/       SupabaseService (+Finance, +Goals)
  Core/        APIKeys, SupabaseConfig, client factory
  Finance/     stores, BudgetMath, CategorizationEngine, goals, cash flow
  Plaid/       LinkKit bridge only — no secret API calls
BudgetTracker/Models/
BudgetTracker/Views/     SwiftUI by feature tab
supabase/functions/    Deno Edge Functions
supabase/migrations/
```

## TDD (required for pure logic)

1. Add/update tests in `BudgetTrackerTests/Backend/<domain>/` **first**
2. Implement under `BudgetTracker/Backend/` until green
3. UI in `Views/` — extract logic to `Backend/Finance/` when testable
4. Threshold changes → update `LaunchReadinessTests` first

## File size

- Target ≤ 400 lines per Swift file; hard stop 500
- Run `check-file-line-limits.ps1` before large merges

## Naming

- Descriptive file names by domain (`BudgetStore.swift`, not `Store2.swift`)
- Split oversized stores by responsibility (see Optimized `WorkoutStore+*.swift` go-by)

## Security (non-negotiable)

- Plaid: iOS → Edge Function → Plaid only
- No `access_token`, `client_secret`, or full account numbers on device
- Face ID / Touch ID before any financial screen
- Supabase project ref: `dldbcbituquxedlkeefu` (not Optimized’s project)

## Documentation duties

| Event | Action |
|-------|--------|
| Non-trivial bug fix | Append `LESSONS_LEARNED.md` |
| Product/behavior decision | One line in `AI_PROJECT_INSTRUCTIONS.txt` **Update Log** |
| New repeatable pattern | Add or extend a file in `docs/ai/go-bys/` |

Never paste secrets into markdown tracked in git.
