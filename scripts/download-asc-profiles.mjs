#!/usr/bin/env node
import fs from 'fs';
import crypto from 'crypto';
import path from 'path';
import { fileURLToPath } from 'url';
import { loadIosAppConfig, repoRootFromScript } from './load-ios-app-config.mjs';

const repoRoot = repoRootFromScript(import.meta.url);
const cfg = loadIosAppConfig(repoRoot);

const keyPath =
  process.argv[2] || path.join(repoRoot, 'signing', 'certs', `AuthKey_${cfg.ascKeyId}.p8`);
const outDir = process.argv[3] || path.join(repoRoot, 'signing', 'profiles');

function b64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function makeToken(privateKeyPem) {
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: cfg.ascKeyId, typ: 'JWT' }));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(
    JSON.stringify({ iss: cfg.ascIssuerId, exp: now + 1200, aud: 'appstoreconnect-v1' })
  );
  const data = `${header}.${payload}`;
  const sign = crypto.sign('sha256', Buffer.from(data), {
    key: privateKeyPem,
    dsaEncoding: 'ieee-p1363',
  });
  return `${data}.${sign.toString('base64url')}`;
}

const privateKey = fs.readFileSync(keyPath, 'utf8');
const token = makeToken(privateKey);

const res = await fetch('https://api.appstoreconnect.apple.com/v1/profiles?limit=200', {
  headers: { Authorization: `Bearer ${token}` },
});
if (!res.ok) {
  console.error('API error', res.status, await res.text());
  process.exit(1);
}

const json = await res.json();
fs.mkdirSync(outDir, { recursive: true });

for (const profile of cfg.profiles) {
  const name = profile.ascName;
  const item = json.data?.find((p) => p.attributes?.name === name);
  if (!item) {
    console.error('Profile not found:', name);
    process.exit(1);
  }
  const content = item.attributes?.profileContent;
  if (!content) {
    console.error('No profileContent for', name);
    process.exit(1);
  }
  const file = path.join(outDir, profile.file);
  fs.writeFileSync(file, Buffer.from(content, 'base64'));
  console.log('Wrote', file);
}
