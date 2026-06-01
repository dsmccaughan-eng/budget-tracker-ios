# Budget Tracker iOS App — Full Project Brief (Cursor Agent Handoff)

You are a senior iOS engineer and backend architect picking up a project that has been fully planned. **Do not re-ask for information provided here.** **Do not suggest alternatives to decisions already made** unless you find a blocking contradiction — then state the blocker and the smallest fix.

**Agent read order:**

1. `AI_PROJECT_INSTRUCTIONS.txt` — product rules, engineering standards, update log (append when behavior ships)  
2. `LESSONS_LEARNED.md` — resolved issues ledger (**append after every non-trivial fix**; do not rewrite old entries)  
3. This file (`docs/PROJECT_BRIEF.md`) — full scope, models, phases  
4. `Config/SECRETS.local.md` — credentials (gitignored)

**Never commit** secrets, `service_role` keys, Plaid secrets, or app-specific passwords.

**Workspace:** `c:\Users\dsmcc\Projects\Users\m1\Desktop\BudgetTracker`  
**Reference implementation (patterns only):** `c:\Users\dsmcc\Projects\Users\m1\Desktop\Optimized` (repo: `dsmccaughan-eng/optimized-ios`) — signing and `pkg.xcconfig` live inside that repo, not on the parent Desktop.

---

## Project Overview

A personal iOS budget tracking app with automatic bank transaction sync via **Plaid**, AI-powered categorization via **Google Gemini**, receipt scanning, savings goals, net worth tracking, and smart spending insights.

- **Users:** personal use only (~1 user, Dylan)
- **Distribution:** TestFlight (no App Store approval required)
- **Privacy:** financial data — treat as highest sensitivity

---

## Product North Star (from Optimized / life-optimization vision)

1. **Reliability first** — no silent failures; expose actionable errors; never lose user corrections (categories, rules, splits).
2. **Low-friction automation** — sync, categorize, and surface insights with minimal taps; good defaults over forms.
3. **Practical AI** — Gemini for unknown merchants, receipts, and narratives; **deterministic fallbacks** (merchant DB → user rules → Plaid category) when AI fails.
4. **Incremental delivery** — smallest safe change; verify each phase before the next (Edge Functions before iOS, compile before features).

Dylan has no prior coding experience — explain **what** and **why** in plain English before large changes.

---

## Tech Stack (decisions locked)

| Layer | Choice |
|--------|--------|
| iOS | Swift 5.9+, SwiftUI, iOS 17+ deployment target |
| Xcode | **16.x on CI** (Optimized uses Xcode 16.3 on `macos-15` runners). Local brief may say “Xcode 26” — match **whatever version GitHub `macos-*` images provide** at build time; pin in workflow with `xcode-select`. |
| Project gen | **XcodeGen** (`project.yml` = source of truth) — same as Optimized |
| Backend | **Supabase** — **dedicated project** `dldbcbituquxedlkeefu` (NOT the fitness app database) |
| Bank sync | **Plaid** Sandbox → Development when ready for real banks |
| AI | **Gemini 1.5 Flash** — categorization, receipt parsing, insights (iOS + Edge Functions as needed) |
| Auth | Supabase Auth (`auth.uid()` RLS on all user tables) |
| CI / TestFlight | **Xcode Cloud** (Apple Developer; no Mac). **GitHub = backup only** — see `../Optimized/docs/GITHUB_POLICY.md` and `../Optimized/docs/XCODE_CLOUD_RELEASE.md`. |
| Version control | GitHub `dsmccaughan-eng/budget-tracker` (private) |

### Swift Package Dependencies

- **Plaid Link (SPM):** `https://github.com/plaid/plaid-link-ios-spm.git` — import **LinkKit** (do NOT use main `plaid-link-ios` repo — ~1GB).
- **Supabase:** `https://github.com/supabase/supabase-swift`

---

## Credentials & Secret Handling

### Where values live

| Secret | iOS app | Supabase Edge Functions | GitHub Actions |
|--------|---------|-------------------------|----------------|
| Plaid `client_id` | Never | Vault / env | `PLAID_CLIENT_ID` |
| Plaid `secret` | **Never** | Vault / env only | `PLAID_SECRET` |
| Plaid `access_token` | **Never** | Supabase Vault only | Never |
| Supabase `anon` key | Yes (public) | — | Optional |
| Supabase `service_role` | **Never** | Edge Functions only | Never in iOS |
| Gemini API key | Yes (see APIKeys) | Optional server-side | `GEMINI_API_KEY` |

