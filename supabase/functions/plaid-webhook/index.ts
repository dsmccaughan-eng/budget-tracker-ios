import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { syncPlaidItemById } from "../_shared/plaid-sync.ts";
import { securityHeaders } from "../_shared/security.ts";
import { verifyPlaidWebhook } from "../_shared/webhook-verify.ts";

type PlaidWebhookPayload = {
  webhook_type?: string;
  webhook_code?: string;
  item_id?: string;
  error?: {
    error_code?: string;
    error_message?: string;
  };
};

const SYNC_WEBHOOK_CODES = new Set([
  "SYNC_UPDATES_AVAILABLE",
  "DEFAULT_UPDATE",
  "INITIAL_UPDATE",
  "HISTORICAL_UPDATE",
  "TRANSACTIONS_REMOVED",
]);

const ITEM_STATUS_BY_CODE: Record<string, string> = {
  ERROR: "error",
  PENDING_DISCONNECT: "pending_disconnect",
  USER_PERMISSION_REVOKED: "revoked",
  LOGIN_REPAIRED: "active",
};

function adminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Server configuration error");
  }
  return createClient(supabaseUrl, serviceRoleKey);
}

async function sha256Hex(rawBody: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(rawBody),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405, securityHeaders);
  }

  const rawBody = await req.text();

  try {
    const verified = await verifyPlaidWebhook(req, rawBody);
    if (!verified) {
      return jsonResponse({ error: "Invalid webhook signature" }, 401, securityHeaders);
    }

    const payload = JSON.parse(rawBody) as PlaidWebhookPayload;
    const itemId = payload.item_id;
    if (!itemId || !payload.webhook_type || !payload.webhook_code) {
      return jsonResponse({ received: true }, 200, securityHeaders);
    }

    const admin = adminClient();
    const payloadHash = await sha256Hex(rawBody);

    const { error: insertError } = await admin.from("plaid_webhook_events").insert({
      plaid_item_id: itemId,
      webhook_type: payload.webhook_type,
      webhook_code: payload.webhook_code,
      payload_hash: payloadHash,
    });

    if (insertError?.code === "23505") {
      return jsonResponse({ received: true, duplicate: true }, 200, securityHeaders);
    }
    if (insertError) {
      throw new Error(insertError.message);
    }

    await admin.from("plaid_items").update({
      last_webhook_at: new Date().toISOString(),
    }).eq("plaid_item_id", itemId);

    if (payload.webhook_type === "ITEM") {
      const status = ITEM_STATUS_BY_CODE[payload.webhook_code] ??
        (payload.webhook_code === "ERROR" ? "error" : undefined);

      if (status) {
        await admin.from("plaid_items").update({
          status,
          error_code: payload.error?.error_code ?? payload.webhook_code,
          error_message: payload.error?.error_message ??
            (status === "login_required"
              ? "Bank credentials need to be refreshed."
              : null),
        }).eq("plaid_item_id", itemId);
      }

      if (payload.webhook_code === "ERROR" &&
        payload.error?.error_code === "ITEM_LOGIN_REQUIRED") {
        await admin.from("plaid_items").update({
          status: "login_required",
          error_code: payload.error.error_code,
          error_message: payload.error.error_message ??
            "Bank credentials need to be refreshed.",
        }).eq("plaid_item_id", itemId);
      }
    }

    let syncTriggered = false;
    if (
      payload.webhook_type === "TRANSACTIONS" &&
      SYNC_WEBHOOK_CODES.has(payload.webhook_code)
    ) {
      await syncPlaidItemById(admin, itemId);
      syncTriggered = true;
    }

    await admin.from("plaid_webhook_events").update({ sync_triggered: syncTriggered })
      .eq("payload_hash", payloadHash);

    return jsonResponse({ received: true, sync_triggered: syncTriggered }, 200, securityHeaders);
  } catch (error) {
    console.error("plaid_webhook_failed", error);
    return jsonResponse({ error: "Webhook processing failed" }, 500, securityHeaders);
  }
});
