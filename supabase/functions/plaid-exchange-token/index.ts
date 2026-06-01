import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { plaidRequest, PlaidAccount } from "../_shared/plaid.ts";
import {
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type ExchangeBody = {
  public_token: string;
  institution_name?: string;
};

type ExchangeResponse = {
  access_token: string;
  item_id: string;
};

type AccountsResponse = {
  accounts: PlaidAccount[];
};

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "plaid-exchange-token", 5)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = await req.json() as ExchangeBody;

    if (!body.public_token) {
      return jsonResponse({ error: "public_token is required" }, 400, securityHeaders);
    }

    const exchange = await plaidRequest<ExchangeResponse>(
      "/item/public_token/exchange",
      { public_token: body.public_token },
    );

    const { data: conflictingItem } = await admin
      .from("plaid_items")
      .select("user_id")
      .eq("plaid_item_id", exchange.item_id)
      .maybeSingle();

    if (conflictingItem && conflictingItem.user_id !== user.id) {
      return jsonResponse({
        error: "This bank connection is already linked to another account.",
      }, 409, securityHeaders);
    }

    const { error: vaultError } = await admin.rpc("store_plaid_access_token", {
      p_plaid_item_id: exchange.item_id,
      p_access_token: exchange.access_token,
    });

    if (vaultError) {
      throw new Error(`Failed to store access token: ${vaultError.message}`);
    }

    const { error: itemError } = await admin.from("plaid_items").upsert(
      {
        user_id: user.id,
        plaid_item_id: exchange.item_id,
        institution_name: body.institution_name ?? null,
        status: "active",
        error_code: null,
        error_message: null,
      },
      { onConflict: "plaid_item_id" },
    );

    if (itemError) {
      throw new Error(`Failed to save plaid item: ${itemError.message}`);
    }

    const accountsPayload = await plaidRequest<AccountsResponse>(
      "/accounts/get",
      { access_token: exchange.access_token },
    );

    const accountRows = accountsPayload.accounts.map((account) => ({
      user_id: user.id,
      plaid_item_id: exchange.item_id,
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
      const { error: accountsError } = await admin.from("accounts").upsert(
        accountRows,
        { onConflict: "plaid_account_id" },
      );
      if (accountsError) {
        throw new Error(`Failed to save accounts: ${accountsError.message}`);
      }
    }

    await writeAuditLog(admin, {
      userId: user.id,
      action: "plaid_item_linked",
      resourceType: "plaid_item",
      resourceId: exchange.item_id,
      metadata: { accounts_linked: accountRows.length },
    });

    return jsonResponse({
      item_id: exchange.item_id,
      accounts_linked: accountRows.length,
    }, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to link bank account."),
    }, 500, securityHeaders);
  }
});
