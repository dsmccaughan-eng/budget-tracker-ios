#!/usr/bin/env node
/**
 * Service-role ops script: invoke recategorize-transactions for a user via edge function.
 * Requires the function to be deployed. Uses a short-lived user JWT from service role.
 *
 * Usage: node scripts/recategorize-user-transactions.mjs [userId] [limit]
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const repoRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const secrets = Object.fromEntries(
  fs
    .readFileSync(path.join(repoRoot, 'Config/SECRETS.local.md'), 'utf8')
    .split(/\r?\n/)
    .filter((line) => /^[A-Z0-9_]+=/.test(line))
    .map((line) => {
      const index = line.indexOf('=');
      return [line.slice(0, index), line.slice(index + 1)];
    })
);

const userId = process.argv[2] || 'a580abbe-01ef-498c-9ad7-e5a3ff092e3e';
const limit = Number.parseInt(process.argv[3] || '2000', 10);
const supabaseUrl = secrets.SUPABASE_URL;
const serviceRoleKey = secrets.SUPABASE_SERVICE_ROLE_KEY;

const adminHeaders = {
  apikey: serviceRoleKey,
  Authorization: `Bearer ${serviceRoleKey}`,
  'Content-Type': 'application/json',
};

async function adminFetch(pathname, options = {}) {
  const response = await fetch(`${supabaseUrl}${pathname}`, {
    headers: adminHeaders,
    ...options,
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${pathname} ${response.status}: ${text.slice(0, 400)}`);
  }
  return text ? JSON.parse(text) : null;
}

async function getUserEmail() {
  const users = await adminFetch(`/auth/v1/admin/users/${userId}`);
  return users?.email;
}

async function createUserJwt(email) {
  const link = await adminFetch('/auth/v1/admin/generate_link', {
    method: 'POST',
    body: JSON.stringify({
      type: 'magiclink',
      email,
    }),
  });
  const actionLink = link?.action_link;
  if (!actionLink) throw new Error('Could not generate user auth link');
  const token = new URL(actionLink).searchParams.get('token');
  const type = new URL(actionLink).searchParams.get('type') || 'magiclink';
  if (!token) throw new Error('Magic link missing token');

  const verify = await fetch(`${supabaseUrl}/auth/v1/verify`, {
    method: 'POST',
    headers: {
      apikey: secrets.SUPABASE_ANON_KEY || serviceRoleKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ type, token_hash: token }),
  });
  const payload = await verify.json();
  if (!verify.ok || !payload?.access_token) {
    throw new Error(`verify failed: ${JSON.stringify(payload).slice(0, 200)}`);
  }
  return payload.access_token;
}

async function recategorizeBatch(accessToken) {
  const response = await fetch(`${supabaseUrl}/functions/v1/recategorize-transactions`, {
    method: 'POST',
    headers: {
      apikey: secrets.SUPABASE_ANON_KEY || serviceRoleKey,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ limit }),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`recategorize-transactions ${response.status}: ${text.slice(0, 400)}`);
  }
  return JSON.parse(text);
}

async function main() {
  const email = await getUserEmail();
  if (!email) throw new Error(`No email for user ${userId}`);
  console.log(`Recategorizing transactions for ${email} (${userId}), limit=${limit}…`);

  const accessToken = await createUserJwt(email);
  let totalScanned = 0;
  let totalUpdated = 0;
  let totalCategorized = 0;
  let passes = 0;

  while (passes < 20) {
    const result = await recategorizeBatch(accessToken);
    totalScanned += result.scanned || 0;
    totalUpdated += result.updated || 0;
    totalCategorized += result.categorized || 0;
    passes += 1;
    console.log(
      `  pass ${passes}: scanned=${result.scanned} updated=${result.updated} categorized=${result.categorized}`
    );
    if (!result.scanned || result.categorized === 0) break;
  }

  const remaining = await adminFetch(
    `/rest/v1/transactions?select=id&user_id=eq.${userId}&category=eq.Other&is_manual=eq.false&or=(category_source.is.null,category_source.eq.plaid)&limit=1`
  );
  console.log(
    `Done. total scanned=${totalScanned} updated=${totalUpdated} categorized=${totalCategorized} remaining_other=${remaining?.length ?? 0}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
