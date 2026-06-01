# Lessons Learned

Last updated: 2026-06-01

Purpose
- Capture resolved issues and proven fixes so future agents do not re-open solved problems.
- Read this file before bug-fix passes; verify current behavior before re-implementing an old fix.
- When you fix a new issue, append an entry below (do not rewrite or delete old entries).

Entry format
- **Symptom** — what the user or CI saw
- **Root cause** — why it happened
- **Fix pattern** — what to do
- **Guardrails** — what not to break
- **Verification** — how to confirm

## Resolved Issues Ledger

### 2026-06-01 - Immediate TestFlight crash on launch (iOS 26 + Supabase)
- **Symptom:** App closes instantly on open on device/TestFlight; no UI. ASC crash API returned 0 feedback entries; LAUNCHES diagnostics 404 (not ingested yet).
- **Root cause:** `supabase-swift` before **2.44.0** force-unwraps `URL.host` in `SupabaseClient.init`. On **iOS 26**, deprecated `URL.host` returns `nil` for valid `https://` URLs → `EXC_BREAKPOINT` in `SupabaseClient.init` before UI (see [supabase/supabase-swift#960](https://github.com/supabase/supabase-swift/issues/960), fixed in **2.44.0** / [#962](https://github.com/supabase/supabase-swift/pull/962)). Budget Tracker pinned `from: 2.0.0` and calls `SupabaseClient` during `AuthStore.bootstrap()` right after launch.
- **Fix pattern:** Pin Supabase SPM to **`from: "2.44.0"`** (or newer). Keep `AuthStore` lazy client creation (no `SupabaseClient` in `init`). Optional: `STRIP_BITCODE_FROM_COPIED_FILES = NO` for LinkKit embed safety.
- **Guardrails:** Do not downgrade Supabase below 2.44.0 while supporting iOS 26 / Xcode 26 SDK builds. Re-fetch crashes with `node scripts/fetch-asc-crashes.mjs` after the next TestFlight wave.
- **Verification:** `bash scripts/verify-supabase-package.sh` and `AuthStoreTests` pass on CI; app reaches auth screen on iOS 26 device; Xcode Organizer crash no longer shows `SupabaseClient.init` + `URL.host` force-unwrap. See `docs/TDD_AND_CRASHES.md`.

### 2026-05-31 - Agent docs split (brief vs living instructions)
- **Symptom:** Agents only had docs/PROJECT_BRIEF.md; no standing place for post-fix notes or shipped behavior deltas.
- **Root cause:** Handoff copied Optimized engineering patterns but not AI_PROJECT_INSTRUCTIONS.txt / LESSONS_LEARNED.md files.
- **Fix pattern:** Maintain AI_PROJECT_INSTRUCTIONS.txt (rules + update log) and this file (fixes); PROJECT_BRIEF stays the full spec.
- **Guardrails:** Do not paste secrets into either file; use Config/SECRETS.local.md.
- **Verification:** README and PROJECT_BRIEF list both files in agent read order.

### 2026-05-31 - Supabase project ref typo in handoff brief
- **Symptom:** DNS failed for `dldbcbituxuxedlkeefu.supabase.co`; `supabase link` returned Not Found.
- **Root cause:** Brief/transcript typo; live project ref is `dldbcbituquxedlkeefu` (budget-tracker).
- **Fix pattern:** Use ref/URL from Supabase dashboard or Management API `GET /v1/projects`; update `Config/SECRETS.local.md` and docs.
- **Guardrails:** Do not share Supabase project with Optimized fitness app.
- **Verification:** `nslookup dldbcbituquxedlkeefu.supabase.co` resolves; `scripts/test-plaid-sandbox.ps1` passes.

### 2026-05-31 - GitHub Actions minutes / billing gate
- **Symptom:** Cannot push to verify compile until next month's Actions minutes restore.
- **Root cause:** GitHub Actions billing or monthly minute cap (same class of issue documented in Optimized brief).
- **Fix pattern:** Continue Windows development locally; run **Verify compile** via Actions → workflow_dispatch after minutes reset; avoid push-triggered CI while waiting.
- **Guardrails:** Do not disable tests or skip `BudgetTrackerTests` to “save” CI — wait for minutes or fix billing.
- **Verification:** Manual workflow_dispatch run completes build + test job on `macos-15`.

### 2026-05-31 - Plaid production gaps (webhooks, update mode, defense in depth)
- **Symptom:** Sandbox link/sync worked, but ongoing Production sync and re-auth would fail without webhooks, update mode, and item lifecycle handling.
- **Root cause:** Initial implementation covered 4 user-facing Edge Functions only; Plaid Launch Center requires webhooks for repeated sync, update mode for `ITEM_LOGIN_REQUIRED`, and `/item/remove` on disconnect.
- **Fix pattern:** Added `plaid-webhook` (Plaid JWT + body hash verification, idempotent `plaid_webhook_events`), `plaid-create-update-link-token`, `plaid-remove-item`, Vault delete RPC, audit log, rate limits, iOS reconnect/disconnect UI. Documented full checklist in `docs/PLAID_PRODUCTION_CHECKLIST.md`.
- **Guardrails:** Deploy `plaid-webhook` with `--no-verify-jwt`; never expose `access_token` to iOS; set `PLAID_REDIRECT_URI` before Production OAuth banks.
- **Verification:** `scripts/deploy-backend.ps1` → sandbox smoke test → fire Sandbox webhook → confirm sync + `plaid_items.status` updates.

### 2026-06-01 - Plaid Trial approved → Production backend switch
- **Symptom:** Trial access approved; backend still on Sandbox secrets (`PLAID_ENV=sandbox`).
- **Root cause:** Production secret lives in Dashboard only until pasted into `Config/SECRETS.local.md` and deployed via `scripts/switch-plaid-production.ps1`.
- **Fix pattern:** Set `PLAID_PRODUCTION_SECRET` locally (never chat) → run switch script → verify `production.plaid.com/link/token/create` OK.
- **Guardrails:** Sandbox Items do not carry over; disconnect old test bank before linking real institution. OAuth banks need `PLAID_REDIRECT_URI` + Universal Link.
- **Verification:** Supabase secrets show `PLAID_ENV=production`; link token create succeeds against `production.plaid.com`.

### 2026-06-01 - Plaid Link "post process failed" on iOS
- **Symptom:** After completing bank login in Link, UI shows post process failed (common with Production OAuth banks).
- **Root cause:** Link `Handler` was not retained for the full session; OAuth return URL was not handled via `.onOpenURL` / `handler.continue(from:)`.
- **Fix pattern:** `PlaidLinkCoordinator` holds `Handler`; `BudgetTrackerApp.onOpenURL` calls `continueLink(from:)`; surface `LinkExit` error text in `PlaidLinkView`.
- **Guardrails:** OAuth institutions still need `PLAID_REDIRECT_URI` + Universal Link in Plaid Dashboard and Xcode associated domains.
- **Verification:** Link real bank on device; no post-process error; accounts appear after exchange.

## Operational Notes
- For release builds/uploads, follow the command chain in `AI_PROJECT_INSTRUCTIONS.txt` under **Release / TestFlight**.
- For CI while minutes are limited, use GitHub Actions **Verify compile** with `workflow_dispatch`.
- When adding a new lesson, include the test name(s) that cover the regression when available.

### 2026-06-01 - Robinhood / OAuth stuck on website (redirect pages 404)
- **Symptom:** Plaid Link opens Robinhood or a bank website; user never returns to Budget Tracker; linking does not complete.
- **Root cause:** GitHub Pages OAuth assets were not deployed — `oauth.html` and `apple-app-site-association` returned **404**, so Universal Links and the “return to app” page never worked. Separately, clearing the Link `Handler` on every `onExit` could drop OAuth mid-handoff.
- **Fix pattern:** Ship `docs/.nojekyll`, `docs/.well-known/apple-app-site-association`, `docs/plaid/oauth.html`; enable Pages on `dsmccaughan-eng/budget-tracker-ios`; run `scripts/verify-plaid-oauth-pages.ps1`; set `PLAID_REDIRECT_URI` + Plaid Dashboard redirect URI; retain `Handler` on OAuth handoff (`onExit` only clears when `exit.error != nil`).
- **Guardrails:** Run verify script before telling user OAuth is ready; Robinhood requires Production + redirect URI (not Sandbox-only flow).
- **Verification:** Both URLs return 200; link Robinhood on TestFlight → return page → app completes exchange; accounts sync.

### 2026-06-01 - Robinhood OAuth spins / loads for minutes after sign-in
- **Symptom:** User completes Robinhood login; Plaid or app shows loading for several minutes; link never finishes.
- **Root cause:** Plaid calls `onExit` with no error when handing off to OAuth; `PlaidLinkView` treated that as failure, dismissed the sheet, and `endSession()` destroyed the `Handler` before the user returned. Initial transaction sync after link also blocked the UI.
- **Fix pattern:** On `onExit` with `exit.error == nil` and no user-facing exit message, keep sheet + handler (`markOAuthHandoff`); handle Universal Links via `onContinueUserActivity`; after `onSuccess`, dismiss sheet, save token, sync transactions in background `Task`.
- **Guardrails:** Do not set `isPresentingLink = false` on OAuth handoff `onExit`; do not call `endSession()` from sheet `onDismiss` while `isOAuthHandoff`.
- **Verification:** Link Robinhood → leave for bank → return → success within seconds; accounts appear; transactions sync without blocking button.

### 2026-06-01 - Dashboard “Set up budgets” and missing pie/bills UI
- **Symptom:** TestFlight build lacked budget donut, bills list, or month-grouped transactions; Dashboard “Set up budgets” did nothing.
- **Root cause:** `RootView` wrapped `MainTabView` in an extra `NavigationStack`, breaking pushes from tab `NavigationLink`s; pie chart only drew slices with `spent > 0`, so new budgets looked empty.
- **Fix pattern:** One navigation stack per tab; present `AddBudgetView` in a sheet from Dashboard; pie uses monthly limits until spending exists; reload budgets on Dashboard `.task`; build number 6.
- **Verification:** Set up budgets sheet saves; Budgets tab shows donut + category rows; Dashboard preview pie + bills section; Transactions grouped by month.

### 2026-06-01 - App lock and budgets “not implemented” on device
- **Symptom:** User reported no Face ID/PIN and broken budgets despite merged code and green Codemagic build.
- **Root cause:** PIN used a 1×1 invisible `SecureField` that often does not focus on iOS; users never completed PIN setup so the app looked unchanged. Budget saves did not always reload UI or show errors.
- **Fix pattern:** Visible `PINEntryField` with focus; explicit Set PIN steps; reload financial data on unlock/PIN; budget save alerts and duplicate-category guard; TestFlight build 7.
- **Verification:** Fresh install → email sign-in → “Secure your budget” screen → enter/confirm PIN → Face ID on reopen; Set up budgets saves and pie appears.

### 2026-06-01 - Budget save: missing is_fixed column; Face ID error 6 on reopen
- **Symptom:** Add budget failed with schema cache error for `budgets.is_fixed`; pie empty; Face ID worked after force-quit but on normal reopen showed LocalAuthentication error 6 and required manual retry.
- **Root cause:** Remote `budgets` table lacked `is_fixed` / `is_rollover` columns; biometric prompt ran in `.task` before `scenePhase == .active` (biometryNotAvailable).
- **Fix:** Migration `20260601120000_budgets_fixed_rollover.sql`; delay auto Face ID 500ms after active; lock only on `.background`; friendly message for error 6 without counting as failure.
- **Verification:** `supabase db push`; save budget with Fixed expense toggle; cold open → Face ID auto-prompt without error 6.

### 2026-06-01 - Budgets pie: sync message with $0 spend; projections always zero
- **Symptom:** TestFlight Budgets tab showed “Spending will appear when transactions sync” despite synced transactions; category projections were $0; no month navigation or edit/delete affordances.
- **Root cause:** Pie chart treated `totalSpent == 0` as “not synced”; projections used in-month pace (`spent / day * daysInMonth`) so zero current-month spend yielded zero projection; UI only had swipe-delete.
- **Fix:** Show sync hint only when no transactions are loaded; show “No spending this month yet” when synced but empty; use `BudgetMath.averageMonthlySpend` (6-month mean per category) for `projectedSpend`; month chevrons + `EditBudgetView` + context menu delete; refreshed pie legend/styling.
- **Verification:** Budgets with synced txns and $0 this month → no sync message, typical $/mo on rows; past months via chevrons; tap row → edit limit/color/delete; `BudgetMathTests` average/projection cases pass.

### 2026-06-02 - Per-account balance history (1 year)
- **Symptom:** User wanted each account’s value at different times over the last year; Plaid only returns current balance on refresh.
- **Root cause:** No `account_balance_snapshots` table; transaction fetch capped at 100 rows (insufficient for reconstruction).
- **Fix:** Migration `20260602120000_account_balance_snapshots.sql`; record snapshots on `plaid-get-accounts` / link / app reload; `AccountBalanceHistoryEngine` reconstructs daily balances from current balance + settled transactions; `AccountDetailView` with scrubbing chart (1M–ALL).
- **Verification:** Tap account on Accounts or Net Worth → chart scrubs; label shows “Estimated from activity” vs saved snapshot; deploy migration + edge functions; sync transactions for full year.

### 2026-06-02 - Codemagic archive: ShapeStyle ternary compile error
- **Symptom:** Build IPA failed (exit 65) on `BudgetCategorySpendRow` / `BudgetProgressBar` — cannot mix `.secondary` (HierarchicalShapeStyle) and `.red` (Color) in one ternary for `foregroundStyle`.
- **Root cause:** Swift requires a single concrete `ShapeStyle` type in ternary branches; semantic `.secondary` vs `.red` differ.
- **Fix:** Use `Color.secondary` / `Color.red` (and `plotAreaFrame` not `plotFrame` on chart overlay). Rebuild with bumped `CURRENT_PROJECT_VERSION`.
- **Verification:** Codemagic unit-test step + archive succeed.

<!-- Append new entries above this line -->
