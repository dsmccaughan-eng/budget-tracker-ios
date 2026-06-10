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

The **Magic Link** email template must include `{{ .Token }}` so users see the 6-digit code (not only a confirmation link). This repo ships `supabase/templates/magic_link.html`; apply to hosted project with:

```powershell
node scripts/fix-supabase-auth-email.mjs
```

Or in Dashboard → Authentication → Email Templates → **Magic Link**, paste the template body from that file.

**OTP length:** Hosted auth must use `mailer_otp_length: 6` (Dashboard → Auth → Providers → Email, or the fix script). Default on some projects is 8, which mismatches the app’s 6-digit field.
