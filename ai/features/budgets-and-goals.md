# Feature: Budgets and goals

**Canonical rules:** `AI_PROJECT_INSTRUCTIONS.txt` → Budgets and goals; tabs IA

## Behavior

- **Budgets tab:** Donut chart (spending or planned allocation) + category rows; add via toolbar sheet
- **Dashboard:** Pie preview when budgets exist; **Set up budgets** opens add-budget sheet (not nested navigation)
- **Bills:** Fixed-expense budgets → `BillsListView` (calendar strip + dated list); linked from Dashboard and Budgets tab
- **Transactions:** Grouped by month via `TransactionMonthGrouping`
- Budget math and alerts are deterministic (`BudgetMath`, `BudgetAlertEngine`)
- Debt payoff (avalanche/snowball) stays client-side — no third-party debt payloads
- Tabs: Dashboard, Transactions, Budgets, Goals, Insights

## Code map

| Area | Path |
|------|------|
| Budget store/math | `BudgetTracker/Backend/Finance/BudgetStore.swift`, `BudgetMath.swift` |
| Goals | `GoalsStore.swift`, `GoalsMath.swift` |
| Cash flow | `CashFlowEngine.swift` |
| Cloud extensions | `Backend/Cloud/SupabaseService+Finance.swift`, `+Goals.swift` |
| UI | `BudgetTracker/Views/Budgets/`, `Views/Bills/BillsListView.swift`, `Views/Goals/` |
| Bills (fixed budgets) | `Backend/Finance/BillsEngine.swift` |
| Month-grouped transactions | `Backend/Finance/TransactionMonthGrouping.swift` |

## Tests

`BudgetTrackerTests/Backend/Finance/` — threshold changes require `LaunchReadinessTests` update first.

## Do not

- Send debt balances to Gemini or external analytics
- Change alert thresholds without tests
