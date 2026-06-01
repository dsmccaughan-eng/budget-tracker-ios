# Go-by: Categorization and Gemini JSON

## Priority (locked)

1. `merchant_rules` (user)
2. `merchant_db` (seed)
3. Gemini JSON (validated)
4. Plaid raw category

## In-repo

| Piece | File |
|-------|------|
| Engine | `BudgetTracker/Backend/Finance/CategorizationEngine.swift` |
| Gemini client | `BudgetTracker/Backend/AI/GeminiService.swift` |
| Transactions store | `BudgetTracker/Backend/Finance/TransactionStore.swift` |

## Sibling pattern

Optimized nutrition uses lookup-first then AI — same **shape**: deterministic path wins, AI is optional enhancement.

- `../Optimized/Optimized/Backend/Nutrition/NutritionLookupSelector.swift`
- `../Optimized/Optimized/Backend/AI/GeminiService.swift` (tolerant JSON)

## Rules

- Fixed 17 categories (`docs/PROJECT_BRIEF.md`) — validate before save
- User corrections must survive sync (do not overwrite unless still `Other`)

## Tests

Add cases in `BudgetTrackerTests/Backend/Finance/` before changing priority or enum mapping.
