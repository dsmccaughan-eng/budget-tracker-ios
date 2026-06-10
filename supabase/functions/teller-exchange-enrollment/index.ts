import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { recordAccountBalanceSnapshots } from "../_shared/account-balance-snapshots.ts";
import {
  mapTellerAccountType,
  tellerExternalAccountId,
  tellerListAccounts,
  tellerAccountBalances,
} from "../_shared/teller.ts";
import { syncTellerItemsForUser } from "../_shared/teller-sync.ts";
import {
  checkRateLimit,
  clientSafeError,
  securityHeaders,
  writeAuditLog,
} from "../_shared/security.ts";

type ExchangeBody = {
  access_token: string;
  enrollment_id: string;
  institution_name?: string;
};

function parseAmount(value: string | null | undefined): number | null {
  if (value == null) return null;
  const parsed = Number.parseFloat(value);
  return Number.isFinite(parsed) ? parsed : null;
}

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user, admin } = await requireUser(req);
    if (!checkRateLimit(user.id, "teller-exchange-enrollment", 5)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const body = await req.json() as ExchangeBody;

    if (!body.access_token?.trim() || !body.enrollment_id?.trim()) {
      return jsonResponse({
        error: "access_token and enrollment_id are required",
      }, 400, securityHeaders);
    }

    const enrollmentId = body.enrollment_id.trim();
    const accessToken = body.access_token.trim();

    const { data: conflictingItem } = await admin
      .from("teller_items")
      .select("user_id")
      .eq("teller_enrollment_id", enrollmentId)
      .maybeSingle();

    if (conflictingItem && conflictingItem.user_id !== user.id) {
      return jsonResponse({
        error: "This bank connection is already linked to another account.",
      }, 409, securityHeaders);
    }

    const { error: vaultError } = await admin.rpc("store_teller_access_token", {
      p_teller_enrollment_id: enrollmentId,
      p_access_token: accessToken,
    });

    if (vaultError) {
      throw new Error(`Failed to store access token: ${vaultError.message}`);
    }

    const { error: itemError } = await admin.from("teller_items").upsert(
      {
        user_id: user.id,
        teller_enrollment_id: enrollmentId,
        institution_name: body.institution_name ?? null,
        status: "active",
        error_code: null,
        error_message: null,
      },
      { onConflict: "teller_enrollment_id" },
    );

    if (itemError) {
      throw new Error(`Failed to save teller item: ${itemError.message}`);
    }

    const tellerAccounts = await tellerListAccounts(accessToken);
    const accountRows = [];

    for (const account of tellerAccounts) {
      const mapped = mapTellerAccountType(account.type, account.subtype);
      const balances = await tellerAccountBalances(accessToken, account.id);
      accountRows.push({
        user_id: user.id,
        provider: "teller",
        plaid_item_id: enrollmentId,
        plaid_account_id: tellerExternalAccountId(account.id),
        name: account.name,
        official_name: account.institution.name,
        type: mapped.type,
        subtype: mapped.subtype,
        mask: account.last_four ?? null,
        current_balance: parseAmount(balances.ledger),
        available_balance: parseAmount(balances.available),
      });
    }

    if (accountRows.length > 0) {
      const { error: accountsError } = await admin.from("accounts").upsert(
        accountRows,
        { onConflict: "plaid_account_id" },
      );
      if (accountsError) {
        throw new Error(`Failed to save accounts: ${accountsError.message}`);
      }
      await recordAccountBalanceSnapshots(
        admin,
        user.id,
        accountRows.map((row) => row.plaid_account_id),
      );
    }

    const syncResult = await syncTellerItemsForUser(admin, user.id, enrollmentId);

    await writeAuditLog(admin, {
      userId: user.id,
      action: "teller_item_linked",
      resourceType: "teller_item",
      resourceId: enrollmentId,
      metadata: {
        accounts_linked: accountRows.length,
        synced: syncResult.synced,
      },
    });

    return jsonResponse({
      enrollment_id: enrollmentId,
      accounts_linked: accountRows.length,
      synced: syncResult.synced,
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
