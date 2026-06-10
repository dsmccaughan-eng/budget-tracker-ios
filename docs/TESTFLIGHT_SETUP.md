# Budget Tracker — first TestFlight build

Same pipeline as Optimized (Codemagic + manual signing). Budget Tracker is **not** on Codemagic or App Store Connect yet.

## Checklist

### A. App Store Connect (~10 min, browser)

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+** → App IDs → `com.budgettracker.app` (Budget Tracker).
2. [App Store Connect](https://appstoreconnect.apple.com/apps) → **+** → New App → iOS → **Budget Tracker** → bundle `com.budgettracker.app` → SKU e.g. `budgettracker-ios`.
3. [Profiles](https://developer.apple.com/account/resources/profiles/list) → **+** → **App Store** → name **Budget Tracker Distribution** → app ID above → **Apple Distribution: Dylan McCaughan (CHHWVGCKG4)**.
4. Copy the app’s **Apple ID** (numeric, App Information) → set `ascAppId` in `ios-app.config.json`.

### B. GitHub

```powershell
cd C:\Users\dsmcc\Projects\Users\m1\Desktop\BudgetTracker
git init
git branch -M main
# Create empty private repo: dsmccaughan-eng/budget-tracker-ios on GitHub
git remote add origin https://github.com/dsmccaughan-eng/budget-tracker-ios.git
git add -A
git commit -m "Initial Budget Tracker iOS"
git push -u origin main
```

### C. Codemagic

1. [Codemagic](https://codemagic.io/apps) → **Add application** → GitHub → **budget-tracker-ios** → enable **budgettracker-testflight** workflow (`codemagic.yaml`).
2. Note **Application ID** and create variable group **budgettracker_secrets**; note **group ID**.
3. Update `ios-build/apps/budgettracker.json`:

```json
"ascAppId": "<numeric Apple ID>",
"codemagic": {
  "appId": "<Codemagic app _id>",
  "groupId": "<variable group id>",
  ...
}
```

4. From Desktop: `.\ios-build\sync-to-repos.ps1` then commit/push `codemagic.yaml` if it changed.

### D. Secrets (reuse Optimized distribution cert)

```powershell
cd C:\Users\dsmcc\Projects\Users\m1\Desktop\BudgetTracker
Copy-Item ..\Optimized\signing\certs\AuthKey_N99V63R65U.p8 signing\certs\ -Force
node scripts/download-asc-profiles.mjs

$env:CM_P12_PATH = "<same distribution.p12 as Optimized>"
$env:CM_P12_PASSWORD = "<same password>"
node scripts/upload-codemagic-signing-secrets.mjs
```

In Codemagic UI for **budgettracker_secrets**, also add (from `Config/SECRETS.local.md`):

- `GEMINI_API_KEY`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY` (copy from **optimized_secrets**)

### E. Build

```powershell
$env:CM_SKIP_GITHUB_CHECK = "1"
node scripts/validate-codemagic-prereqs.mjs
node scripts/trigger-codemagic-build.mjs
```

IPA uploads to App Store Connect when signing secrets and API keys are correct.

### F. TestFlight Test Information (required once — usually in browser)

**Symptom:** Codemagic “distribution failed,” or TestFlight → Test Information won’t save / looks empty, or the TestFlight iPhone app shows no build.

**Checks (API):**

```powershell
node scripts/setup-asc-testflight-info.mjs --inspect
node scripts/fetch-asc-crashes.mjs   # lists processed builds
```

| API field | Meaning |
|-----------|---------|
| `betaAppLocalizations` count **0** | Test Information has no language yet — web UI often cannot save until you complete the form once as **Account Holder** or **Admin** |
| `internalBuildState: READY_FOR_BETA_TESTING` | Build **is** on TestFlight for **internal** team members (App Store Connect users) |
| `externalBuildState: READY_FOR_BETA_SUBMISSION` | External testers blocked until Test Information + review contact exist |
| API key `POST betaAppLocalizations` → **403** | Key `N99V63R65U` can upload IPAs but **cannot** edit Test Information — use browser or regenerate key as **Admin** / **App Manager** |

**Fill in (browser, ~2 min):** [TestFlight → Test Information](https://appstoreconnect.apple.com/apps/6775334574/testflight/test-info)

1. Language: **English (U.S.)** (app primary locale).
2. **Beta App Description** (required): e.g. `Personal finance and budget tracking with Plaid sync, budgets, and net worth.`
3. **Feedback Email:** `dsmccaughan@gmail.com`
4. **Beta App Review Information:** Dylan McCaughan, your phone (E.164, e.g. `+1…`), `dsmccaughan@gmail.com`

**Install internally (no external review):**

1. [Users and Access](https://appstoreconnect.apple.com/access/users) — your Apple ID must be on the team with access to this app.
2. On iPhone: TestFlight app, signed in as **dsmccaughan@gmail.com** → **Optimized Budget Tracker** → build **32** (or latest).
3. Internal group **Budget Testers** already exists; internal builds with `hasAccessToAllBuilds` do not need manual build assignment.

**Automation (after Admin API key or Test Information exists):**

```powershell
$env:ASC_CONTACT_PHONE = "+1XXXXXXXXXX"   # your real number
node scripts/setup-asc-testflight-info.mjs
```

Then set `submit_to_testflight: true` in `codemagic.yaml` if you want Codemagic to submit external beta review on future builds.

## Helper script

```powershell
powershell -File scripts/setup-testflight.ps1
```

After ASC app exists:

```powershell
powershell -File scripts/setup-testflight.ps1 -AscAppId "1234567890" -CodemagicAppId "..." -CodemagicGroupId "..."
```
