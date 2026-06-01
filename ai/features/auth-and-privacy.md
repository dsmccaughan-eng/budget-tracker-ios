# Feature: Auth and privacy

**Canonical rules:** `AI_PROJECT_INSTRUCTIONS.txt` → Core Product Rules §2 (Auth and privacy)

## Behavior

- Face ID / Touch ID before any financial screen (cold start and return from background)
- `BiometricGate` on app lifecycle
- `NSAllowsArbitraryLoads` = false

## Code map

| Area | Path |
|------|------|
| Auth UI | `BudgetTracker/Views/Auth/AuthView.swift` |
| Session store | `BudgetTracker/Backend/Auth/AuthStore.swift` |
| OTP bridge | `BudgetTracker/Backend/Auth/AuthOTPBridge.swift` |
| Biometric gate | `BudgetTracker/App/BiometricGate.swift` |
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
