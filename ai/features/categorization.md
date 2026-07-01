# Feature: Categorization

**Canonical rules:** `AI_PROJECT_INSTRUCTIONS.txt` → Categorization priority (locked)

## Behavior

Priority: `merchant_rules` → user-similar history → housing heuristics → transfer heuristics → `merchant_db` → Gemini → Plaid category.  
17 fixed categories — validate AI JSON before persist.  
User category edits must not be wiped on sync (`category_source` `user` or `merchant_rule` always preserved).

## Code map

| Area | Path |
|------|------|
| Engine | `BudgetTracker/Backend/Finance/CategorizationEngine.swift` |
| Gemini | `BudgetTracker/Backend/AI/GeminiService.swift` |
| Transactions | `BudgetTracker/Backend/Finance/TransactionStore.swift` |
| Merchant rules UI | Settings / Profile path (see `Views/`) |

## Go-bys

- [`docs/ai/go-bys/categorization-and-gemini.md`](../../docs/ai/go-bys/categorization-and-gemini.md)
- Enum list: `docs/PROJECT_BRIEF.md`

## Tests

`BudgetTrackerTests/Backend/Finance/` — add tests before changing priority or validation.
