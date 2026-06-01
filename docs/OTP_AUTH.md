# Email OTP sign-in (no passwords)

Budget Tracker uses **email one-time codes**, same pattern as the Optimized fitness app.

## Flow

1. Enter email → **Send sign-in code**
2. Check your **email** for the 6-digit code (inbox and spam)
3. Enter the code → signed in

## In-app code (emergency only)

If Supabase **cannot send email** (SMTP/Resend not configured), allowlisted addresses may receive a code in the app. This is a **fallback**, not the normal path.

Configure real email delivery:

```powershell
# After adding RESEND_API_KEY to Config/SECRETS.local.md:
node scripts/fix-supabase-auth-email.mjs
.\scripts\deploy-backend.ps1   # deploys send-auth-email
```

## Enable email in Supabase

Dashboard → Authentication → Providers → **Email** → enable Email OTP.
