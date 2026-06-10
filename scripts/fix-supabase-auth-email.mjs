#!/usr/bin/env node
/**
 * Configure Budget Tracker Supabase auth email (Resend hook or Gmail SMTP).
 *
 * Usage:
 *   set RESEND_API_KEY=re_...
 *   node scripts/fix-supabase-auth-email.mjs
 *
 * Reads SUPABASE_ACCESS_TOKEN from Config/SECRETS.local.md if unset.
 */
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(scriptDir, '..');
const PROJECT_REF = 'dldbcbituquxedlkeefu';
const FUNCTION_SLUG = 'send-auth-email';

function readSecretsFile() {
  const secretsPath = path.join(repoRoot, 'Config', 'SECRETS.local.md');
  if (!fs.existsSync(secretsPath)) return {};
  const text = fs.readFileSync(secretsPath, 'utf8');
  const out = {};
  for (const key of [
    'SUPABASE_ACCESS_TOKEN',
    'RESEND_API_KEY',
    'GOOGLE_APP_PASSWORD',
    'SUPABASE_ANON_KEY',
  ]) {
    const m = text.match(new RegExp(`^${key}=(.+)$`, 'm'));
    if (m) out[key] = m[1].trim();
  }
  return out;
}

const secrets = readSecretsFile();
const accessToken = process.env.SUPABASE_ACCESS_TOKEN || secrets.SUPABASE_ACCESS_TOKEN;
let resendKey = process.env.RESEND_API_KEY?.trim() || secrets.RESEND_API_KEY;
let googleAppPassword = process.env.GOOGLE_APP_PASSWORD?.trim() || secrets.GOOGLE_APP_PASSWORD;
const anonKey = secrets.SUPABASE_ANON_KEY;

if (!accessToken) {
  console.error('Missing SUPABASE_ACCESS_TOKEN in env or Config/SECRETS.local.md');
  process.exit(1);
}
if (!resendKey?.startsWith('re_') && !googleAppPassword) {
  console.error('Set RESEND_API_KEY (re_...) or GOOGLE_APP_PASSWORD in env or SECRETS.local.md');
  process.exit(1);
}

function magicLinkEmailTemplate() {
  const templatePath = path.join(repoRoot, 'supabase', 'templates', 'magic_link.html');
  return fs.readFileSync(templatePath, 'utf8').trim();
}

const MAGIC_LINK_SUBJECT = 'Your Budget Tracker sign-in code';

async function applyOtpEmailTemplate() {
  const body = {
    mailer_otp_length: 6,
    mailer_subjects_magic_link: MAGIC_LINK_SUBJECT,
    mailer_templates_magic_link_content: magicLinkEmailTemplate(),
  };
  const r = await mgmt('/config/auth', { method: 'PATCH', body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`PATCH magic link template failed: ${await r.text()}`);
  console.log('Magic link email template updated (shows {{ .Token }} OTP in email)');
}

const mgmt = (p, opts = {}) =>
  fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}${p}`, {
    ...opts,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...(opts.headers || {}),
    },
  });

async function setSecrets(hookSecret) {
  const body = [
    { name: 'RESEND_API_KEY', value: resendKey },
    { name: 'SEND_EMAIL_HOOK_SECRET', value: hookSecret },
    { name: 'AUTH_FROM_EMAIL', value: 'Budget Tracker <onboarding@resend.dev>' },
  ];
  const r = await mgmt('/secrets', { method: 'POST', body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`Set secrets failed: ${await r.text()}`);
  console.log('Edge function secrets updated');
}

async function enableSendEmailHook(hookSecret) {
  const hookUri = `https://${PROJECT_REF}.supabase.co/functions/v1/${FUNCTION_SLUG}`;
  const body = {
    hook_send_email_enabled: true,
    hook_send_email_uri: hookUri,
    hook_send_email_secrets: hookSecret,
    external_email_enabled: true,
    mailer_otp_length: 6,
    mailer_subjects_magic_link: MAGIC_LINK_SUBJECT,
    mailer_templates_magic_link_content: magicLinkEmailTemplate(),
  };
  const r = await mgmt('/config/auth', { method: 'PATCH', body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`PATCH auth failed: ${await r.text()}`);
  console.log('Send-email hook enabled:', hookUri);
}

async function patchGmailSmtp() {
  const body = {
    smtp_host: 'smtp.gmail.com',
    smtp_port: '587',
    smtp_user: 'dsmccaughan@gmail.com',
    smtp_pass: googleAppPassword,
    smtp_admin_email: 'dsmccaughan@gmail.com',
    smtp_sender_name: 'Budget Tracker',
    external_email_enabled: true,
    hook_send_email_enabled: false,
    mailer_otp_length: 6,
    mailer_subjects_magic_link: MAGIC_LINK_SUBJECT,
    mailer_templates_magic_link_content: magicLinkEmailTemplate(),
  };
  const r = await mgmt('/config/auth', { method: 'PATCH', body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`PATCH Gmail SMTP failed: ${await r.text()}`);
  console.log('Gmail SMTP configured');
}

async function testOtp() {
  if (!anonKey) {
    console.warn('No SUPABASE_ANON_KEY in SECRETS.local.md — skipping OTP probe');
    return;
  }
  const r = await fetch(`https://${PROJECT_REF}.supabase.co/auth/v1/otp`, {
    method: 'POST',
    headers: { apikey: anonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'dsmccaughan@gmail.com', create_user: true }),
  });
  const text = await r.text();
  console.log(`OTP probe: ${r.status} ${text.slice(0, 200)}`);
  if (!r.ok) process.exit(1);
}

async function main() {
  if (resendKey?.startsWith('re_')) {
    const hookSecret = `v1,whsec_${crypto.randomBytes(24).toString('base64')}`;
    await setSecrets(hookSecret);
    await enableSendEmailHook(hookSecret);
    console.log('Deploy send-auth-email: supabase functions deploy send-auth-email --no-verify-jwt');
  } else {
    await patchGmailSmtp();
  }
  await applyOtpEmailTemplate();
  await testOtp();
  console.log('Done. Sign-in emails should show the 6-digit code in the message body.');
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
