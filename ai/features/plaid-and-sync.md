# Feature: Plaid and transaction sync

**Canonical rules:** `AI_PROJECT_INSTRUCTIONS.txt` → Plaid and secrets; Engineering → Supabase backend

## Behavior

- iOS → Supabase Edge Function → Plaid only
- `access_token` in Vault only; webhook for ongoing sync
- Errors surface in UI (`TransactionStore.errorMessage`, Plaid link status)
- Production: `docs/PLAID_PRODUCTION_CHECKLIST.md`

## Code map

| Area | Path |
|------|------|
| Link UI (unified) | `BudgetTracker/Views/Plaid/BankLinkView.swift` |
| Plaid Link | `BudgetTracker/Views/Plaid/PlaidLinkView.swift` |
| Teller Connect | `BudgetTracker/Views/Plaid/TellerLinkView.swift` |
| Link policy | `BudgetTracker/Backend/Finance/ConnectionPolicyEngine.swift` |
| Aggregation API | `supabase/functions/aggregation-*`, `teller-*` |
| Coordinator | `BudgetTracker/Backend/Plaid/PlaidLinkCoordinator.swift` |
| Models | `BudgetTracker/Backend/Plaid/PlaidModels.swift` |
| Transactions | `BudgetTracker/Backend/Finance/TransactionStore.swift` |
| Edge Functions | `supabase/functions/plaid-*` |
| Migrations | `supabase/migrations/` |

## Go-bys

- [`docs/ai/go-bys/plaid-edge-functions.md`](../../docs/ai/go-bys/plaid-edge-functions.md)
- `LESSONS_LEARNED.md` — OAuth, post-process failed, production switch

## Verify

```powershell
.\scripts\test-plaid-sandbox.ps1
```

## Do not

- Call Plaid REST from iOS
- Store full account numbers (last 4 mask only)
