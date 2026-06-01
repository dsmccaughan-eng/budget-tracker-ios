import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { createPlaidLinkToken } from "../_shared/plaid-link.ts";
import {
  assertPlaidItemOwnership,
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type UpdateLinkBody = {
  plaid_item_id: string;
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "plaid-create-update-link-token", 10)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = await req.json() as UpdateLinkBody;
    if (!body.plaid_item_id) {
      return jsonResponse({ error: "plaid_item_id is required" }, 400, securityHeaders);
    }

    await assertPlaidItemOwnership(admin, user.id, body.plaid_item_id);

    const { data: accessToken, error: tokenError } = await admin.rpc(
      "get_plaid_access_token",
      { p_plaid_item_id: body.plaid_item_id },
    );

    if (tokenError || !accessToken) {
      return jsonResponse({ error: "Unable to prepare bank reconnect." }, 404, securityHeaders);
    }

    const payload = await createPlaidLinkToken({
      userId: user.id,
      accessToken,
    });

    await writeAuditLog(admin, {
      userId: user.id,
      action: "plaid_update_link_token_created",
      resourceType: "plaid_item",
      resourceId: body.plaid_item_id,
    });

    return jsonResponse({
      link_token: payload.link_token,
      expiration: payload.expiration,
    }, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to start bank reconnect."),
    }, 500, securityHeaders);
  }
});
