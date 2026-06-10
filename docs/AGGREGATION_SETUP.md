# Plaid + Teller aggregation

Budget Tracker can link banks through **Plaid** (default) or **Teller** (fallback when the global Plaid Trial item cap is reached).

## Routing (automatic)

| Condition | New links use |
|-----------|----------------|
| `PLAID_ENV=sandbox` | Plaid (unlimited sandbox) |
| Global `plaid_items` count &lt; `PLAID_TRIAL_ITEM_LIMIT` (default 10) | Plaid |
| At or over limit and `TELLER_APPLICATION_ID` set | Teller |
| At limit, Teller not configured | Plaid link fails at Plaid API |

Existing connections stay on their provider until disconnected.

## Teller developer account (optional)

**You do not need Teller** to run Budget Tracker. Plaid sandbox + Trial cover most testing. Add Teller only when you need more than 10 Production Plaid items.

Teller signup URLs change; `https://teller.io/user/new` often returns 404. Try:

1. [teller.io/blog](https://teller.io/blog) — banner link **Create free account** (top of page).
2. [teller.io/user/new](https://teller.io/user/new) — registration form (if it loads in your browser).
3. Email [legal-notices@teller.io](mailto:legal-notices@teller.io) — request a developer dashboard invite and an Application ID (`app_…`).

If you only see **Log in** with no sign-up link, use (2) or (3). Production KYB is separate; see [Environments](https://teller.io/docs/guides/environments).

## Supabase secrets

Add to `Config/SECRETS.local.md` and deploy with `.\scripts\deploy-backend.ps1`:

```
TELLER_APPLICATION_ID=app_xxxxxxxx
TELLER_ENV=sandbox
PLAID_TRIAL_ITEM_LIMIT=10
```

- **sandbox** — Teller sandbox enrollments (no real banks)
- **development** — real banks, Teller dev tier (not billed)
- **production** — live Teller

## iOS

- User-facing entry: `BankLinkView` (Dashboard / Accounts → Link bank)
- Product screens (transactions, budgets, dashboard) are unchanged — same `accounts` / `transactions` tables

## Edge Functions

| Function | Purpose |
|----------|---------|
| `aggregation-link-policy` | Returns `provider` + Teller app id for Connect |
| `aggregation-sync-transactions` | Syncs Plaid + Teller |
| `teller-exchange-enrollment` | Saves Teller token to Vault |
| `teller-sync-transactions` | Teller-only sync |
| `teller-remove-item` | Disconnect Teller enrollment |

## Database

Migration `20260603180000_teller_aggregation.sql` adds `teller_items`, `accounts.provider`, and Vault helpers for Teller tokens.