**Canonical local file:** `Config/SECRETS.local.md` (gitignored).

### Plaid (sandbox)

- Environment: `sandbox`
- Test login: `user_good` / `pass_good`
- Endpoints base: `https://sandbox.plaid.com/`

### Supabase

- Project ref: `dldbcbituquxedlkeefu`
- URL: `https://dldbcbituquxedlkeefu.supabase.co`
- Keys: see `SECRETS.local.md`
- **Separate from** Optimized Supabase — no shared tables, no shared Edge Function deploy target

### Gemini

- Model: `gemini-1.5-flash`
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent`
- Free tier limits: ~1500 req/day, 15 req/min — batch categorization on sync; cache rules to minimize calls

### Apple (shared with Optimized)

- **Team ID:** `CHHWVGCKG4`
- **Apple ID:** `dsmccaughan@gmail.com`
- Distribution identity: `Apple Distribution: Dylan McCaughan (CHHWVGCKG4)`
- App-specific password: in `SECRETS.local.md` — for `altool` / ASC upload only; store in GitHub Secrets for CI
- **Issuer ID (ASC API):** `aac249cb-4e46-49a0-832f-446a6bdba91d` (from Optimized ship docs — reuse for App Store Connect API if using `api_key` upload path)

### API key resolution in iOS (copy Optimized pattern)

Implement `BudgetTracker/Backend/Core/APIKeys.swift` like Optimized’s `APIKeys.swift`:

1. User override in Settings (UserDefaults + “user provided” flag) — highest precedence  
2. Environment variable  
3. `Info.plist` (injected via `pkg.xcconfig` at archive / CI)  
4. `LocalAPIKeys.plist` — **DEBUG builds only** (`#if DEBUG`), gitignored  
5. Reject placeholders containing `$(…)`, `YOUR_*`, or empty strings  

Copy `Config/LocalAPIKeys.plist.example` → `Config/LocalAPIKeys.plist` for local Simulator runs.

**Release / TestFlight:** inject `GEMINI_API_KEY` and Supabase anon via `pkg.xcconfig` + `scripts/ci-write-pkg-xcconfig.sh` pattern from Optimized — not bundled plist in Release.

---

## Security Architecture — Non-Negotiable

```
iOS App → Supabase Edge Function → Plaid API → Bank
```

- **Never** call Plaid API directly from iOS  
- **Never** store `access_token` in iOS, Keychain, or UserDefaults  
- **Never** store full account numbers — **last 4 digits** (`mask`) only  
- **Never** put Plaid `client_secret` in any iOS file or committed repo file  
- Plaid `access_token` lives in **Supabase Vault** only  
- **Face ID / Touch ID** required before showing any financial screen (LocalAuthentication)  
- `NSAllowsArbitraryLoads` = **false** in Info.plist  
- All third-party credentials via `APIKeys` + gitignored plists — **not** hardcoded in Swift  
- **Rotate** any credential that was pasted into chat, committed, or logged  

---

## Database — Already Created (do not recreate base tables)

Existing tables in Supabase with RLS: `auth.uid() = user_id`.

| Table | Purpose |
|-------|---------|
| `accounts` | Linked bank/investment accounts (`mask` = last 4 only) |
| `transactions` | Transactions with category |
| `budgets` | Monthly limits per category |
| `plaid_items` | Plaid item IDs (tokens in Vault, not in row) |

### Additional tables to create

- `savings_goals` — name, target, monthly contribution, target date, linked account  
- `merchant_rules` — user rules: merchant substring → category  
- `merchant_db` — ~500 curated merchants + categories (seed data)  
- `price_history` — item, price, merchant, date (from receipts)  
- `net_worth_snapshots` — monthly snapshots for trend chart  

Use migrations under `supabase/migrations/`; verify RLS on every new table.

---

## Supabase Edge Functions — 4 Required

Deploy to project `dldbcbituquxedlkeefu`. Store Plaid secret and service role in Supabase secrets / Vault — not in repo.

### 1. `plaid-create-link-token`

- Plaid: `POST /link/token/create`  
- Returns: `link_token` for iOS LinkKit  

### 2. `plaid-exchange-token`

