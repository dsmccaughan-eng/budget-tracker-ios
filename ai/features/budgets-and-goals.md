# Feature: Budgets and goals

**Canonical rules:** `AI_PROJECT_INSTRUCTIONS.txt` → Budgets and goals; tabs IA

## Behavior

- **Budgets tab:** Donut chart (spending or planned allocation) + category rows; add via toolbar sheet
- **Dashboard:** Pie preview when budgets exist; **Set up budgets** opens add-budget sheet (not nested navigation)
- **Bills:** Fixed-expense budgets → `BillsListView` (calendar strip + dated list); linked from Dashboard and Budgets tab
- **Transactions:** Grouped by month via `TransactionMonthGrouping`
- Budget math and alerts are deterministic (`BudgetMath`, `BudgetAlertEngine`)
- **Typical by now:** overall wheel and category rows show average spend through this day-of-month across the prior 6 months (skip months with no data; current month excluded)
- **Budget alerts** only for discretionary categories: Groceries, Dining & Bars, Shopping, Entertainment, Transport (still skip fixed / fixed-bill). Fire when spend is above typical-by-now, and when over the budget limit (not at 80% of the limit)
- Debt payoff (avalanche/snowball) stays client-side — no third-party debt payloads
- Tabs: Dashboard, Transactions, Budgets, Goals, Insights

## Code map

| Area | Path |
|------|------|
| Budget store/math | `BudgetTracker/Backend/Finance/BudgetStore.swift`, `BudgetMath.swift`, `BudgetSpendIndex.swift`, `BudgetProgress.swift` |
| Budget alerts | `BudgetTracker/Backend/Finance/BudgetAlertEngine.swift` |
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
