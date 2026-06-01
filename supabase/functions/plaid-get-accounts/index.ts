import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { recordAccountBalanceSnapshots } from "../_shared/account-balance-snapshots.ts";
import { plaidRequest, PlaidAccount } from "../_shared/plaid.ts";
import {
  assertPlaidItemOwnership,
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type AccountsResponse = {
  accounts: PlaidAccount[];
};

type RequestBody = {
  plaid_item_id?: string;
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "plaid-get-accounts", 20)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = req.method === "POST"
      ? await req.json() as RequestBody
      : {};

    let query = admin
      .from("plaid_items")
      .select("plaid_item_id, status")
      .eq("user_id", user.id);

    if (body.plaid_item_id) {
      await assertPlaidItemOwnership(admin, user.id, body.plaid_item_id);
      query = query.eq("plaid_item_id", body.plaid_item_id);
    }

    const { data: items, error: itemsError } = await query;
    if (itemsError) {
      throw new Error(itemsError.message);
    }
    if (!items?.length) {
      return jsonResponse({ accounts: [] }, 200, securityHeaders);
    }

    const allAccounts: PlaidAccount[] = [];

    for (const item of items) {
      if (item.status === "revoked") continue;

      const { data: token, error: tokenError } = await admin.rpc(
        "get_plaid_access_token",
        { p_plaid_item_id: item.plaid_item_id },
      );

      if (tokenError || !token) {
        continue;
      }

      try {
        const payload = await plaidRequest<AccountsResponse>("/accounts/get", {
          access_token: token,
        });

        allAccounts.push(...payload.accounts);

        const accountRows = payload.accounts.map((account) => ({
          user_id: user.id,
          plaid_item_id: item.plaid_item_id,
          plaid_account_id: account.account_id,
          name: account.name,
          official_name: account.official_name,
          type: account.type,
          subtype: account.subtype,
          mask: account.mask,
          current_balance: account.balances.current,
          available_balance: account.balances.available,
        }));

        if (accountRows.length > 0) {
          await admin.from("accounts").upsert(accountRows, {
            onConflict: "plaid_account_id",
          });
          await recordAccountBalanceSnapshots(
            admin,
            user.id,
            accountRows.map((row) => row.plaid_account_id),
          );
        }
      } catch (error) {
        console.error("plaid_get_accounts_failed", item.plaid_item_id, error);
      }
    }

    return jsonResponse({ accounts: allAccounts }, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to refresh accounts."),
    }, 500, securityHeaders);
  }
});
