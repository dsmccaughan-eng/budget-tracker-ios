import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { syncPlaidItemsForUser } from "../_shared/plaid-sync.ts";
import { syncTellerItemsForUser } from "../_shared/teller-sync.ts";
import { isTellerConfigured } from "../_shared/connection-policy.ts";
import { recategorizeOtherTransactionsForUser } from "../_shared/recategorize-transactions.ts";
import {
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "aggregation-sync-transactions", 12)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const plaidResult = await syncPlaidItemsForUser(admin, user.id);
    const tellerResult = isTellerConfigured()
      ? await syncTellerItemsForUser(admin, user.id)
      : { synced: 0, categorized: 0, items_processed: 0 };

    const synced = plaidResult.synced + tellerResult.synced;
    const categorized = plaidResult.categorized + tellerResult.categorized;

    const recategorized = await recategorizeOtherTransactionsForUser(admin, user.id, {
      limit: 250,
    });

    if (synced > 0) {
      await writeAuditLog(admin, {
        userId: user.id,
        action: "aggregation_transactions_synced",
        metadata: {
          synced,
          categorized,
          plaid_synced: plaidResult.synced,
          teller_synced: tellerResult.synced,
          recategorized: recategorized.categorized,
        },
      });
    }

    return jsonResponse({
      synced,
      categorized,
      recategorized: recategorized.categorized,
      recategorized_updated: recategorized.updated,
    }, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to sync transactions."),
    }, 500, securityHeaders);
  }
});
