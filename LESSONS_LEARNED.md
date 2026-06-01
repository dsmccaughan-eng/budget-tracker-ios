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

<!-- Append new entries above this line -->
