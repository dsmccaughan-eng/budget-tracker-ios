# Email OTP sign-in (no passwords)

Budget Tracker uses **email one-time codes**. Users never set or store a password in the app.

## Flow

1. Enter email → **Send sign-in code**
2. Enter the 6-digit code (email or in-app fallback) → signed in
3. Session persists via Supabase (refresh token on device)

## Backend keys (no in-app setup)

Supabase URL and **anon public key** are baked into the app (`Info.plist`, `APIKeys`, bundled `Config/LocalAPIKeys.plist`). Users are **never** asked to paste keys.

Codemagic `budgettracker_secrets` should still set `SUPABASE_ANON_KEY` and `SUPABASE_URL` for Release archives when using `pkg.xcconfig`.

## In-app code fallback

If Supabase email is slow or rate-limited, allowlisted addresses get a code on the next screen via `request-login-otp`:

- Default allowlist includes `dsmccaughan@gmail.com`
- Add more: `OTP_ALLOWLIST=you@example.com,friend@example.com` in Supabase Edge Function secrets

Deploy:

```powershell
.\scripts\deploy-backend.ps1
```

## Enable email auth in Supabase

Dashboard → Authentication → Providers → **Email** → enable Email OTP / magic link.
