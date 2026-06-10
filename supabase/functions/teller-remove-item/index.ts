import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import {
  assertTellerItemOwnership,
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type RemoveBody = {
  teller_enrollment_id: string;
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "teller-remove-item", 5)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = await req.json() as RemoveBody;
    if (!body.teller_enrollment_id) {
      return jsonResponse({
        error: "teller_enrollment_id is required",
      }, 400, securityHeaders);
    }

    await assertTellerItemOwnership(
      admin,
      user.id,
      body.teller_enrollment_id,
    );

    const { data: accountRows } = await admin
      .from("accounts")
      .select("id")
      .eq("user_id", user.id)
      .eq("plaid_item_id", body.teller_enrollment_id)
      .eq("provider", "teller");

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

    await admin.rpc("delete_teller_access_token", {
      p_teller_enrollment_id: body.teller_enrollment_id,
    });

    await admin.from("teller_items")
      .delete()
      .eq("user_id", user.id)
      .eq("teller_enrollment_id", body.teller_enrollment_id);

    await writeAuditLog(admin, {
      userId: user.id,
      action: "teller_item_removed",
      resourceType: "teller_item",
      resourceId: body.teller_enrollment_id,
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
