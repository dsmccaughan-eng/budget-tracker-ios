# Email OTP sign-in (no passwords)

Budget Tracker uses **email one-time codes** (same pattern as Optimized). Users never set or store a password in the app.

## Flow

1. Enter email → **Send sign-in code**
2. Enter the 6-digit code from email → signed in
3. Session persists via Supabase (refresh token on device)

## Backend key on device

TestFlight builds need the **Supabase anon public key** once:

- Sign-in screen → **Backend** section, or **Settings → Backend**
- Paste from Supabase Dashboard → Project Settings → API → `anon` `public`
- Project URL is pre-filled (`https://dldbcbituquxedlkeefu.supabase.co`)

Codemagic should also set `SUPABASE_ANON_KEY` in `budgettracker_secrets` so most users never see this step.

## Email delivery fallback

If Supabase cannot send email, allowlisted addresses can get an **in-app code** via the `request-login-otp` edge function.

Deploy:

```powershell
.\scripts\deploy-backend.ps1
```

Set allowlist (optional):

```text
OTP_ALLOWLIST=you@example.com,other@example.com
```

in Supabase Edge Function secrets.

## Enable email auth in Supabase

Dashboard → Authentication → Providers → **Email** → enable Email OTP / magic link.
