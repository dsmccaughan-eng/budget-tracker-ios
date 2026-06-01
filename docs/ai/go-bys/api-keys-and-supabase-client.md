# Go-by: API keys and Supabase client

## In-repo (primary)

| Concern | File |
|---------|------|
| Key resolution order | `BudgetTracker/Backend/Core/APIKeys.swift` |
| URL + anon defaults | `BudgetTracker/Backend/Core/SupabaseConfig.swift` |
| Lazy client (no init crash) | `BudgetTracker/Backend/Core/SupabaseClientFactory.swift` |
| Session + bootstrap | `BudgetTracker/Backend/Auth/AuthStore.swift` |
| Cloud API surface | `BudgetTracker/Backend/Cloud/SupabaseService.swift` |

## Sibling pattern (adapt, do not copy project ref)

`../Optimized/Optimized/Backend/Core/APIKeys.swift` — Profile override model differs; Budget Tracker embeds Supabase anon in Release.

## Tests

- `BudgetTrackerTests/Backend/Core/APIKeysTests.swift`
- `BudgetTrackerTests/Backend/Core/SupabaseConfigTests.swift`
- `BudgetTrackerTests/Backend/Auth/AuthStoreTests.swift`

## External

- [supabase-swift #960](https://github.com/supabase/supabase-swift/issues/960) — pin **≥ 2.44.0** for iOS 26
