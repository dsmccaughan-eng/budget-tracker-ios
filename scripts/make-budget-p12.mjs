import fs from "fs";
import crypto from "crypto";
import { execFileSync } from "child_process";

const repo = "C:/Users/dsmcc/Projects/Users/m1/Desktop/BudgetTracker";
const opt = "C:/Users/dsmcc/Projects/Users/m1/Desktop/Optimized/signing/certs";
const openssl = "C:/Program Files/Git/usr/bin/openssl.exe";

const p8 = fs.readFileSync(`${repo}/signing/certs/AuthKey_N99V63R65U.p8`, "utf8");
const b64url = (x) => Buffer.from(x).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const data =
  b64url(JSON.stringify({ alg: "ES256", kid: "N99V63R65U", typ: "JWT" })) +
  "." +
  b64url(
    JSON.stringify({
      iss: "aac249cb-4e46-49a0-832f-446a6bdba91d",
      exp: now + 1200,
      aud: "appstoreconnect-v1",
    })
  );
const sig = crypto
  .sign("sha256", Buffer.from(data), { key: p8, dsaEncoding: "ieee-p1363" })
  .toString("base64url");
const jwt = `${data}.${sig}`;
const headers = { Authorization: `Bearer ${jwt}` };

const profiles = await fetch("https://api.appstoreconnect.apple.com/v1/profiles?limit=200", {
  headers,
}).then((r) => r.json());
const profile = (profiles.data || []).find(
  (x) => x.attributes?.name === "Budget Tracker Distribution"
);
if (!profile) throw new Error("Profile not found: Budget Tracker Distribution");

const certs = await fetch(
  `https://api.appstoreconnect.apple.com/v1/profiles/${profile.id}/certificates`,
  { headers }
).then((r) => r.json());
const certId = certs.data?.[0]?.id;
if (!certId) throw new Error("No certificate attached to profile");

const cert = await fetch(`https://api.appstoreconnect.apple.com/v1/certificates/${certId}`, {
  headers,
}).then((r) => r.json());

fs.mkdirSync(`${repo}/signing/certs`, { recursive: true });
const derPath = `${repo}/signing/certs/budget_distribution.cer`;
const pemPath = `${repo}/signing/certs/budget_distribution.pem`;
fs.writeFileSync(derPath, Buffer.from(cert.data.attributes.certificateContent, "base64"));

execFileSync(openssl, ["x509", "-inform", "DER", "-in", derPath, "-out", pemPath]);
const certMod = execFileSync(openssl, ["x509", "-noout", "-modulus", "-in", pemPath])
  .toString()
  .trim();

let keyPath = "";
for (const keyFile of ["distribution_new.key", "distribution.key"]) {
  const full = `${opt}/${keyFile}`;
  if (!fs.existsSync(full)) continue;
  try {
    const keyMod = execFileSync(openssl, ["rsa", "-noout", "-modulus", "-in", full])
      .toString()
      .trim();
    if (keyMod === certMod) {
      keyPath = full;
      break;
    }
  } catch {
    // ignore non-matching key parse issues
  }
}
if (!keyPath) throw new Error("No matching private key found in Optimized/signing/certs");

const p12Path = `${repo}/signing/certs/distribution_codemagic.p12`;
const password = "BudgetCM2026!";
execFileSync(openssl, [
  "pkcs12",
  "-export",
  "-inkey",
  keyPath,
  "-in",
  pemPath,
  "-out",
  p12Path,
  "-passout",
  `pass:${password}`,
]);

console.log(`MATCH_KEY=${keyPath}`);
console.log(`P12=${p12Path}`);
console.log(`P12_PASSWORD=${password}`);
