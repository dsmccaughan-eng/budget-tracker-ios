#!/usr/bin/env node
/**
 * Service-role ops script: run Plaid /transactions/sync for a user and upsert rows.
 * Usage: node scripts/force-plaid-sync-for-user.mjs [userId]
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

const supabaseUrl = secrets.SUPABASE_URL;
const serviceRoleKey = secrets.SUPABASE_SERVICE_ROLE_KEY;
const plaidClientId = secrets.PLAID_CLIENT_ID;
const plaidSecret = secrets.PLAID_PRODUCTION_SECRET || secrets.PLAID_SANDBOX_SECRET;
const plaidEnv = secrets.PLAID_ENV || 'sandbox';
const userId = process.argv[2] || 'a580abbe-01ef-498c-9ad7-e5a3ff092e3e';

const plaidBase =
  plaidEnv === 'production'
    ? 'https://production.plaid.com'
    : 'https://sandbox.plaid.com';

const headers = {
  apikey: serviceRoleKey,
  Authorization: `Bearer ${serviceRoleKey}`,
  'Content-Type': 'application/json',
  Prefer: 'return=minimal',
};

async function supabase(pathname, options = {}) {
  const response = await fetch(`${supabaseUrl}${pathname}`, { headers, ...options });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${pathname} ${response.status}: ${text.slice(0, 400)}`);
  }
  return text ? JSON.parse(text) : null;
}

async function plaidRequest(pathname, body) {
  const response = await fetch(`${plaidBase}${pathname}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'PLAID-CLIENT-ID': plaidClientId,
      'PLAID-SECRET': plaidSecret,
    },
    body: JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(
      `${pathname}: ${payload.error_code || response.status} ${payload.error_message || ''}`.trim()
    );
  }
  return payload;
}

async function syncItem(item, accountByPlaidId) {
  const token = await supabase('/rest/v1/rpc/get_plaid_access_token', {
    method: 'POST',
    body: JSON.stringify({ p_plaid_item_id: item.plaid_item_id }),
  });
  if (!token) {
    console.warn(`  skip ${item.institution_name}: no access token`);
    return { synced: 0, pages: 0 };
  }

  let cursor = item.sync_cursor || undefined;
  let synced = 0;
  let pages = 0;

  while (pages < 50) {
    const payload = await plaidRequest('/transactions/sync', {
      access_token: token,
      cursor,
      count: 500,
    });
    const rows = [...(payload.added || []), ...(payload.modified || [])];
    const upserts = [];

    for (const txn of rows) {
      const accountId = accountByPlaidId.get(txn.account_id);
      if (!accountId) continue;
      upserts.push({
        user_id: userId,
        account_id: accountId,
        plaid_transaction_id: txn.transaction_id,
        amount: txn.amount,
        date: txn.date,
        merchant_name: txn.merchant_name,
        name: txn.name,
        category: 'Other',
        subcategory: null,
        category_source: 'plaid',
        pending: txn.pending,
        is_manual: false,
      });
    }

    if (upserts.length > 0) {
      await supabase('/rest/v1/transactions?on_conflict=plaid_transaction_id', {
        method: 'POST',
        headers: {
          ...headers,
          Prefer: 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(upserts),
      });
      synced += upserts.length;
    }

    if (payload.removed?.length) {
      const removedIds = payload.removed.map((row) => row.transaction_id);
      await supabase(
        `/rest/v1/transactions?plaid_transaction_id=in.(${removedIds.map((id) => `"${id}"`).join(',')})`,
        { method: 'DELETE' }
      );
    }

    cursor = payload.next_cursor;
    pages += 1;
    if (!payload.has_more) {
      await supabase(
        `/rest/v1/plaid_items?plaid_item_id=eq.${encodeURIComponent(item.plaid_item_id)}`,
        {
          method: 'PATCH',
          body: JSON.stringify({
            sync_cursor: cursor,
            status: 'active',
            error_code: null,
            error_message: null,
            last_sync_at: new Date().toISOString(),
          }),
        }
      );
      break;
    }
  }

  return { synced, pages };
}

const items = await supabase(
  `/rest/v1/plaid_items?select=plaid_item_id,institution_name,sync_cursor&user_id=eq.${userId}&order=institution_name`
);
const accounts = await supabase(
  `/rest/v1/accounts?select=id,plaid_account_id&user_id=eq.${userId}`
);
const accountByPlaidId = new Map(accounts.map((row) => [row.plaid_account_id, row.id]));

console.log(`Syncing ${items.length} Plaid item(s) for ${userId}…`);
let total = 0;
for (const item of items) {
  process.stdout.write(`- ${item.institution_name ?? item.plaid_item_id}: `);
  try {
    const result = await syncItem(item, accountByPlaidId);
    total += result.synced;
    console.log(`${result.synced} rows (${result.pages} page(s))`);
  } catch (error) {
    console.log(`FAILED ${error.message}`);
  }
}

const newest = await supabase(
  `/rest/v1/transactions?select=date&user_id=eq.${userId}&order=date.desc&limit=1`
);
console.log(`Done. Upserted ${total} transaction rows. Newest date: ${newest[0]?.date ?? 'none'}`);
console.log('Run: node scripts/recategorize-user-transactions.mjs', userId);