- Input: `public_token` from iOS after Link  
- Plaid: `POST /item/public_token/exchange`  
- Store `access_token` in **Vault**; insert `plaid_item_id` into `plaid_items`  
- iOS **never** receives `access_token`  

### 3. `plaid-sync-transactions`

- Load `access_token` from Vault  
- Plaid: `POST /transactions/sync`  
- Upsert `transactions`; run categorization pipeline for uncategorized rows  

### 4. `plaid-get-accounts`

- Plaid: `POST /accounts/get`  
- Return account list for UI  

**Categorization on sync (server-side preferred for secret safety):**

1. `merchant_rules` (user)  
2. `merchant_db` (curated)  
3. Gemini JSON categorization  
4. Fallback: Plaid raw category  

---

## Full Feature Scope

(Unchanged from product spec — implement in build order below.)

1. Account connectivity (Plaid + manual)  
2. Transaction categorization (17 categories + splits + learning rules)  
3. Budget goals (limits, rollover, projected spend, fixed vs flexible)  
4. Savings goals (incl. emergency fund from spending history)  
5. Notifications & alerts (configurable)  
6. Net worth tracking + snapshots  
7. Receipt scanning (Gemini Vision)  
8. Price history from receipts  
9. Debt payoff tracker  
10. Cash flow calendar (30/60/90)  
11. Custom categorization rules UI  
12. AI insights (weekly/monthly, subscription audit, anomalies)  

### Categories (locked)

`Housing & Utilities`, `Groceries`, `Dining & Bars`, `Transport`, `Shopping`, `Health & Wellness`, `Travel`, `Entertainment`, `Subscriptions`, `Personal Care`, `Education`, `Pets`, `Gifts & Donations`, `Business`, `Income`, `Transfers`, `Other`

---

## iOS App Structure

### Tabs (5)

| Tab | Content |
|-----|---------|
| Dashboard | Net worth, budget ring, recent txns, alerts |
| Transactions | List, search, filters, receipt scan |
| Budgets | Progress bars, projected spend, history |
| Goals | Savings, debt payoff, cash flow calendar |
| Insights | AI summaries, price history, subscription audit |

### Key views

`DashboardView`, `TransactionListView`, `TransactionDetailView`, `SplitTransactionView`, `BudgetView`, `AddBudgetView`, `BudgetHistoryView`, `GoalsView`, `AddSavingsGoalView`, `DebtPayoffView`, `CashFlowCalendarView`, `InsightsView`, `PriceHistoryView`, `SubscriptionAuditView`, `AccountsView`, `PlaidLinkView`, `NetWorthView`, `ReceiptScanView`, `SettingsView`, `NotificationSettingsView`, `CategoryRulesView`

### Suggested bundle ID

`com.budgettracker.app` (or `com.dsmccaughan.budgettracker`) — **must not** reuse `com.optimizedapp.app`

---

## Engineering Standards (from Optimized — apply here)

### Backend layout

```
BudgetTracker/
  BudgetTracker/           # app target sources (XcodeGen path)
    Backend/
      AI/                  # Gemini client, JSON normalizers (see Optimized Backend/AI)
      Auth/                # Supabase session
      Cloud/               # SupabaseService (CRUD, RPC, Edge Function invoke)
      Core/                # APIKeys, config
      Finance/             # BudgetStore, TransactionStore, Categorization, Goals
      Plaid/               # Link UI bridge only — no secret-bearing API calls
    Models/                # Codable types
    Views/                 # SwiftUI by feature
    App/                   # @main, auth gate, Face ID shell
  BudgetTrackerTests/
    Backend/<domain>/      # TDD unit tests — write tests first for pure logic
```

- Target **≤ 400 lines** per Swift file; hard stop **500** (`scripts/check-file-line-limits.ps1`)  
- Split large stores into `*PersistenceStore.swift` + `*Store+<Feature>.swift` extensions  
- **No** monolithic `Services/` folder  

### TDD

- New categorization, budget math, debt/cash-flow logic → tests in `BudgetTrackerTests/Backend/<domain>/` **first**  
- Guard thresholds (e.g. alert percentages) with explicit tests  

### AI JSON handling (from Optimized)

- Use a shared `AIResponseNormalizer` pattern: extract JSON block, parse with `Codable`, validate category enum  
- Prompts: **return ONLY valid JSON**; system + user messages as in Gemini section below  
- Receipt images: base64 to Gemini Vision; handle failures with user-visible message  

