# Codemagic — TestFlight (shared playbook)

Synced into each app repo from `Desktop/ios-build`. App-specific IDs live in `ios-app.config.json`.

## Two failure modes

| Symptom | Cause | Fix |
|--------|--------|-----|
| **Prepare machine slow / timeout** (~2 min+ or ~10 min) | VM flake; GitHub disconnected on private repo | Cancel if prepare > ~45s; retry once; reconnect GitHub on app |
| **Signing / archive errors** | Wrong .p12 vs profiles; compile errors | Matching `.p12`; fix Swift; see build log |

## Rules (save macOS minutes)

1. **No push auto-builds** until CI is green — manual `node scripts/trigger-codemagic-build.mjs` only.
2. **Preflight locally:** `node scripts/validate-codemagic-prereqs.mjs`
3. **One macOS build at a time**
4. Pre-IPA script steps timeout at **60s** (`CM_PRE_IPA_STEP_TIMEOUT_SEC`)

## One-time per app

1. Create Codemagic app → set `codemagic.appId` and `codemagic.groupId` in `ios-build/apps/<slug>.json`, run `sync-to-repos.ps1`.
2. Reconnect **GitHub** on the Codemagic app.
3. Upload matching Distribution `.p12` + profiles:

```powershell
cd <AppFolder>
node scripts/download-asc-profiles.mjs
$env:CM_P12_PATH = "C:\path\to\distribution.p12"
$env:CM_P12_PASSWORD = "..."
node scripts/upload-codemagic-signing-secrets.mjs
```

4. ASC API keys in secrets group: `APP_STORE_CONNECT_*`, plus app API keys (`GEMINI_API_KEY`, etc.).

## Per-app config

| App | Config file |
|-----|-------------|
| Optimized | `ios-build/apps/optimized.json` |
| Budget Tracker | `ios-build/apps/budgettracker.json` |

After editing, run `.\ios-build\sync-to-repos.ps1` from Desktop.

## Optimized IDs (reference)

- App: `6a1cb0929bc1d9dc6be0f9f1`
- Workflow: `optimized-testflight`
- Group: `optimized_secrets` / `6a1cbc5391193fc76d2a0415`

Budget Tracker: fill IDs in `budgettracker.json` when Codemagic app exists.
