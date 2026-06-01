import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { plaidRequest } from "../_shared/plaid.ts";
import {
  assertPlaidItemOwnership,
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type RemoveBody = {
  plaid_item_id: string;
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "plaid-remove-item", 5)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = await req.json() as RemoveBody;
    if (!body.plaid_item_id) {
      return jsonResponse({ error: "plaid_item_id is required" }, 400, securityHeaders);
    }

    await assertPlaidItemOwnership(admin, user.id, body.plaid_item_id);

    const { data: accessToken } = await admin.rpc(
      "get_plaid_access_token",
      { p_plaid_item_id: body.plaid_item_id },
    );

    if (accessToken) {
      try {
        await plaidRequest("/item/remove", { access_token: accessToken });
      } catch (error) {
        console.error("plaid_item_remove_failed", body.plaid_item_id, error);
      }
    }

    const { data: accountRows } = await admin
      .from("accounts")
      .select("id")
      .eq("user_id", user.id)
      .eq("plaid_item_id", body.plaid_item_id);

    const accountIds = (accountRows ?? []).map((row) => row.id);
    if (accountIds.length > 0) {
      await admin.from("transactions")
        .delete()
        .eq("user_id", user.id)
        .in("account_id", accountIds);
      await admin.from("accounts")
        .delete()
        .eq("user_id", user.id)
        .in("id", accountIds);
    }

    await admin.rpc("delete_plaid_access_token", {
      p_plaid_item_id: body.plaid_item_id,
    });

    await admin.from("plaid_items")
      .delete()
      .eq("user_id", user.id)
      .eq("plaid_item_id", body.plaid_item_id);

    await writeAuditLog(admin, {
      userId: user.id,
      action: "plaid_item_removed",
      resourceType: "plaid_item",
      resourceId: body.plaid_item_id,
      metadata: { accounts_removed: accountIds.length },
    });

    return jsonResponse({ removed: true }, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to disconnect bank."),
    }, 500, securityHeaders);
  }
});
