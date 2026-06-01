# Plaid OAuth (Robinhood, Chase, etc.)

OAuth institutions open the bank website or app, then must return to Budget Tracker via a **redirect URI**.

## One-time setup

1. **GitHub Pages** (repo `dsmccaughan-eng/budget-tracker-ios`):
   - Settings → Pages → Build from branch **main**, folder **/docs**
   - After deploy, verify:  
     `https://dsmccaughan-eng.github.io/budget-tracker-ios/.well-known/apple-app-site-association`

2. **Plaid Dashboard** → Team Settings → **API** → Allowed redirect URIs, add exactly:
   ```
   https://dsmccaughan-eng.github.io/budget-tracker-ios/plaid/oauth.html
   ```

3. **Secrets** — in `Config/SECRETS.local.md`:
   ```
   PLAID_REDIRECT_URI=https://dsmccaughan-eng.github.io/budget-tracker-ios/plaid/oauth.html
   ```
   Then: `.\scripts\deploy-backend.ps1`

4. **TestFlight build** must include Associated Domains (entitlements in `BudgetTracker.entitlements`).

## After linking

When the bank sends you to the Robinhood app to log in, complete login, then **switch back to Budget Tracker**. Link should finish automatically if the handler is still open.

If it still fails, disconnect the item in Accounts and try **Reconnect** after confirming steps 1–4.
