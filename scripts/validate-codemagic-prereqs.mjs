#!/usr/bin/env node
import fs from 'fs';
import crypto from 'crypto';
import path from 'path';
import { spawnSync } from 'child_process';
import { loadIosAppConfig, repoRootFromScript } from './load-ios-app-config.mjs';

const repoRoot = repoRootFromScript(import.meta.url);
const cfg = loadIosAppConfig(repoRoot);

const OPENSSL =
  process.env.OPENSSL ||
  (fs.existsSync('C:/Program Files/Git/usr/bin/openssl.exe')
    ? 'C:/Program Files/Git/usr/bin/openssl.exe'
    : 'openssl');

const P8_PATH = path.join(repoRoot, 'signing', 'certs', `AuthKey_${cfg.ascKeyId}.p8`);
const PROFILE_NAMES = cfg.profiles.map((p) => p.ascName);
const CM_APP_ID = cfg.codemagic.appId;

let failures = 0;
const warn = (msg) => console.log(`⚠️  ${msg}`);
const ok = (msg) => console.log(`✅ ${msg}`);
const fail = (msg) => {
  console.log(`❌ ${msg}`);
  failures += 1;
};

function b64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function ascToken() {
  const p8 = fs.readFileSync(P8_PATH, 'utf8');
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: cfg.ascKeyId, typ: 'JWT' }));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(
    JSON.stringify({ iss: cfg.ascIssuerId, exp: now + 1200, aud: 'appstoreconnect-v1' })
  );
  const data = `${header}.${payload}`;
  const sign = crypto.sign('sha256', Buffer.from(data), {
    key: p8,
    dsaEncoding: 'ieee-p1363',
  });
  return `${data}.${sign.toString('base64url')}`;
}

function opensslModulus(args) {
  const r = spawnSync(OPENSSL, args, { encoding: 'utf8' });
  if (r.status !== 0) return null;
  return (r.stdout || '').trim();
}

async function ascProfileCertificateModulus(profileName) {
  const token = ascToken();
  const headers = { Authorization: `Bearer ${token}` };
  const list = await fetch('https://api.appstoreconnect.apple.com/v1/profiles?limit=200', {
    headers,
  }).then((r) => r.json());
  const prof = list.data?.find((p) => p.attributes?.name === profileName);
  if (!prof) return null;
  const certs = await fetch(
    `https://api.appstoreconnect.apple.com/v1/profiles/${prof.id}/certificates`,
    { headers }
  ).then((r) => r.json());
  const certId = certs.data?.[0]?.id;
  if (!certId) return null;
  const cert = await fetch(`https://api.appstoreconnect.apple.com/v1/certificates/${certId}`, {
    headers,
  }).then((r) => r.json());
  const cerPath = path.join(repoRoot, 'signing', '.tmp-asc.cer');
  fs.writeFileSync(cerPath, Buffer.from(cert.data.attributes.certificateContent, 'base64'));
  const mod = opensslModulus(['x509', '-inform', 'DER', '-in', cerPath, '-noout', '-modulus']);
  fs.unlinkSync(cerPath);
  return mod;
}

function keyModulus(pemPath) {
  return opensslModulus(['rsa', '-in', pemPath, '-noout', '-modulus']);
}

function p12Modulus(p12Path, password) {
  const p12 = path.join(repoRoot, 'signing', '.tmp-check.p12');
  fs.copyFileSync(p12Path, p12);
  const key = path.join(repoRoot, 'signing', '.tmp-extracted.key');
  const r = spawnSync(
    OPENSSL,
    ['pkcs12', '-in', p12, '-nocerts', '-nodes', '-out', key, '-passin', `pass:${password}`],
    { encoding: 'utf8' }
  );
  fs.unlinkSync(p12);
  if (r.status !== 0) return { error: r.stderr || 'pkcs12 extract failed' };
  const mod = opensslModulus(['rsa', '-in', key, '-noout', '-modulus']);
  fs.unlinkSync(key);
  return { modulus: mod };
}

