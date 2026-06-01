# Launch crash root cause (confirmed 2026-06-01)

## ASC / Xcode Organizer

- App Store Connect `betaFeedbackCrashSubmissions`: **0** entries (crashes not ingested via API yet).
- `diagnosticSignatures` for builds 6–10: **404** (not available for this app/build set).
- Use **Xcode → Window → Organizer → Crashes** for symbolicated stacks when available.

## Confirmed issue (public report matches TestFlight behavior)

**[supabase/supabase-swift#960](https://github.com/supabase/supabase-swift/issues/960)** — fixed in **2.44.0** ([#962](https://github.com/supabase/supabase-swift/pull/962))

```
Exception Type:  EXC_BREAKPOINT (SIGTRAP)
Thread 0 Crashed:
  Swift runtime failure: Unexpectedly found nil while unwrapping an Optional value
  SupabaseClient.init(supabaseURL:supabaseKey:options:) (SupabaseClient.swift:168)
```

**Cause:** `supabaseURL.host!` in older SDK; on **iOS 26**, deprecated `URL.host` returns `nil` for valid `https://*.supabase.co` URLs.

**Budget Tracker trigger:** `RootView.task` → `AuthStore.bootstrap()` → `SupabaseClient` init on launch when keys are configured (Release `pkg.xcconfig`).

## Safeguards shipped

| Layer | Mitigation |
|-------|------------|
| SPM | `supabase-swift` **from 2.44.0** in `project.yml` |
| CI | `scripts/verify-supabase-package.sh` before IPA |
| App | `SupabaseConfig.validatedURL` + `SupabaseClientFactory.makeClient` (host pre-check) |
| Tests | `AuthStoreTests`, `SupabaseConfigTests` |
| Auth | Lazy client; no init in `AuthStore.init` |

## Verification after TestFlight build

1. App opens to auth or main UI (no instant quit).
2. Organizer crash list no longer shows `SupabaseClient.init` + `URL.host` trap.
3. Codemagic logs: unit tests + supabase package verify passed.
