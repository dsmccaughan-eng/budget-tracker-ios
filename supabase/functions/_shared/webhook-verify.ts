import * as jose from "npm:jose@5";
import { plaidRequest } from "./plaid.ts";

type VerificationKeyResponse = {
  key: jose.JWK;
};

const cachedKeys = new Map<string, jose.KeyLike>();

async function sha256Hex(rawBody: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(rawBody),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let i = 0; i < left.length; i += 1) {
    mismatch |= left.charCodeAt(i) ^ right.charCodeAt(i);
  }
  return mismatch === 0;
}

export async function verifyPlaidWebhook(
  req: Request,
  rawBody: string,
): Promise<boolean> {
  const verificationHeader = req.headers.get("Plaid-Verification") ??
    req.headers.get("plaid-verification");
  if (!verificationHeader) return false;

  const header = jose.decodeProtectedHeader(verificationHeader);
  if (header.alg !== "ES256" || !header.kid) return false;

  let verificationKey = cachedKeys.get(header.kid);
  if (!verificationKey) {
    const keyResponse = await plaidRequest<VerificationKeyResponse>(
      "/webhook_verification_key/get",
      { key_id: header.kid },
    );
    verificationKey = await jose.importJWK(keyResponse.key, "ES256");
    cachedKeys.set(header.kid, verificationKey);
  }

  const { payload } = await jose.jwtVerify(verificationHeader, verificationKey, {
    maxTokenAge: "5 min",
  });

  const expectedHash = String(payload.request_body_sha256 ?? "");
  const actualHash = await sha256Hex(rawBody);
  return timingSafeEqual(expectedHash, actualHash);
}
