#!/usr/bin/env node
/**
 * Upload SUPABASE_* and GEMINI_* from Config/SECRETS.local.md to Codemagic.
 * Usage: node scripts/upload-codemagic-api-keys.mjs
 */
import fs from 'fs';
import path from 'path';
import { loadIosAppConfig, repoRootFromScript } from './load-ios-app-config.mjs';

const repoRoot = repoRootFromScript(import.meta.url);
const cfg = loadIosAppConfig(repoRoot);
const secretsPath = path.join(repoRoot, 'Config', 'SECRETS.local.md');
const tokenFile = path.join(repoRoot, 'signing', 'cm_api_token.txt');

const token =
  process.env.CM_API_TOKEN ||
  (fs.existsSync(tokenFile) ? fs.readFileSync(tokenFile, 'utf8').trim() : '');
const GROUP_ID = process.env.CM_GROUP_ID || cfg.codemagic.groupId;

if (!token) {
  console.error('Missing CM_API_TOKEN or signing/cm_api_token.txt');
  process.exit(1);
}
if (!fs.existsSync(secretsPath)) {
  console.error(`Missing ${secretsPath}`);
  process.exit(1);
}

function parseSecrets(md) {
  const out = {};
  for (const line of md.split(/\r?\n/)) {
    const trimmed = line.trim();
    const m = trimmed.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

const secrets = parseSecrets(fs.readFileSync(secretsPath, 'utf8'));
const keys = cfg.pkgXcconfigKeys || ['GEMINI_API_KEY', 'SUPABASE_URL', 'SUPABASE_ANON_KEY'];
const vars = keys
  .map((name) => ({ name, value: secrets[name] || '' }))
  .filter((v) => v.value);

for (const v of vars) {
  if (!v.value || v.value.includes('your_')) {
    console.error(`Missing or placeholder value for ${v.name} in SECRETS.local.md`);
    process.exit(1);
  }
}

const headers = {
  Accept: 'application/json',
  'Content-Type': 'application/json',
  'x-auth-token': token,
};

async function upsertVariable(name, value) {
  try {
    const res = await fetch(
      `https://codemagic.io/api/v3/variable-groups/${GROUP_ID}/variables`,
      {
        method: 'POST',
        headers,
        body: JSON.stringify({ secure: true, variables: [{ name, value }] }),
      }
    );
    if (res.ok || res.status === 201) return;
    const text = await res.text();
    if (!text.includes('already exists')) throw new Error(`${res.status} ${text}`);
  } catch (e) {
    if (!String(e.message).includes('already exists')) throw e;
  }
  const apps = await fetch('https://api.codemagic.io/apps', {
    headers: { 'x-auth-token': token },
  }).then((r) => r.json());
  const app = apps.applications?.find((a) => a._id === cfg.codemagic.appId);
  const existing = app?.appEnvironmentVariables?.variables?.find((v) => v.key === name);
  if (!existing?.id) throw new Error(`Cannot PATCH ${name}: variable not found in group`);
  const patch = await fetch(
    `https://codemagic.io/api/v3/variable-groups/${GROUP_ID}/variables/${existing.id}`,
    {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ name, value, secure: true }),
    }
  );
  if (!patch.ok) throw new Error(`PATCH ${name}: ${await patch.text()}`);
}

console.log(`Uploading ${vars.length} keys to Codemagic group ${GROUP_ID} (${cfg.codemagic.secretsGroup})…`);
for (const v of vars) {
  await upsertVariable(v.name, v.value);
  console.log(`Uploaded ${v.name} (${v.value.length} chars)`);
}
console.log('Done. Trigger: node scripts/trigger-codemagic-build.mjs');
