#!/usr/bin/env node
/**
 * Fetch TestFlight / ASC crash diagnostics for Budget Tracker.
 * Usage: node scripts/fetch-asc-crashes.mjs
 */
import fs from "fs";
import crypto from "crypto";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, "..");
const config = JSON.parse(fs.readFileSync(path.join(repo, "ios-app.config.json"), "utf8"));

const keyId = config.ascKeyId;
const issuerId = config.ascIssuerId;
const appId = config.ascAppId;
const p8Path = path.join(repo, "signing/certs", `AuthKey_${keyId}.p8`);
const p8 = fs.readFileSync(p8Path, "utf8");

function b64url(value) {
  const input = typeof value === "string" ? value : JSON.stringify(value);
  return Buffer.from(input).toString("base64url");
}

function jwt() {
  const now = Math.floor(Date.now() / 1000);
  const unsigned =
    b64url({ alg: "ES256", kid: keyId, typ: "JWT" }) +
    "." +
    b64url({ iss: issuerId, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" });
  const sig = crypto.createSign("SHA256").update(unsigned).sign({ key: p8, dsaEncoding: "ieee-p1363" });
  return `${unsigned}.${sig.toString("base64url")}`;
}

async function asc(pathname) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${pathname}`, {
    headers: { Authorization: `Bearer ${jwt()}`, Accept: "application/json" },
  });
  const body = await res.text();
  return { status: res.status, body, json: () => JSON.parse(body) };
}

const outDir = path.join(repo, "crash-reports");
fs.mkdirSync(outDir, { recursive: true });

console.log("App ID:", appId);

const feedback = await asc(`/v1/apps/${appId}/betaFeedbackCrashSubmissions?limit=25`);
fs.writeFileSync(path.join(outDir, "betaFeedbackCrashSubmissions.json"), feedback.body);
console.log("betaFeedbackCrashSubmissions:", feedback.status);

if (feedback.status === 200) {
  const { data = [] } = feedback.json();
  for (const item of data) {
    const id = item.id;
    const log = await asc(`/v1/betaFeedbackCrashSubmissions/${id}/crashLog`);
    const logPath = path.join(outDir, `feedback-${id}.txt`);
    fs.writeFileSync(logPath, log.body);
    console.log("  crash log", id, log.status, log.body.slice(0, 200).replace(/\n/g, " "));
  }
}

const builds = await asc(`/v1/builds?filter[app]=${appId}&limit=8&sort=-uploadedDate`);
if (builds.status !== 200) {
  console.error("builds:", builds.status, builds.body);
  process.exit(1);
}

const buildList = builds.json().data ?? [];
for (const build of buildList) {
  const buildId = build.id;
  const version = build.attributes?.version;
  console.log(`\nBuild ${version} (${buildId})`);
  for (const diagnosticType of ["LAUNCHES", "HANGS", "DISK_WRITES"]) {
    const sigs = await asc(
      `/v1/builds/${buildId}/diagnosticSignatures?filter[diagnosticType]=${diagnosticType}&limit=5`
    );
    if (sigs.status !== 200) {
      console.log(`  ${diagnosticType}: ${sigs.status}`);
      continue;
    }
    const signatures = sigs.json().data ?? [];
    if (!signatures.length) continue;
    console.log(`  ${diagnosticType}: ${signatures.length} signature(s)`);
    for (const sig of signatures) {
      const sigId = sig.id;
      const logs = await asc(`/v1/diagnosticSignatures/${sigId}/logs?limit=3`);
      const file = path.join(outDir, `build${version}-${diagnosticType}-${sigId.slice(0, 16)}.json`);
      fs.writeFileSync(file, logs.body);
      console.log("   ", sig.attributes?.signature?.slice(0, 80) ?? sigId);
      console.log("    saved", path.basename(file), "status", logs.status);
    }
  }
}

console.log("\nDone. Reports in", outDir);
console.log(
  "\nNote: If ASC returns empty but the app dies on launch on iOS 26 with supabase-swift < 2.44.0,",
  "see https://github.com/supabase/supabase-swift/issues/960 (fixed in 2.44.0)."
);
