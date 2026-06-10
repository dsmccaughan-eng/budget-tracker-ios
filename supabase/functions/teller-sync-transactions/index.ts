import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { syncTellerItemsForUser } from "../_shared/teller-sync.ts";
import {
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type SyncBody = {
  teller_enrollment_id?: string;
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "teller-sync-transactions", 12)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = req.method === "POST"
      ? await req.json() as SyncBody
      : {};

    const result = await syncTellerItemsForUser(
      admin,
      user.id,
      body.teller_enrollment_id,
    );

    if (result.synced > 0) {
      await writeAuditLog(admin, {
        userId: user.id,
        action: "teller_transactions_synced",
        metadata: {
          synced: result.synced,
          categorized: result.categorized,
          teller_enrollment_id: body.teller_enrollment_id ?? "all",
        },
      });
    }

    return jsonResponse({
      synced: result.synced,
      categorized: result.categorized,
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
