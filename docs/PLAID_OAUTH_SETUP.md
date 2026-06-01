# Plaid OAuth (Robinhood, Chase, etc.)

OAuth institutions open the bank website or app, then must return to Budget Tracker via a **redirect URI**.

## Why Robinhood sends you to a website

That is expected. After you sign in, Plaid redirects to your **redirect URI** (`oauth.html`). That page must exist on the web and must open Budget Tracker again. If the redirect page is missing (404), you stay in Safari and linking never finishes.

## One-time setup

### 1. GitHub Pages (repo `dsmccaughan-eng/budget-tracker-ios`)

1. GitHub → **Settings** → **Pages** → Build from branch **`main`**, folder **`/docs`**
2. Wait a few minutes for deploy
3. Verify (must be **200**, not 404):

```powershell
powershell -File scripts/verify-plaid-oauth-pages.ps1
```

Expected URLs:

- `https://dsmccaughan-eng.github.io/budget-tracker-ios/.well-known/apple-app-site-association`
- `https://dsmccaughan-eng.github.io/budget-tracker-ios/plaid/oauth.html`

`docs/.nojekyll` is required so GitHub serves `.well-known/` (without it, Universal Links break).

### 2. Plaid Dashboard

Team Settings → **API** → **Allowed redirect URIs** — add exactly:

```
https://dsmccaughan-eng.github.io/budget-tracker-ios/plaid/oauth.html
```

### 3. Supabase secret

In `Config/SECRETS.local.md`:

```
PLAID_REDIRECT_URI=https://dsmccaughan-eng.github.io/budget-tracker-ios/plaid/oauth.html
```

Then deploy:

```powershell
.\scripts\deploy-backend.ps1
```

### 4. TestFlight build

Associated Domains entitlement must be in the build (`BudgetTracker.entitlements` → `applinks:dsmccaughan-eng.github.io`).

## Linking Robinhood on device

1. In Budget Tracker: **Connect Bank** (leave the app open; do not force-quit).
2. Choose Robinhood → sign in on the website or Robinhood app.
3. When redirected, tap **Open Budget Tracker** on the return page (or switch back manually).
4. Wait for “Linked …” — accounts should appear under Accounts.

## If it still fails

| Check | Action |
|-------|--------|
| `verify-plaid-oauth-pages.ps1` fails | Enable Pages and push `docs/` on `main` |
| Never see “Open Budget Tracker” page | `PLAID_REDIRECT_URI` not deployed — run `deploy-backend.ps1` |
| Post-process / setup error | Re-link without closing app; install latest TestFlight build |
| Old sandbox item | Disconnect test bank in Accounts before linking Robinhood (Production) |
