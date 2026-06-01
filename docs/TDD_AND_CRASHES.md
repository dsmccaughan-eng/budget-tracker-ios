# TDD gate and crash diagnostics

Last updated: 2026-06-01

## Test-driven pre-ship gate (same idea as Optimized)

Before TestFlight, confirm backend logic and launch guards — **do not ship on guesswork**.

| Step | Where | Command |
|------|--------|---------|
| Line budget | Windows / Mac | `powershell -File scripts/check-file-line-limits.ps1` |
| Full Windows gate | Windows | `powershell -File scripts/pre-ship-gate.ps1` |
| Resolve packages | Mac / Codemagic | `xcodebuild -project BudgetTracker.xcodeproj -scheme BudgetTracker -resolvePackageDependencies` |
| Supabase ≥ 2.44.0 | Mac / Codemagic | `bash scripts/verify-supabase-package.sh` |
| Unit tests | Mac / Codemagic | `bash scripts/run-unit-tests.sh` |

Codemagic runs **Verify supabase-swift version**, **Run unit tests**, then archives the IPA.

### What the tests guard

| Test suite | Guards |
|------------|--------|
| `APIKeysTests` | Rejects `$(…)` / `YOUR_*` placeholders |
| `SupabaseConfigTests` | HTTPS URL has resolvable host (iOS 26-safe) |
| `AuthStoreTests` | No Supabase client in `init`; bootstrap without keys → unauthenticated; `SupabaseClient` init does not trap |
| `LaunchReadinessTests` | Budget alert threshold (0.8), cash-flow prefix math |
| `BudgetMathTests`, `GoalsEngineTests`, `CategorizationEngineTests` | Finance domain regressions |

When changing a threshold or constant in production code, **update the matching test first** (see `LaunchReadinessTests`).

## Crash logs in Xcode (TestFlight / device)

Apple’s message “details can be found in Xcode” means **Organizer**, not only the ASC website.

1. Open **Xcode** on your Mac (signed in with the same Apple ID as App Store Connect).
2. **Window → Organizer** (or **Xcode → Settings → Accounts** → your team → **Download Manual Profiles** if symbols are missing).
3. Select **Crashes** in the left sidebar.
4. Choose **Budget Tracker** and the build that crashed.
5. Open a crash report — stack traces are symbolicated when Xcode has the matching **dSYM** from the archive (Codemagic artifacts or your local `build/BudgetTracker.xcarchive`).

Alternative paths:

- **Devices and Simulators**: connect device → **View Device Logs**.
- **App Store Connect** → TestFlight → build → **Crashes** (may lag; API often returns 0 until Apple ingests).
- Repo helper: `node scripts/fetch-asc-crashes.mjs` (needs ASC API key in `signing/`).

### Known launch crash (2026-06-01)

If the top frame is `SupabaseClient.init` + `URL.host` force-unwrap on **iOS 26**, pin **supabase-swift 2.44.0+** and re-run `AuthStoreTests` / `verify-supabase-package.sh`. See `LESSONS_LEARNED.md`.

## Agent rule

Do **not** trigger Codemagic/TestFlight until:

1. `pre-ship-gate.ps1` passes on Windows.
2. Mac/Codemagic unit tests and Supabase package verify pass.
3. User explicitly approves a new build after reviewing crash status in Xcode Organizer.
