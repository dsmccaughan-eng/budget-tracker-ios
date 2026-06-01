#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { loadIosAppConfig, repoRootFromScript } from './load-ios-app-config.mjs';

const repoRoot = repoRootFromScript(import.meta.url);
const cfg = loadIosAppConfig(repoRoot);

const tokenFile = path.join(repoRoot, 'signing', 'cm_api_token.txt');
const GROUP_ID = process.env.CM_GROUP_ID || cfg.codemagic.groupId;

const token =
  process.env.CM_API_TOKEN ||
  (fs.existsSync(tokenFile) ? fs.readFileSync(tokenFile, 'utf8').trim() : '');

const p12Path =
  process.env.CM_P12_PATH ||
  path.join(repoRoot, 'signing', 'certs', 'distribution_codemagic.p12');
const p12Password = process.env.CM_P12_PASSWORD;

if (!token) {
  console.error('Missing CM_API_TOKEN or signing/cm_api_token.txt');
  process.exit(1);
}
if (!GROUP_ID) {
  console.error('Set codemagic.groupId in ios-app.config.json (or CM_GROUP_ID env)');
  process.exit(1);
}
if (!fs.existsSync(p12Path)) {
  console.error(`Missing P12: ${p12Path}`);
  process.exit(1);
}
if (!p12Password) {
  console.error('Set CM_P12_PASSWORD');
  process.exit(1);
}

const profileDir = path.join(repoRoot, 'signing', 'profiles');
const vars = [
  { name: 'CM_CERTIFICATE', value: fs.readFileSync(p12Path).toString('base64') },
  { name: 'CM_CERTIFICATE_PASSWORD', value: p12Password },
];

for (const profile of cfg.profiles) {
  const p = path.join(profileDir, profile.file);
  if (!fs.existsSync(p)) {
    console.error(`Missing profile: ${p} — run node scripts/download-asc-profiles.mjs`);
    process.exit(1);
  }
  vars.push({
    name: profile.env,
    value: fs.readFileSync(p).toString('base64'),
  });
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
  const app = cfg.codemagic.appId
    ? apps.applications?.find((a) => a._id === cfg.codemagic.appId)
    : null;
  const existing = app?.appEnvironmentVariables?.variables?.find((v) => v.key === name);
  if (!existing?.id) throw new Error(`Cannot PATCH ${name}: not found`);
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

for (const v of vars) {
  await upsertVariable(v.name, v.value);
  console.log('Uploaded', v.name);
}
console.log(`Codemagic group ${GROUP_ID} updated for ${cfg.displayName}.`);
