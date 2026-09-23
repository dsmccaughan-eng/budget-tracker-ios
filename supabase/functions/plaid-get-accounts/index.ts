import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { recordAccountBalanceSnapshots } from "../_shared/account-balance-snapshots.ts";
import { syncPlaidInvestmentsForUser } from "../_shared/plaid-investments-sync.ts";
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

function isInvestmentAccountType(type: string): boolean {
  return type === "investment" || type === "brokerage";
}

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

        const plaidAccountIds = payload.accounts.map((account) => account.account_id);
        const { data: existingAccounts } = await admin
          .from("accounts")
          .select("plaid_account_id, current_balance, available_balance")
          .eq("user_id", user.id)
          .in("plaid_account_id", plaidAccountIds);
        const existingByPlaidId = new Map(
          ((existingAccounts as Array<{
            plaid_account_id: string;
            current_balance: number | null;
            available_balance: number | null;
          }> | null) ?? []).map((row) => [row.plaid_account_id, row]),
        );

        const accountRows = payload.accounts.map((account) => {
          const existing = existingByPlaidId.get(account.account_id);
          let current = account.balances.current;
          let available = account.balances.available;
          // Retirement/brokerage /accounts/get balances are often months stale.
          // Never regress a higher stored balance; holdings sync corrects next.
          if (isInvestmentAccountType(account.type) && existing) {
            if (
              existing.current_balance != null &&
              (current == null || existing.current_balance > current + 0.01)
            ) {
              current = existing.current_balance;
            }
            if (
              existing.available_balance != null &&
              (available == null || existing.available_balance > available + 0.01)
            ) {
              available = existing.available_balance;
            }
          }
          return {
            user_id: user.id,
            plaid_item_id: item.plaid_item_id,
            plaid_account_id: account.account_id,
            name: account.name,
            official_name: account.official_name,
            type: account.type,
            subtype: account.subtype,
            mask: account.mask,
            current_balance: current,
            available_balance: available,
          };
        });

        if (accountRows.length > 0) {
          await admin.from("accounts").upsert(accountRows, {
            onConflict: "plaid_account_id",
          });
          try {
            await syncPlaidInvestmentsForUser(
              admin,
              user.id,
              item.plaid_item_id,
            );
          } catch (investmentError) {
            console.error(
              "plaid_investments_sync_failed",
              item.plaid_item_id,
              investmentError,
            );
          }
          // Snapshot only after holdings sync so investment balances are current.
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
