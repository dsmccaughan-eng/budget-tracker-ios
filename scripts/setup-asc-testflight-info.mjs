#!/usr/bin/env node
/**
 * Set TestFlight Beta App Information via App Store Connect API.
 * Usage:
 *   node scripts/setup-asc-testflight-info.mjs
 *   node scripts/setup-asc-testflight-info.mjs --dry-run
 *
 * Env overrides (optional):
 *   ASC_FEEDBACK_EMAIL, ASC_CONTACT_EMAIL, ASC_CONTACT_FIRST, ASC_CONTACT_LAST, ASC_CONTACT_PHONE
 */
import fs from "fs";
import crypto from "crypto";
import path from "path";
import { fileURLToPath } from "url";
import { loadIosAppConfig, repoRootFromScript } from "./load-ios-app-config.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = repoRootFromScript(import.meta.url);
const cfg = loadIosAppConfig(repoRoot);
const dryRun = process.argv.includes("--dry-run");
const inspectOnly = process.argv.includes("--inspect");

const defaults = {
  feedbackEmail: process.env.ASC_FEEDBACK_EMAIL ?? "dsmccaughan@gmail.com",
  contactEmail: process.env.ASC_CONTACT_EMAIL ?? "dsmccaughan@gmail.com",
  contactFirstName: process.env.ASC_CONTACT_FIRST ?? "Dylan",
  contactLastName: process.env.ASC_CONTACT_LAST ?? "McCaughan",
  contactPhone: process.env.ASC_CONTACT_PHONE ?? "",
};

const p8Path = path.join(repoRoot, "signing", "certs", `AuthKey_${cfg.ascKeyId}.p8`);
const p8 = fs.readFileSync(p8Path, "utf8");

function b64url(value) {
  const input = typeof value === "string" ? value : JSON.stringify(value);
  return Buffer.from(input).toString("base64url");
}

