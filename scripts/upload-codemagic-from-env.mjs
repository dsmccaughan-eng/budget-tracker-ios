#!/usr/bin/env node
import { loadIosAppConfig, repoRootFromScript } from './load-ios-app-config.mjs';

const repoRoot = repoRootFromScript(import.meta.url);
const cfg = loadIosAppConfig(repoRoot);

const GROUP_ID = process.env.CM_GROUP_ID || cfg.codemagic.groupId;
const token = process.env.CM_API_TOKEN;

const required = ['CM_API_TOKEN', 'P12_BASE64', 'P12_PASSWORD'];
for (const profile of cfg.profiles) {
  const secretName = cfg.githubSigningSecrets?.[profile.env.replace('CM_PROVISIONING_PROFILE_', '')] ||
    cfg.githubSigningSecrets?.APP_PROFILE;
  // map env to github secret key from config
}
// Simpler: build from githubSigningSecrets object
const secretMap = cfg.githubSigningSecrets || {};
const envToGithub = {
  CM_PROVISIONING_PROFILE_MAIN: secretMap.APP_PROFILE || 'DIST_PROVISIONING_PROFILE_BASE64',
  CM_PROVISIONING_PROFILE_WIDGETS: secretMap.WIDGETS_PROFILE,
  CM_PROVISIONING_PROFILE_WATCH: secretMap.WATCH_PROFILE,
};

for (const k of ['CM_API_TOKEN', 'P12_BASE64', 'P12_PASSWORD']) {
  if (!process.env[k]) {
    console.error(`Missing env ${k}`);
    process.exit(1);
  }
}

const vars = [
  { name: 'CM_CERTIFICATE', value: process.env.P12_BASE64.replace(/\s/g, '') },
  { name: 'CM_CERTIFICATE_PASSWORD', value: process.env.P12_PASSWORD },
];

for (const profile of cfg.profiles) {
  const gh =
    profile.env === 'CM_PROVISIONING_PROFILE_MAIN'
      ? process.env.APP_PROFILE || process.env.DIST_PROVISIONING_PROFILE_BASE64
      : profile.env === 'CM_PROVISIONING_PROFILE_WIDGETS'
        ? process.env.WIDGETS_PROFILE
        : profile.env === 'CM_PROVISIONING_PROFILE_WATCH'
          ? process.env.WATCH_PROFILE
          : null;
  if (!gh) {
    console.error(`Missing GitHub secret env for ${profile.env}`);
    process.exit(1);
  }
  vars.push({ name: profile.env, value: gh.replace(/\s/g, '') });
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
  if (!cfg.codemagic.appId) throw new Error(`Cannot PATCH ${name}: codemagic.appId not set`);
  const apps = await fetch('https://api.codemagic.io/apps', {
    headers: { 'x-auth-token': token },
  }).then((r) => r.json());
  const app = apps.applications?.find((a) => a._id === cfg.codemagic.appId);
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
console.log(`Codemagic signing secrets updated (${cfg.displayName}).`);