### Regenerate Xcode project (no Mac required)

1. Edit `project.yml` and Swift under `BudgetTracker/`  
2. `git push`  
3. Run GitHub Actions **Verify compile** (`workflow_dispatch`) — mirrors Optimized  
4. TestFlight workflow when signing secrets configured  

---

## Data Models (Swift)

```swift
struct Transaction: Codable, Identifiable {
    var id: UUID
    var accountId: UUID
    var plaidTransactionId: String
    var amount: Double
    var date: String
    var merchantName: String?
    var name: String
    var category: String
    var subcategory: String?
    var pending: Bool
    var isManual: Bool          // receipt / manual entry
    var splitItems: [SplitItem]?
}

struct SplitItem: Codable {
    var category: String
    var amount: Double
    var note: String?
}

struct Account: Codable, Identifiable {
    var id: UUID
    var plaidItemId: String
    var plaidAccountId: String
    var name: String
    var officialName: String?
    var type: String            // depository, investment, credit, loan
    var subtype: String?
    var mask: String?           // last 4 only
    var currentBalance: Double?
    var availableBalance: Double?
}

struct Budget: Codable, Identifiable {
    var id: UUID
    var category: String
    var monthlyLimit: Double
    var color: String
    var isRollover: Bool
    var isFixed: Bool
}

struct SavingsGoal: Codable, Identifiable {
    var id: UUID
    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var monthlyContribution: Double
    var targetDate: String?
    var linkedAccountId: UUID?
    var emoji: String?
}

struct MerchantRule: Codable, Identifiable {
    var id: UUID
    var merchantContains: String
    var category: String
    var subcategory: String?
}

struct PriceHistoryItem: Codable, Identifiable {
    var id: UUID
    var itemName: String
    var price: Double
    var merchant: String
    var date: String
}

struct NetWorthSnapshot: Codable, Identifiable {
    var id: UUID
    var date: String
    var totalAssets: Double
    var totalLiabilities: Double
    var netWorth: Double
}
```

---

## Gemini Integration (prompts locked)

### Transaction categorization

**System:**  
`You are a transaction categorizer. Return ONLY valid JSON with 'category' and 'subcategory' fields. Category must be one of: [Housing & Utilities, Groceries, Dining & Bars, Transport, Shopping, Health & Wellness, Travel, Entertainment, Subscriptions, Personal Care, Education, Pets, Gifts & Donations, Business, Income, Transfers, Other]`

**User:**  
`Merchant: {name}, Amount: ${amount}, Raw category: {plaid_category}`

### Receipt scanning

**System:**  
`You are a receipt parser. Return ONLY valid JSON with fields: merchant (string), date (yyyy-MM-dd), items (array of {name, quantity, price, category}), subtotal, tax, total.`

**User:** `[base64 image]`

### Weekly insights

**System:**  
`You are a personal finance advisor. Be concise and specific. Return ONLY valid JSON with fields: summary (string), topInsight (string), suggestion (string), anomalies (array of strings).`

**User:**  
`Spending this week: {category breakdown JSON}. Budget limits: {budget JSON}. 3-month averages: {averages JSON}.`

---

## CI / TestFlight (Xcode Cloud — same policy as Optimized)

Owner is on **Windows** with **Apple Developer**. **GitHub is backup only**; do not use GitHub Actions macOS runners for TestFlight.

When the iOS app is ready to ship:

1. Follow **`../Optimized/docs/XCODE_CLOUD_RELEASE.md`** (connect repo, workflow, TestFlight internal testing).
2. Add `ci_scripts/` mirroring Optimized (`ci_post_clone.sh`, `ci_pre_xcodebuild.sh`).
3. Put release secrets (`GEMINI_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`) in **Xcode Cloud environment**, not GitHub Actions.
4. **Plaid secrets** stay in Supabase Edge Functions only.

### GitHub (this repo)

- `git push` for backup only.
- Optional: disable or stub any `.github/workflows/*` macOS jobs (see Optimized `.github/workflows/README.md`).

---

## Build Order (locked)

### Phase 1 — Backend (FIRST — no iOS until verified)

