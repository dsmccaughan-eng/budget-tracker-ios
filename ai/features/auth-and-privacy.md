# Feature: Auth and privacy

**Canonical rules:** `AI_PROJECT_INSTRUCTIONS.txt` → Core Product Rules §2 (Auth and privacy)

## Behavior

- Face ID / Touch ID before any financial screen (cold start and after 30+ seconds in background)
- Privacy shield covers financial UI immediately when inactive or in the app switcher
- Auto-prompt biometrics on unlock; after 3 failed attempts (or user chooses PIN), require 6-digit app PIN
- PIN verifier stored in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) as PBKDF2-HMAC-SHA256 (120k iterations) — never plaintext
- First-time PIN optional: use **Settings → Security → Set up app lock** (or Dashboard banner) when already signed in
- After PIN exists: Face ID / PIN required when returning after the background grace period
- Financial Supabase loads only when authenticated, PIN configured, and app unlocked
- `NSAllowsArbitraryLoads` = false

## Code map

| Area | Path |
|------|------|
| Auth UI | `BudgetTracker/Views/Auth/AuthView.swift` |
| App lock UI | `BudgetTracker/Views/Auth/AppLockViews.swift` |
| Session store | `BudgetTracker/Backend/Auth/AuthStore.swift` |
| App lock store | `BudgetTracker/Backend/Auth/AppLockStore.swift` |
| App lock policy | `BudgetTracker/Backend/Auth/AppLockPolicy.swift` |
| PIN Keychain | `BudgetTracker/Backend/Auth/PINKeychainStore.swift` |
| PIN hashing | `BudgetTracker/Backend/Auth/PINHasher.swift` |
| OTP bridge | `BudgetTracker/Backend/Auth/AuthOTPBridge.swift` |
| Root routing | `BudgetTracker/App/RootView.swift` |
| OTP Edge Functions | `supabase/functions/request-login-otp/`, `send-auth-email/` |

## Go-bys

- OTP email flow: compare `../Optimized/supabase/functions/request-login-otp/`
- `docs/OTP_AUTH.md`

## Tests

`BudgetTrackerTests/Backend/Auth/AuthStoreTests.swift` — required for launch-guard changes.

## Do not

- Skip biometric gate for “debug convenience” on financial views
- Log session tokens or Plaid-related secrets
