# Go-by: Plaid via Supabase Edge Functions

## In-repo

| Function | Path |
|----------|------|
| Link token | `supabase/functions/plaid-create-link-token/` |
| Update link | `supabase/functions/plaid-create-update-link-token/` |
| Exchange | `supabase/functions/plaid-exchange-public-token/` |
| Accounts | `supabase/functions/plaid-accounts/` |
| Sync | `supabase/functions/plaid-sync/` |
| Remove item | `supabase/functions/plaid-remove-item/` |
| Webhook | `supabase/functions/plaid-webhook/` (`--no-verify-jwt`; Plaid JWT) |

| iOS | Path |
|-----|------|
| Link UI | `BudgetTracker/Views/Plaid/PlaidLinkView.swift` |
| Coordinator | `BudgetTracker/Backend/Plaid/PlaidLinkCoordinator.swift` |
| OAuth return | `BudgetTracker/App/BudgetTrackerApp.swift` (`onOpenURL` → `continueLink`) |

## Verify

```powershell
.\scripts\deploy-backend.ps1
.\scripts\test-plaid-sandbox.ps1
```

## Docs

- `docs/PLAID_PRODUCTION_CHECKLIST.md`
- `docs/PLAID_OAUTH_SETUP.md`
- `LESSONS_LEARNED.md` — Plaid OAuth / post-process failures

## External (pattern only)

- [Plaid Link iOS](https://plaid.com/docs/link/ios/)
- [Plaid webhooks](https://plaid.com/docs/api/webhooks/)
