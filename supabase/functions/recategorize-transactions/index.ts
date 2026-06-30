import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { recategorizeOtherTransactionsForUser } from "../_shared/recategorize-transactions.ts";
import {
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type RecategorizeBody = {
  since?: string;
  limit?: number;
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "recategorize-transactions", 6)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = req.method === "POST"
      ? await req.json() as RecategorizeBody
      : {};

    const result = await recategorizeOtherTransactionsForUser(admin, user.id, {
      since: body.since,
      limit: body.limit ?? 500,
    });

    if (result.updated > 0) {
      await writeAuditLog(admin, {
        userId: user.id,
        action: "transactions_recategorized",
        metadata: result,
      });
    }

    return jsonResponse(result, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to recategorize transactions."),
    }, 500, securityHeaders);
  }
});