1. Install Supabase CLI on Windows (see First Task below)  
2. `supabase init` + `supabase link --project-ref dldbcbituquxedlkeefu`  
3. Create additional DB tables + migrations  
4. Seed `merchant_db` (~500 merchants)  
5. Deploy 4 Edge Functions  
6. Verify all functions against Plaid Sandbox (`user_good` / `pass_good`)  

### Phase 2 — iOS foundation

7. `project.yml` + XcodeGen; SPM: Plaid Link + Supabase  
8. `APIKeys.swift`, Face ID gate, auth shell, tab structure  
9. `verify-compile` workflow  

### Phase 3 — Core features

10. Accounts + Plaid Link flow (via Edge Functions only)  
11. Transaction list + sync + categorization  
12. Budget UI  

### Phase 4 — Goals & wealth

13. Savings goals  
14. Net worth + investments  
15. Debt payoff  

### Phase 5 — Smart features

16. Receipt scanning  
17. Notifications  
18. Cash flow calendar  
19. Rules manager  
20. Price history  

### Phase 6 — Insights

21. Weekly/monthly AI insights  
22. Subscription audit  
23. Optimization suggestions  

---

## Development Principles

- Maintain **`AI_PROJECT_INSTRUCTIONS.txt`** and **`LESSONS_LEARNED.md`** like the Optimized fitness app — brief for spec, those files for ongoing agent memory  
- Smallest safe change first — verify each step before the next  
- Never expose credentials in git  
- All Plaid **secret** calls on Edge Functions — no exceptions  
- Face ID gate on every cold open to financial UI  
- Test Plaid Sandbox before Development environment  
- Explain approach in plain English before writing code  
- Prefer **complete file writes** for new files; minimal diffs for small fixes  
- Copy proven patterns from `../Optimized/` (APIKeys, Supabase client, Gemini JSON, GHA, XcodeGen) — do not copy fitness domain code or Supabase project  

---

## First Task (agent start here)

**Do not write iOS code until all four Edge Functions pass Sandbox tests.**

### Install Supabase CLI (Windows)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
supabase --version
```

### Login and link

1. Create a Personal Access Token at https://supabase.com/dashboard/account/tokens — name `budget-tracker-cli`  
2. Run:

```powershell
cd c:\Users\dsmcc\Projects\Users\m1\Desktop\BudgetTracker
supabase login --token <YOUR_PAT>
supabase init
supabase link --project-ref dldbcbituquxedlkeefu
```

3. Paste `supabase link` output before creating migrations or deploying functions.  
4. Add Edge Function secrets (Plaid client id/secret) via Supabase dashboard or CLI — values from `Config/SECRETS.local.md`.  
5. Deploy and curl-test each function with a test user JWT.

---

## Budget Tracker agent docs (this repo)

| File | Role |
|------|------|
| `AI_PROJECT_INSTRUCTIONS.txt` | Living rules, security, update log |
| `LESSONS_LEARNED.md` | Resolved bugs — append after each fix |
| `docs/PROJECT_BRIEF.md` | Full spec (this file) |

## Optimized Cross-Reference Cheat Sheet

| Topic | Optimized location |
|-------|-------------------|
| API key resolution | `Optimized/Backend/Core/APIKeys.swift` |
| Gemini + JSON | `Optimized/Backend/AI/GeminiService.swift`, `AIResponseNormalizer` |
| Supabase client | `Optimized/Backend/Cloud/SupabaseService.swift` |
| XcodeGen | `Optimized/project.yml` |
| Verify compile CI | `Optimized/.github/workflows/verify-compile.yml` |
| TestFlight CI | `Optimized/.github/workflows/testflight.yml` |
| Engineering rules | `Optimized/AI_PROJECT_INSTRUCTIONS.txt`, `.cursor/rules/engineering-standards.mdc` |
| Line limit script | `Optimized/scripts/check-file-line-limits.ps1` |
| Agent safety | `Optimized/.cursor/rules/agent-run-everything-safety.mdc` |

**Do not share** Supabase projects, bundle IDs, or signing profiles between apps.

---

## Security reminder

Credentials were provided in an earlier Claude handoff. **Assume they may be exposed** — rotate Plaid secret, Supabase `service_role`, Gemini key, and Apple app-specific password after first successful Sandbox test if this chat or any file was shared broadly. Never commit `Config/SECRETS.local.md` or `LocalAPIKeys.plist`.

---

*Brief version: 2026-05-30 — merged original Budget Tracker spec with Optimized iOS engineering, CI, and security patterns.*