async function checkSigningMaterial() {
  const profilesDir = path.join(repoRoot, 'signing', 'profiles');
  if (!fs.existsSync(profilesDir)) {
    warn('Run: node scripts/download-asc-profiles.mjs');
  }

  const primary = cfg.profiles[0]?.ascName;
  const profileCertMod = primary ? await ascProfileCertificateModulus(primary) : null;
  if (!profileCertMod) {
    fail(`Could not load certificate for ${primary || 'primary'} profile`);
    return;
  }
  ok('Loaded Apple Distribution cert from ASC profile');

  const p12Path =
    process.env.CM_P12_PATH ||
    path.join(repoRoot, 'signing', 'certs', 'distribution_codemagic.p12');
  const p12Pass = process.env.CM_P12_PASSWORD;

  if (fs.existsSync(p12Path) && p12Pass) {
    const r = p12Modulus(p12Path, p12Pass);
    if (r.error) fail(`P12 check failed: ${r.error}`);
    else if (r.modulus === profileCertMod) ok(`P12 matches active profiles: ${p12Path}`);
    else fail('P12 does not match active ASC profiles');
  } else {
    warn(
      'Set CM_P12_PATH + CM_P12_PASSWORD then run:\n' +
        '   node scripts/upload-codemagic-signing-secrets.mjs'
    );
  }

  if (!CM_APP_ID) {
    warn('codemagic.appId empty in ios-app.config.json — set after creating Codemagic app');
    return;
  }

  const tokenPath = path.join(repoRoot, 'signing', 'cm_api_token.txt');
  if (fs.existsSync(tokenPath)) {
    const apps = await fetch('https://api.codemagic.io/apps', {
      headers: { 'x-auth-token': fs.readFileSync(tokenPath, 'utf8').trim() },
    }).then((r) => r.json());
    const vars =
      apps.applications?.find((a) => a._id === CM_APP_ID)?.appEnvironmentVariables?.variables ||
      [];
    const hasCert = vars.some((v) => v.key === 'CM_CERTIFICATE');
    const hasP12Key = vars.some((v) => v.key === 'CERTIFICATE_PRIVATE_KEY');
    if (hasP12Key) warn('Remove obsolete CERTIFICATE_PRIVATE_KEY in Codemagic');
    if (hasCert) ok('Codemagic has CM_CERTIFICATE');
    else fail('Codemagic missing CM_CERTIFICATE');
  }
}

async function checkAsc() {
  const token = ascToken();
  const headers = { Authorization: `Bearer ${token}` };
  const profJson = await fetch('https://api.appstoreconnect.apple.com/v1/profiles?limit=200', {
    headers,
  }).then((r) => r.json());
  for (const name of PROFILE_NAMES) {
    const p = profJson.data?.find((x) => x.attributes?.name === name);
    if (!p || p.attributes?.profileState !== 'ACTIVE') fail(`ASC profile not ACTIVE: ${name}`);
    else ok(`ASC profile ACTIVE: ${name}`);
  }
}

async function checkCodemagic() {
  if (!CM_APP_ID) return;
  const tokenPath = path.join(repoRoot, 'signing', 'cm_api_token.txt');
  if (!fs.existsSync(tokenPath)) {
    warn('No signing/cm_api_token.txt');
    return;
  }
  const token = fs.readFileSync(tokenPath, 'utf8').trim();
  const h = { 'x-auth-token': token };
  const app = (await fetch('https://api.codemagic.io/apps', { headers: h }).then((r) => r.json()))
    .applications?.find((a) => a._id === CM_APP_ID);
  if (!app?.repository?.isAuthenticationEnabled) {
    if (process.env.CM_SKIP_GITHUB_CHECK === '1') {
      warn('API still shows isAuthenticationEnabled=false (proceed if UI shows connected)');
    } else {
      fail('GitHub not connected on Codemagic app — reconnect or set CM_SKIP_GITHUB_CHECK=1');
    }
  } else ok('Codemagic GitHub connected');
  const user = await fetch('https://api.codemagic.io/user', { headers: h }).then((r) => r.json());
  const used = user.user?.billing?.usage?.currentPeriod?.buildTime?.mac_mini_m2_free ?? 0;
  ok(`Free macOS minutes used ~${(used / 60).toFixed(1)} / 500`);
}

console.log(`=== Codemagic preflight — ${cfg.displayName} ===\n`);
await checkSigningMaterial();
console.log('');
await checkAsc();
console.log('');
await checkCodemagic();
console.log('');
if (failures) {
  console.log(`BLOCKED: ${failures} issue(s).`);
  process.exit(1);
}
console.log('Ready: node scripts/trigger-codemagic-build.mjs');
