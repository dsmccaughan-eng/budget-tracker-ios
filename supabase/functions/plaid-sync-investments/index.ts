import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { syncPlaidInvestmentsForUser } from "../_shared/plaid-investments-sync.ts";
import {
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type SyncBody = {
  plaid_item_id?: string;
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "plaid-sync-investments", 12)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = req.method === "POST"
      ? await req.json() as SyncBody
      : {};

    const result = await syncPlaidInvestmentsForUser(
      admin,
      user.id,
      body.plaid_item_id,
    );

    if (result.holdings > 0 || result.transactions > 0) {
      await writeAuditLog(admin, {
        userId: user.id,
        action: "plaid_investments_synced",
        metadata: {
          holdings: result.holdings,
          transactions: result.transactions,
          items_processed: result.items_processed,
          skipped_items: result.skipped_items,
          plaid_item_id: body.plaid_item_id ?? "all",
        },
      });
    }

    return jsonResponse(result, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to sync investments."),
    }, 500, securityHeaders);
  }
});
