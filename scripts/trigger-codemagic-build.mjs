#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { spawnSync } from 'child_process';
import { loadIosAppConfig, repoRootFromScript } from './load-ios-app-config.mjs';

const repoRoot = repoRootFromScript(import.meta.url);
const cfg = loadIosAppConfig(repoRoot);

const tokenFile = path.join(repoRoot, 'signing', 'cm_api_token.txt');
const token =
  process.env.CM_API_TOKEN ||
  (fs.existsSync(tokenFile) ? fs.readFileSync(tokenFile, 'utf8').trim() : '');

const APP_ID = process.env.CM_APP_ID || cfg.codemagic.appId;
const WORKFLOW_ID = cfg.codemagic.workflowId;
const GROUP = cfg.codemagic.secretsGroup;

if (!APP_ID) {
  console.error('Set codemagic.appId in ios-app.config.json (or CM_APP_ID env)');
  process.exit(1);
}
if (!token) {
  console.error('Missing CM_API_TOKEN or signing/cm_api_token.txt');
  process.exit(1);
}

const pre = spawnSync(process.execPath, ['scripts/validate-codemagic-prereqs.mjs'], {
  cwd: repoRoot,
  stdio: 'inherit',
});
if (pre.status !== 0) {
  console.error('Preflight failed — fix before starting a macOS build.');
  process.exit(pre.status ?? 1);
}

const headers = {
  Accept: 'application/json',
  'Content-Type': 'application/json',
  'x-auth-token': token,
};

// Secrets group is declared in codemagic.yaml (budgettracker_secrets). Do not override via API.
const body = {
  appId: APP_ID,
  workflowId: WORKFLOW_ID,
  branch: process.env.CM_BRANCH || 'main',
};

const res = await fetch('https://api.codemagic.io/builds', {
  method: 'POST',
  headers,
  body: JSON.stringify(body),
});
const text = await res.text();
let json;
try {
  json = JSON.parse(text);
} catch {
  json = { raw: text };
}
if (!res.ok) {
  console.error('Trigger failed:', res.status, text.slice(0, 500));
  process.exit(1);
}

const id = json.buildId || json.build?._id || json.build?.id;
console.log('Started build:', id);
console.log('App:', cfg.displayName, '| Workflow:', WORKFLOW_ID);
if (id) console.log(`https://codemagic.io/app/${APP_ID}/build/${id}`);
