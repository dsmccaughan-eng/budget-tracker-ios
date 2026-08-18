# Feature: Dashboard and insights

**Canonical rules:** `AI_PROJECT_INSTRUCTIONS.txt` → Product North Star (Gemini for insights with fallbacks)

## Behavior

- Dashboard is primary overview tab
- **Unreviewed transactions:** dashboard row opens a review sheet (not a dropdown). Category save returns to that list and keeps scroll; Confirm all stays in the sheet
- **Net Worth charts** (overall, Cash / Investments / Debts, and each account): Daily or Monthly (1st of month) interval toggle
- Dashboard loads budgets on first unlock (does not wait for the Budgets tab or Plaid sync)
- Investment history is an **accumulation curve**: dated contributions/withdrawals/transfers, bank “Investments” outflows inferred when needed, market P/L between snapshots, today pinned to live value; internal buys/sells are ignored
- Insights may use Gemini when it materially helps; keep deterministic fallbacks
- Smart features must not override user categorization rules

## Code map

| Area | Path |
|------|------|
| Dashboard UI | `BudgetTracker/Views/Dashboard/DashboardView.swift`, `UnreviewedTransactionsView.swift` |
| Transaction review | `BudgetTracker/Backend/Finance/TransactionReviewEngine.swift`, `TransactionReviewStore.swift` |
| Net Worth UI | `BudgetTracker/Views/Accounts/NetWorthView.swift`, `NetWorthGroupDetailView.swift` |
| Insights UI | `BudgetTracker/Views/Insights/InsightsViews.swift` |
| Smart features | `BudgetTracker/Backend/Finance/SmartFeaturesStore.swift` |
| Aggregates | `CashFlowEngine.swift`, `TransactionStore.swift`, `NetWorthHistoryEngine.swift`, `InvestmentHistoryEngine.swift` |

## Go-bys

- Chart/summary patterns: keep logic in `Backend/Finance/`, views thin
- Gemini usage: same client as categorization go-by

## Do not

- Block dashboard on network without cached/error state
- Expose raw transaction PII in insight prompts beyond what the feature needs
