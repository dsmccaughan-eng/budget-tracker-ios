# AI documentation map — Budget Tracker

**Parent (workspace):** `../ai/DOCUMENTATION_MAP.md` (cross-app + shared Cursor table)

---

## Read order (this repo)

1. `AGENTS.md`
2. `AI_PROJECT_INSTRUCTIONS.txt` — **canonical rules** (product, security, release)
3. `LESSONS_LEARNED.md` — **bugs only** (append after fixes)
4. `docs/PROJECT_BRIEF.md` — full spec (models, phases)
5. `docs/ai/writing-guide.md` — **how to build** (commands, TDD, layout)
6. `ai/features/<area>.md` — when editing that feature
7. `docs/ai/go-bys/<topic>.md` — when copying an existing pattern
8. `Config/SECRETS.local.md` — credentials (gitignored)

---

## Feature docs — when to apply

| File | Apply when you touch |
|------|----------------------|
| `ai/features/auth-and-privacy.md` | `Views/Auth/`, `Backend/Auth/`, App lock (`AppLockStore`), OTP functions |
| `ai/features/plaid-and-sync.md` | `Views/Plaid/`, `Backend/Plaid/`, `TransactionStore`, `supabase/functions/plaid-*` |
| `ai/features/categorization.md` | `CategorizationEngine`, `GeminiService`, merchant rules, category UI |
| `ai/features/budgets-and-goals.md` | `BudgetStore`, `GoalsStore`, `BudgetMath`, Budgets/Goals views |
| `ai/features/insights-and-dashboard.md` | `DashboardView`, `InsightsViews`, `SmartFeaturesStore` |

---

## Go-bys — when to apply

| File | Apply when |
|------|------------|
| `docs/ai/go-bys/api-keys-and-supabase-client.md` | `Backend/Core/`, `AuthStore`, Supabase SPM version |
| `docs/ai/go-bys/plaid-edge-functions.md` | New/changed Plaid Edge Function or Link flow |
| `docs/ai/go-bys/categorization-and-gemini.md` | AI categorization or merchant priority |
| `docs/ai/go-bys/release-and-codemagic.md` | TestFlight/Codemagic (links to canonical release section) |
| `../ai/cross-app-go-bys.md` | Shared CI, APIKeys pattern from Optimized |

---

## Cursor rules (this repo)

Open **`BudgetTracker/`** as the Cursor workspace root.

| Rule | Scope |
|------|--------|
| `documentation-map.mdc` | Always — use this file |
| `ai-project-instructions.mdc` | Always — read canonical + lessons |
| `engineering-standards.mdc` | Always — TDD, Plaid security, layout |
| `budgettracker-core.mdc` | Always — finance domain summary |
| `go-by-first.mdc` | Always — search go-bys before new patterns |
| `lessons-learned.mdc` | Always — append bugs to ledger |
| `product-north-star.mdc` | Always — value, security, low friction |
| `critical-clarity-and-pushback.mdc` | Always — ask / push back on risky changes |
| `budgettracker-swift.mdc` | `BudgetTracker/**/*.swift` |
| `budgettracker-supabase.mdc` | `supabase/**/*` |
| `budgettracker-plaid-ios.mdc` | `BudgetTracker/**/Plaid/**/*` |

Full workspace table: `../ai/DOCUMENTATION_MAP.md` §3.

---

## Write routing (Budget Tracker)

| Event | File |
|-------|------|
| Bug fixed | `LESSONS_LEARNED.md` |
| New rule / shipped behavior | `AI_PROJECT_INSTRUCTIONS.txt` → Update Log |
| New script or folder convention | `docs/ai/writing-guide.md` |
| New files in a feature | `ai/features/<area>.md` code map |
| New reusable pattern | `docs/ai/go-bys/` + line in `ai/README.md` |

**Never** commit secrets to any tracked file above.
