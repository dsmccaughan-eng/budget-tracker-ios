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

### F. TestFlight Beta App Information (required once)

If Codemagic logs **“App Store Connect distribution failed”** but **Build IPA** succeeded, the binary is usually already on TestFlight. Apple blocked **external** beta submission because contact info is missing.

In [App Store Connect → TestFlight → Test Information](https://appstoreconnect.apple.com/apps/6775334574/testflight/test-info) fill in:

| Section | Required fields |
|--------|------------------|
| **Beta App Information** | Feedback email |
| **Beta App Review Information** | First name, last name, phone, email |

Then in **TestFlight → iOS builds**, open the latest build → add **Internal Testing** testers (your Apple ID) or submit for external testing.

After that is saved, you can set `submit_to_testflight: true` in `codemagic.yaml` if you want Codemagic to auto-submit for beta review on future builds.

## Helper script

```powershell
powershell -File scripts/setup-testflight.ps1
```

After ASC app exists:

```powershell
powershell -File scripts/setup-testflight.ps1 -AscAppId "1234567890" -CodemagicAppId "..." -CodemagicGroupId "..."
```
