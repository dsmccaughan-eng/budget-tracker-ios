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

### 2026-06-02 - TestFlight Test Information empty; build on ASC but not in TestFlight app
- **Symptom:** User cannot save Test Information; TestFlight app shows no Budget Tracker build.
- **Root cause:** `betaAppLocalizations` count was **0** (nothing to edit in API/UI). Build **32** was already `VALID` / `READY_FOR_BETA_TESTING` internally. ASC API key `N99V63R65U` returns **403** on `POST betaAppLocalizations` and `PATCH betaAppReviewDetails` (upload-only role); Account Holder must complete Test Information in browser once.
- **Fix:** ASC → TestFlight → Test Information → English (U.S.) → Beta App Description + Feedback Email + Beta App Review contact. Internal install: TestFlight app signed in as `dsmccaughan@gmail.com` (Account Holder). Optional: `node scripts/setup-asc-testflight-info.mjs` after Admin-capable key or `ASC_CONTACT_PHONE` set.
- **Verification:** `node scripts/setup-asc-testflight-info.mjs --inspect` shows `betaAppLocalizations` ≥ 1; build `internalBuildState` = `READY_FOR_BETA_TESTING`.

### 2026-06-02 - Codemagic “distribution failed” but IPA uploaded (TestFlight metadata)
- **Symptom:** Build IPA succeeded; App Store Connect distribution failed on build 14 (`6a1ddadc`).
- **Root cause:** `submit_to_testflight: true` tried external beta review without Beta App Information (feedback email) or Beta App Review contact (name, phone, email) in ASC for app `6775334574`.
- **Fix:** User completes [TestFlight Test Information](https://appstoreconnect.apple.com/apps/6775334574/testflight/test-info); install build from TestFlight → iOS builds. Set `submit_to_testflight: false` in `codemagic.yaml` until metadata exists so CI does not fail post-upload.
- **Verification:** ASC shows processed build; internal testers can install after test info + tester group.

### 2026-06-05 - Sign-in email showed 8-digit code, app expects 6
- **Symptom:** Email OTP was 8 digits; app UI asks for 6 (still worked if user entered full code).
- **Root cause:** Hosted Supabase `mailer_otp_length` was 8; repo `config.toml` and app assume 6.
- **Fix:** PATCH Management API `mailer_otp_length: 6`; `fix-supabase-auth-email.mjs` `applyOtpEmailTemplate()` sets it.
- **Verification:** Request new code — email shows 6 digits; `verifyOTP` succeeds.

### 2026-06-05 - Budget totals stale after exclude; pie ≠ category sum
- **Symptom:** Center “Spent” did not drop when toggling exclude from budget; category rows did not add up to pie total.
- **Root cause:** Pie used only **budgeted** categories (`monthRows`) while the list included unbudgeted spending; month row cache key ignored transaction fingerprint; category drill-down net included excluded txns.
- **Fix pattern:** Drive pie from `displayMonthSections.spending`; `monthSpendingDisplayTotal` for center total; include `indexedFingerprint` in cache keys; bump `spendDataVersion` on index/cache refresh; `transactionsForCategory` omits excluded by default.
- **Verification:** Exclude a large txn → pie center and category row drop; sum of spending rows equals center total; `BudgetMathTests` `testMonthSpendingDisplayTotalDropsExcludedTransactions`.

### 2026-06-05 - Codemagic build 20: Section footer and onDelete scope
- **Symptom:** Build 20 failed — `onDelete` not in scope on `Section`; `Section("Budget") { } footer:` invalid.
- **Fix:** `onDelete` on `ForEach` only when `allowsDelete`; use `Section { } header:footer:` for budget exclusion toggle.
- **Verification:** Codemagic archive succeeds.

### 2026-06-05 - Codemagic build 19: BudgetStore multiline string interpolation (again)
- **Symptom:** Build 19 IPA failed at `BudgetStore.swift:72` and `:254`.
- **Root cause:** `listCacheKey` reintroduced multiline `"\(...BudgetMath.cacheKey(...))"` after refactor.
- **Fix:** Centralize `monthCacheKey(prefix:referenceDate:transactions:)` helper.
- **Verification:** Codemagic archive succeeds.

### 2026-06-05 - Similar merchant auto-categorization from user history
- **Symptom:** Slightly different merchant text (e.g. "MOBILE CR CARD PMT") not inheriting user's past category.
- **Fix:** Token similarity against saved rules + user-categorized transactions (`user_similar`); Gemini receives user examples. Deployed in `plaid-sync-transactions`.
- **Verification:** `MerchantSimilarityTests`; sync assigns `category_source=user_similar` when matched.

### 2026-06-05 - Mobile credit card mis-tagged as Transport
- **Symptom:** "Mobile credit card transfer" categorized as Transport.
- **Root cause:** `mobil` gas-station pattern matched as substring inside `mobile`; Plaid `TRANSPORTATION` fallback.
- **Fix:** Transfer heuristics before merchant_db; word-boundary match for short patterns; expanded transfer merchant_db + seed script; Gemini prompt clarification.
- **Verification:** `TransferHeuristicsTests`, `CategorizationEngineTests`; redeploy `plaid-sync-transactions`.

### 2026-06-04 - Codemagic archive failed: BillsEngine.resolvedDueDay calendar arg
- **Symptom:** Build 18 IPA failed; `EditBillView` / `TransactionDetailView` missing `calendar` argument.
- **Root cause:** `resolvedDueDay` required `calendar` with no default; call sites omitted it.
- **Fix:** Default `calendar` to `.current` (same as `defaultDueDay`).
- **Verification:** Codemagic archive succeeds.

### 2026-06-04 - Codemagic archive failed: BudgetStore string interpolation
- **Symptom:** Build 17 IPA failed; Swift errors in `BudgetStore.swift:53`.
- **Root cause:** Multi-line function call inside `"\(...)"` string interpolation is invalid Swift.
- **Fix:** Compute `BudgetMath.cacheKey(...)` in a local variable before building the cache key string.
- **Verification:** Codemagic archive succeeds.

### 2026-06-04 - Budget month nav, live totals, transaction-based bills
- **Symptom:** Category colors duplicated; month arrows stuck after first tap; budget totals stale after recategorizing; bills tied to budget categories.
- **Root cause:** Palette reused 8 colors across 17 categories; month cache + in-place transaction mutation did not refresh UI; `BillsEngine` read `budget.isFixed`.
- **Fix:** Distinct per-category palette; month navigator uses offset + multi-key cache; transaction fingerprint + array reassignment; bills anchored on `transactions.is_fixed_bill` with nickname/due day/amount.
- **Verification:** Unit tests for bill engine + spend sort; save plan reapplies distinct colors.

### 2026-06-03 - Codemagic archive failed: MerchantRulesStore upsert extension
- **Symptom:** Build IPA failed on commit `8d87b3a`; Swift error at `MerchantRulesStore+Upsert.swift:23`.
- **Root cause:** `upsertRule` lived in a separate file but assigned to `@Published private(set) var rules`, whose setter is private to the declaring file only.
- **Fix:** Move `upsertRule` into `SmartFeaturesStore.swift` inside `MerchantRulesStore`; delete extension file.
- **Verification:** Codemagic archive succeeds.

### 2026-06-03 - Refunds shown as credits; category drill-down; merchant rules on edit
- **Symptom:** All transactions displayed as expenses (`abs(amount)`); budget rows not drillable; no persistent merchant tag on category change; no AI attribution.
- **Fix:** `TransactionFormatting` inverts Plaid sign (credits green, expenses negative display); net budget spend subtracts refunds; tap budget category → `CategoryTransactionsView`; save category toggle creates/updates merchant rule; `category_source` column + Gemini badge on list/detail.
- **Verification:** `TransactionFormattingTests`, `BudgetMathRefundTests`; redeploy edge functions + migration `20260603120000_transaction_category_source.sql`.

<!-- Append new entries above this line -->

### 2026-06-02 - Budget tab lag (repeated transaction scans)
- **Symptom:** Budgets tab stuttered scrolling and month changes with thousands of synced transactions.
- **Root cause:** `BudgetView` recomputed `progressRows` and per-row `recentMerchantSummary` on every SwiftUI body pass (O(budgets × months × transactions)); tab `.task` also re-fetched all transactions each visit.
- **Fix:** `BudgetSpendIndex` single-pass index, `BudgetStore.monthRows` cache keyed by month/budgets, light tab reload; unified `SetupBudgetPlanView` for total + category breakdown with auto colors.
- **Verification:** `BudgetSpendIndexTests`; scroll/month navigation should stay responsive with full transaction history loaded.

### 2026-06-10 - Net worth dashboard frozen after bank sync
- **Symptom:** Dashboard net worth and chart stayed at day-one values while new transactions kept syncing.
- **Root cause:** Net worth reads `accounts.current_balance`, but `NetWorthStore` only reloaded on cold unlock; sync updated accounts without refreshing net worth. Daily `net_worth_snapshots` / `account_balance_snapshots` were recorded once and skipped later updates when rows already existed for today.
- **Fix:** Reload net worth when linked accounts change; load account balance snapshots before net worth; upsert today's per-account and net-worth snapshots when totals change; dashboard pull-to-refresh and Net Worth screen always reload.
- **Verification:** Sync or pull to refresh → dashboard headline and Net Worth chart/today section reflect current balances; historical chart gains new daily points after sync.

### 2026-06-10 - Net worth reload races and stale account detail
- **Symptom:** Duplicate net-worth reloads on unlock; auto Plaid refresh showed Accounts spinner; account detail could show stale balances after refresh; Net Worth pull-to-refresh skipped `loadAll` when accounts existed.
- **Root cause:** Overlapping `onChange` + `.task` reload hooks; `loadAll` always toggled `isLoading`; navigation captured a static `Account` value; Net Worth refresh path omitted daily snapshots.
- **Fix:** Single app-level financial reload via `.task(id:)`; `loadAll(showsLoading:)`; live account resolution in `AccountDetailView`; unified net-worth refresh helpers across Dashboard/Accounts/Net Worth; shared `FinanceDate.todayString`.
- **Verification:** Unlock once → one reload cycle; silent daily Plaid refresh; manual ↻ updates net worth; Net Worth pull refresh fetches latest balances.

### 2026-06-10 - Codemagic IPA failed on TellerKit SPM
- **Symptom:** Build #43 failed at `Build IPA` / `showBuildSettings`; `Resolve Swift packages` logged missing `Package.swift` in `tellerhq/tellerkit`.
- **Root cause:** Upstream TellerKit repo ships only `TellerKit.xcframework` (no SPM manifest); `ci-step-timeout.sh` masked non-zero exits so resolve failures looked green.
- **Fix:** Vend `Vendor/TellerKitSPM` local binary package; point `project.yml` at local path; fix `wait` exit propagation in `ci-step-timeout.sh`.
- **Verification:** Codemagic resolve packages succeeds; unit tests + IPA build complete.

### 2026-06-10 - CI unit tests picked simulator placeholder
- **Symptom:** Codemagic `Run unit tests` failed with destination `iphonesimulator:placeholder` on Xcode 26.4.
- **Root cause:** `run-unit-tests.sh` used the first `platform:iOS Simulator` line from `-showdestinations`, which is a placeholder entry on newer Xcode.
- **Fix:** Skip lines containing `placeholder`; pick the first real simulator id (e.g. iPhone 17).
- **Verification:** Codemagic unit test step completes; IPA build proceeds.

### 2026-06-10 - Link account 404 after build 51 (aggregation functions not deployed)
- **Symptom:** Build 51 shows no linked accounts / cannot link; Link Account error `non-2xx status code: 404`.
- **Root cause:** `BankLinkView` calls undeployed Edge Function `aggregation-link-policy`; sync also targets `aggregation-sync-transactions`. Backend migration/functions from Teller aggregation were never deployed to Supabase.
- **Fix:** Client fallback to Plaid link policy + `plaid-sync-transactions` when aggregation functions 404; resilient `loadAll` so accounts/transactions still load if item metadata fetch fails. Deploy with `.\scripts\deploy-backend.ps1`.
- **Verification:** Link Account opens Plaid without 404; existing accounts reappear after pull-to-refresh; deploy aggregation functions for full Teller routing.

### 2026-06-10 - Dashboard shows 0 linked accounts while Accounts has connections
- **Symptom:** Dashboard Accounts row says "0 linked accounts" but Accounts screen shows bank connections (and often account rows after opening). Net Worth tab had no account sections despite synced transactions.
- **Root cause:** Dashboard `.task` reload was removed to dedupe app-level reload; `accounts` can still be empty when `plaidItems`/`transactions` already loaded (partial `loadAll` or timing). Net Worth account groups derive from `transactions.accounts`; net-worth snapshot reload ran before accounts arrived.
- **Fix:** Restore Dashboard `.task` reload; show connection count when `accounts` is empty but `bankConnections` is not; reload accounts on Accounts/Net Worth when empty; app `onChange(accounts.count)` refreshes net worth when accounts go from 0 → N; collapsible unreviewed transactions via `DisclosureGroup`.
- **Verification:** Dashboard label matches connections or account count after open; Net Worth lists grouped accounts after sync; long unreviewed list collapses by default (>3 items).

### 2026-06-10 - Budget alerts for fixed costs (housing, bills)
- **Symptom:** Dashboard Alerts warned when Housing & Utilities neared 100% after rent/utilities payments — expected for fixed monthly costs.
- **Root cause:** `BudgetAlertEngine` treated every category the same at the alert threshold (and when over budget).
- **Fix:** Skip alerts when `BudgetProgress.isFixed` or the category has a transaction marked **Fixed monthly expense** (`isFixedBill`). Pass transactions into alert calls from Dashboard and notification settings.
- **Verification:** Fixed budget or fixed-bill category at 95% → no alert; Groceries at 85% with threshold 0.8 → alert still shown.

### 2026-06-10 - Dashboard reload and review UI edge cases
- **Symptom:** Duplicate reloads on unlock; review list collapsed while reviewing long queues; Accounts/Net Worth stuck when connections exist but account rows missing; synthetic account rows with wrong type.
- **Root cause:** Unconditional Dashboard `.task` overlapped app `.task(id:)`; `onChange(accounts.count)` and Net Worth `onChange` duplicated net-worth reload; empty-account recovery paths skipped `refreshPlaidAccountsIfNeeded`; `unreviewedExpanded` used `onChange` only (no initial appear) and reset on every count change.
- **Fix:** Gate Dashboard/Accounts `.task` to empty accounts + existing connections/transactions; coalesce concurrent `loadAll` in `TransactionStore`; add Plaid refresh to Accounts/Net Worth recovery reloads; `onAppear` + threshold-crossing `onChange` for review expansion; restore conditional Net Worth navigation without synthetic `Account`.
- **Verification:** Unlock → one reload cycle; expand 10-item review list → stays open after marking one reviewed; connections + empty accounts → Accounts/Net Worth pull refresh populates rows.

### 2026-06-10 - Net Worth tab empty despite synced transactions
- **Symptom:** Net Worth chart/Today could show values but account sections stayed empty; or "Accounts loading" never resolved.
- **Root cause:** Account rows only render from `transactions.accounts`. Recovery paths used daily-gated `refreshPlaidAccountsIfNeeded` only (skipped after first refresh). `fetchAccounts` could fail decoding legacy rows (missing `provider`, string balances). Net Worth UI did not force `plaid-get-accounts` when connections/transactions existed.
- **Fix:** `refreshAccountsIfMissing` after load (Plaid refresh + Teller sync fallback); resilient `Account` decoding; Net Worth uses `cachedAccounts` fallback; explicit refresh button + error surfacing on Net Worth.
- **Verification:** Open Net Worth with linked bank → Cash/Loan sections list accounts; if DB empty, Refresh accounts pulls from Plaid and repopulates.

### 2026-06-10 - Stale net worth and flat investment history
- **Symptom:** Net Worth totals lagged Plaid; tapping an account felt slow; investment charts flat/wrong and change-over-time missing.
- **Root cause:** Net Worth open used daily-gated Plaid refresh only; investment balances were reconstructed from cash-flow transactions (market moves ignored); today's chart point could use stale snapshots; account detail recomputed full history on every render.
- **Fix:** `refreshAccountBalancesForDisplay` on Net Worth open; investment/brokerage history uses snapshots + live today balance only; pin today's point to `currentBalance`; cache account chart points in `AccountDetailView`; live row balances from linked accounts.
- **Verification:** Net Worth ↻ matches Plaid; investment detail shows snapshot-based history after daily refreshes; account navigation is instant (no network until pull).

### 2026-06-10 - Net worth refresh: daily auto + manual only
- **Symptom:** User wanted net worth updated once per day automatically and when refresh is pressed — not on every Net Worth screen open.
- **Root cause:** Net Worth `.task` always called Plaid on open; daily auto refresh only ran on unlock state change (missed next calendar day if app stayed open).
- **Fix:** App foreground runs daily-gated Plaid refresh + net worth reload; Net Worth open loads cached store data only; ↻ and pull-to-refresh call `refreshAccountsFromPlaid` + snapshot update.
- **Verification:** Same-day re-open shows cached totals; first open each day or ↻ pulls fresh Plaid balances and updates Today + chart snapshot.

### 2026-06-10 — Plaid Investments sync + richer brokerage history
- **Symptom:** Investment accounts showed flat or snapshot-only history; no holdings breakdown.
- **Root cause:** App only synced Plaid Transactions (spending), not Investments API (holdings + investment transactions).
- **Fix:** Migration `20260610120000_plaid_investments.sql`; shared `plaid-investments-sync.ts` + `plaid-sync-investments`; link token adds `investments` product; iOS `InvestmentStore`, `InvestmentHistoryEngine`, holdings/activity in `AccountDetailView`.
- **Verification:** Deploy backend; enable Investments on Plaid product; reconnect or refresh — account detail shows holdings list and activity-based chart when investment transactions sync.

### 2026-06-10 — Net Worth tab lag and jagged chart
- **Symptom:** Net Worth tab felt extremely laggy on open; chart spiked up/down sporadically between days.
- **Root cause:** Tab `.task` refetched snapshots on every open; chart recomputed full transaction reconstruction for all accounts on every SwiftUI render; sparse per-account dates were summed without forward-fill (investment snapshot days missing on other dates); saved net worth snapshots were overridden by bad estimates; Catmull-Rom interpolation overshot between points.
- **Fix:** Cache chart series in `NetWorthStore`; remove Net Worth open network reload; prefer saved net worth snapshots over estimates; forward-fill account balances before summing; linear chart interpolation.
- **Verification:** Net Worth tab opens instantly from cache; chart line is smooth and monotonic between snapshot days; ↻ refresh still updates totals and chart.

### 2026-06-30 — Stale transactions and launch lag
- **Symptom:** Latest transaction stuck at 6/11 while user kept opening the app; UI felt sluggish for several minutes after unlock.
- **Root cause:** App unlock only reloaded rows from Supabase (`loadAll`) and never called Plaid/Teller sync unless the user tapped sync manually. Startup also ran account refresh, net worth, investments, budgets, and rules sequentially on the main actor with loading spinners.
- **Fix:** `TransactionSyncPolicy` + `syncIfNeeded` auto-sync when connections exist and data is stale (30+ min since last client sync, server `last_sync_at` > 6h, or newest txn > 48h). Run sync + daily Plaid refresh in a background task after cached data paints; parallelize `loadAll` fetches and secondary store reloads; suppress startup loading spinners.
- **Verification:** Open app after multi-day gap → transactions update within ~1 min without manual sync; unlock UI responsive immediately; pull-to-refresh on Transactions still forces sync; `TransactionSyncPolicyTests` pass.

### 2026-06-30 — Launch freeze + stale sync after 6/11
- **Symptom:** App still froze for a few seconds on open; transactions stuck at 6/11 despite active bank connections.
- **Root cause:** Startup awaited net worth/budget network work before bank sync started; successful syncs with 0 rows still recorded `lastSyncAt`, blocking retries.
- **Fix:** Loading overlay during bootstrap + transaction sync; sync immediately after DB load when stale; defer investments/net-worth fetch; only record client sync when rows arrive or data is fresh; surface sync errors on Transactions tab.
- **Verification:** Open app → see "Loading/Syncing" overlay instead of frozen UI; stale accounts pull post-6/11 txns after deploy + open; `TransactionSyncPolicyTests` pass.

### 2026-06-30 — Plaid refresh-before-sync broke bank sync (stuck at 6/11)
- **Symptom:** Accounts showed active but newest transaction stayed 2026-06-11; pull-to-refresh did not advance dates.
- **Root cause:** Server called Plaid `/transactions/refresh` immediately before `/transactions/sync` for stale items; Plaid returned `INTERNAL_SERVER_ERROR` and sync aborted. DB backfill via direct `/transactions/sync` returned rows through 2026-06-29. iOS `sync()` skipped `loadAll` when the edge function failed, so pull-to-refresh never re-read Supabase even after server backfill.
- **Fix:** Remove pre-sync refresh from `plaid-sync.ts`; redeploy sync functions; run `scripts/force-plaid-sync-for-user.mjs`; always `loadAll` after sync attempts on iOS; paginate `fetchTransactions` past PostgREST 1000-row cap; reload when Transactions tab appears.
- **Verification:** Production DB newest `date` is 2026-06-29; force-quit + reopen or pull-to-refresh shows June transactions; `last_sync_at` updates on plaid_items.

### 2026-06-30 — Uncategorized Other after emergency Plaid backfill
- **Symptom:** New June transactions appeared but every category showed `Other`.
- **Root cause:** `scripts/force-plaid-sync-for-user.mjs` upserted rows with hardcoded `category: Other` / `category_source: plaid`, bypassing `categorizeTransaction`. Separately, `categorization.ts` imported transfer helpers from `merchant-similarity.ts` (wrong module), causing `BOOT_ERROR` on all sync/recategorize edge functions. Gemini quota was also exhausted, so unknown merchants could not fall back to AI.
- **Fix:** Add `recategorize-transactions` edge function + run `scripts/recategorize-user-transactions.mjs`; auto-recategorize after `aggregation-sync-transactions`; match merchant patterns against both `merchant_name` and `name`; expand `merchant_db` + transfer heuristics; fix categorization imports from `transfer-heuristics.ts`.
- **Verification:** Recategorize pass updates June rows to Groceries/Dining/Transfers/etc.; pull-to-refresh runs recategorize on iOS; edge functions boot successfully.

### 2026-06-30 — Pre-ship edge cases (sync overlap, foreground lag)
- **Symptom:** Risk of duplicate Plaid syncs when manual refresh overlapped auto-sync; every foreground transition re-fetched all transactions.
- **Root cause:** `sync()` and `syncIfNeeded()` could run concurrently; `refreshDailyNetWorthIfNeeded` called `loadAll` on every `scenePhase == .active`.
- **Fix:** `TransactionStore.runBackgroundMaintenance` coalesces auto sync + daily Plaid refresh; manual `sync()` awaits in-flight maintenance; skip auto-sync when `isSyncing`; foreground only runs gated maintenance (no full reload). ISO8601 `last_sync_at` parsing tries fractional and non-fractional timestamps.
- **Verification:** `TransactionSyncPolicyTests`, `BudgetAlertEngineTests`, Codemagic unit tests; build 53.

### 2026-06-30 — CI compile break after Goals tab removal
- **Symptom:** Codemagic unit tests failed with `cannot find type 'NetWorthStore' in scope` and `cannot find type 'SupabaseClient' in scope`.
- **Root cause:** `NetWorthStore` and `NetWorthCalculator` lived in deleted `GoalsStore.swift` / `GoalsMath.swift`; `BudgetTrackerApp.refreshDerivedFinancialData` used `SupabaseClient` without `import Supabase`.
- **Fix:** Extract `NetWorthStore.swift` and `NetWorthCalculator.swift` under `Backend/Finance/`; add `import Supabase` to `BudgetTrackerApp.swift`.
- **Verification:** Codemagic `run-unit-tests` compiles and passes; build 53 uploads to ASC.

### 2026-06-30 — ASC upload fails with altool bundle ID lookup (Xcode 26)
- **Symptom:** Codemagic IPA build succeeded but publishing failed: `Cannot determine the Apple ID from Bundle ID 'com.optimized.budgettracker'`.
- **Root cause:** Xcode 26 `altool` mis-resolves Apple ID when multiple apps share the `com.optimized.*` bundle prefix (Budget Tracker + Optimized).
- **Fix:** Set `APP_STORE_CONNECT_ALTOOL_ADDITIONAL_ARGUMENTS: '--apple-id "6775334574"'` in `codemagic.yaml` workflow vars.
- **Verification:** Codemagic publishing step uploads IPA to App Store Connect.

### 2026-06-30 — Net worth chart low start, June spike, one-day dip
- **Symptom:** Chart started near zero, jumped to normal levels in June when investment accounts appeared, then showed an isolated one-day crater before recovering.
- **Root cause:** Per-account history only counted balances after each account’s first snapshot (partial portfolio before June); a bad saved `net_worth_snapshots` row could override a good account-based estimate; single-day snapshot glitches were plotted verbatim.
- **Fix:** Build account history first with `backfillLeadingBalances` (assume first known balance before first observation); merge snapshots via `shouldTrustSnapshot` (reject isolated low dips, keep snapshots that reflect full portfolio); `smoothIsolatedOutliers` interpolates V-shaped one-day glitches; tests in `NetWorthHistoryEngineTests`.
- **Verification:** Net Worth 1M chart is flat at current level before investment link date; no June vertical jump; no single-day dip; unit tests pass on CI.

### 2026-06-30 — App lag after net worth chart fix; budget wheel + totals mismatch
- **Symptom:** Entire app felt extremely laggy after build 54; budget semi-circle drew incorrectly; Dashboard “Spent” total differed from Budgets tab.
- **Root cause:** `NetWorthStore.rebuildChartCache()` ran all six chart ranges synchronously on the main actor on every transaction/account update; full-screen loading overlay blocked UI during background sync; duplicate `noteTransactionsChanged` calls; Dashboard used budgeted-only `progress` while Budgets tab used `displayMonthSections` spending rows; half-wheel angles used `180 - fraction*180` (bottom arc) instead of `180 + fraction*180` (top arc).
- **Fix:** Debounced off-main chart rebuild in `NetWorthStore`; overlay only during bootstrap (not sync); defer auto-sync to background task after first paint; unify Dashboard chart on `spendingProgress`; fix semi-circle geometry and center total to use `listDisplaySpent`.
- **Verification:** Unlock UI responsive immediately; sync runs without blocking overlay; Dashboard and Budgets tab show matching spent total; top semi-circle renders and taps correctly.

### 2026-06-30 — Budget semi-circle grey with hairline slices
- **Symptom:** Half-wheel showed mostly grey with barely visible category slivers after Canvas rewrite.
- **Root cause:** Slice fractions used a mismatched denominator (`sliceTotal` from a filtered/consolidated subset vs amounts from individual rows); grey track filled the semicircle behind slices that only covered a partial arc; floating-point gaps between wedges.
- **Fix:** `BudgetMath.chartSliceSegments` computes normalized fractions from the same amounts used to draw each slice (last segment pinned to `endFraction = 1`); removed category cap/consolidation and grey under-fill when data exists.
- **Verification:** Budget/Dashboard wheel shows bold colored segments on grey track; tap selection works; totals unchanged.