function jwt() {
  const now = Math.floor(Date.now() / 1000);
  const unsigned =
    b64url({ alg: "ES256", kid: cfg.ascKeyId, typ: "JWT" }) +
    "." +
    b64url({ iss: cfg.ascIssuerId, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" });
  const sig = crypto.createSign("SHA256").update(unsigned).sign({ key: p8, dsaEncoding: "ieee-p1363" });
  return `${unsigned}.${sig.toString("base64url")}`;
}

async function asc(method, pathname, body) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${pathname}`, {
    method,
    headers: {
      Authorization: `Bearer ${jwt()}`,
      Accept: "application/json",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  return { status: res.status, text, json };
}

function fail(msg, detail) {
  console.error(msg);
  if (detail) console.error(detail);
  process.exit(1);
}

if (!inspectOnly && !defaults.contactPhone) {
  fail(
    "ASC_CONTACT_PHONE is required (E.164, e.g. +14085551234).",
    "Set env ASC_CONTACT_PHONE and re-run."
  );
}

const appId = cfg.ascAppId;
console.log("App Store Connect app:", appId);

const locRes = await asc("GET", `/v1/apps/${appId}/betaAppLocalizations`);
if (locRes.status !== 200) fail("betaAppLocalizations GET failed", locRes.text);

let localizations = locRes.json?.data ?? [];

async function createDefaultLocalization() {
  const locale = process.env.ASC_BETA_LOCALE ?? "en-US";
  const payload = {
    data: {
      type: "betaAppLocalizations",
      attributes: {
        locale,
        feedbackEmail: defaults.feedbackEmail,
      },
      relationships: {
        app: { data: { type: "apps", id: appId } },
      },
    },
  };
  if (dryRun || inspectOnly) {
    console.log(`\nWould POST betaAppLocalization locale=${locale}`);
    return null;
  }
  const created = await asc("POST", "/v1/betaAppLocalizations", payload);
  if (created.status === 403) {
    fail(
      "betaAppLocalizations POST forbidden — API key role cannot edit Test Information.",
      "In developer.apple.com → Keys, use Admin or App Manager for this key, or fill Test Information in the ASC web UI (see docs/TESTFLIGHT_SETUP.md § F)."
    );
  }
  if (created.status !== 201) fail("betaAppLocalizations POST failed", created.text);
  const row = created.json?.data;
  console.log(`\nCreated betaAppLocalization ${locale} (${row?.id})`);
  return row;
}

if (!localizations.length) {
  console.log("\nNo betaAppLocalizations yet (ASC UI Test Information stays empty until one exists).");
  const created = await createDefaultLocalization();
  if (created) localizations = [created];
}

for (const loc of localizations) {
  const locale = loc.attributes?.locale ?? loc.id;
  const currentFeedback = loc.attributes?.feedbackEmail;
  console.log(`\nLocalization ${locale} (${loc.id})`);
  console.log("  current feedbackEmail:", currentFeedback ?? "(empty)");

  if (inspectOnly) continue;

  if (currentFeedback === defaults.feedbackEmail) {
    console.log("  feedbackEmail already set — skip");
    continue;
  }

  const payload = {
    data: {
      type: "betaAppLocalizations",
      id: loc.id,
      attributes: { feedbackEmail: defaults.feedbackEmail },
    },
  };

  if (dryRun) {
    console.log("  [dry-run] would PATCH feedbackEmail");
    continue;
  }

  const patch = await asc("PATCH", `/v1/betaAppLocalizations/${loc.id}`, payload);
  if (patch.status !== 200) fail(`betaAppLocalizations PATCH failed (${locale})`, patch.text);
  console.log("  updated feedbackEmail →", defaults.feedbackEmail);
}

const reviewRes = await asc("GET", `/v1/apps/${appId}/betaAppReviewDetail`);
if (reviewRes.status !== 200) fail("betaAppReviewDetail GET failed", reviewRes.text);

const review = reviewRes.json?.data;
if (!review?.id) fail("No betaAppReviewDetail on app");

const attrs = review.attributes ?? {};
console.log("\nbetaAppReviewDetail", review.id);
console.log("  current:", {
  contactFirstName: attrs.contactFirstName,
  contactLastName: attrs.contactLastName,
  contactPhone: attrs.contactPhone,
  contactEmail: attrs.contactEmail,
});

const reviewPayload = {
  data: {
    type: "betaAppReviewDetails",
    id: review.id,
    attributes: {
      contactFirstName: defaults.contactFirstName,
      contactLastName: defaults.contactLastName,
      contactPhone: defaults.contactPhone,
      contactEmail: defaults.contactEmail,
    },
  },
};

const reviewComplete =
  attrs.contactFirstName === defaults.contactFirstName &&
  attrs.contactLastName === defaults.contactLastName &&
  attrs.contactPhone === defaults.contactPhone &&
  attrs.contactEmail === defaults.contactEmail;

if (inspectOnly) {
  // listing only
} else if (reviewComplete) {
  console.log("  review contact already complete — skip");
} else if (dryRun) {
  console.log("  [dry-run] would PATCH review contact");
} else {
  const patchReview = await asc("PATCH", `/v1/betaAppReviewDetails/${review.id}`, reviewPayload);
  if (patchReview.status === 403) {
    fail(
      "betaAppReviewDetails PATCH forbidden — API key role cannot edit Beta App Review contact.",
      "Use Admin/App Manager API key or fill fields in ASC → TestFlight → Test Information."
    );
  }
  if (patchReview.status !== 200) fail("betaAppReviewDetails PATCH failed", patchReview.text);
  console.log("  updated review contact");
}

const buildsRes = await asc(
  "GET",
  `/v1/builds?filter[app]=${appId}&limit=5&sort=-uploadedDate&include=preReleaseVersion,betaBuildLocalizations`
);
console.log("\nRecent builds:");
if (buildsRes.status !== 200) {
  console.log("  (could not list builds)", buildsRes.status);
} else {
  for (const b of buildsRes.json?.data ?? []) {
    const a = b.attributes ?? {};
    let betaState = "";
    if (inspectOnly) {
      const detail = await asc("GET", `/v1/builds/${b.id}/buildBetaDetail`);
      if (detail.status === 200 && detail.json?.data?.attributes) {
        const d = detail.json.data.attributes;
        betaState = ` internal=${d.internalBuildState} external=${d.externalBuildState}`;
      }
    }
    console.log(
      `  v${a.version ?? "?"} (${b.id}) uploaded=${a.uploadedDate} processing=${a.processingState} expired=${a.expired}${betaState}`
    );
  }
}

console.log("\nDone. Open TestFlight in App Store Connect and enable Internal Testing on the latest build.");
console.log("https://appstoreconnect.apple.com/apps/" + appId + "/testflight/ios");
