import { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { categorizeTransaction, shouldPreserveExistingCategory } from "./categorization.ts";
import { loadUserCategorizationHints } from "./user-categorization-history.ts";
import {
  mapTellerAccountType,
  mapTellerCategory,
  tellerAccountBalances,
  tellerExternalAccountId,
  tellerExternalTransactionId,
  tellerListAccounts,
  tellerListTransactions,
} from "./teller.ts";

type TellerItemRow = {
  teller_enrollment_id: string;
  user_id: string;
  last_sync_at: string | null;
};

type AccountRow = {
  id: string;
  plaid_account_id: string;
};

export type TellerSyncResult = {
  synced: number;
  categorized: number;
  items_processed: number;
};

function syncStartDate(lastSyncAt: string | null): string {
  if (lastSyncAt) {
    const date = new Date(lastSyncAt);
    date.setDate(date.getDate() - 10);
    return date.toISOString().slice(0, 10);
  }
  const start = new Date();
  start.setFullYear(start.getFullYear() - 2);
  return start.toISOString().slice(0, 10);
}

function todayISO(): string {
  return new Date().toISOString().slice(0, 10);
}

function parseAmount(value: string): number {
  const parsed = Number.parseFloat(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function isDisconnectedError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const message = error.message.toLowerCase();
  return message.includes("401") ||
    message.includes("403") ||
    message.includes("disconnected") ||
    message.includes("credentials");
}

export async function syncTellerItemsForUser(
  admin: SupabaseClient,
  userId: string,
  tellerEnrollmentId?: string,
): Promise<TellerSyncResult> {
  let itemsQuery = admin
    .from("teller_items")
    .select("teller_enrollment_id, user_id, last_sync_at")
    .eq("user_id", userId);

  if (tellerEnrollmentId) {
    itemsQuery = itemsQuery.eq("teller_enrollment_id", tellerEnrollmentId);
  }

  const { data: items, error: itemsError } = await itemsQuery;
  if (itemsError) throw new Error(itemsError.message);
  if (!items?.length) {
    return { synced: 0, categorized: 0, items_processed: 0 };
  }

  const userHints = await loadUserCategorizationHints(admin, userId);
  let synced = 0;
  let categorized = 0;
  let itemsProcessed = 0;

  for (const item of items as TellerItemRow[]) {
    const { data: accessToken, error: tokenError } = await admin.rpc(
      "get_teller_access_token",
      { p_teller_enrollment_id: item.teller_enrollment_id },
    );

    if (tokenError || !accessToken) continue;

    try {
      const tellerAccounts = await tellerListAccounts(accessToken);
      const accountRows = [];

      for (const account of tellerAccounts) {
        const mapped = mapTellerAccountType(account.type, account.subtype);
        const balances = await tellerAccountBalances(accessToken, account.id);
        accountRows.push({
          user_id: userId,
          provider: "teller",
          plaid_item_id: item.teller_enrollment_id,
          plaid_account_id: tellerExternalAccountId(account.id),
          name: account.name,
          official_name: account.institution.name,
          type: mapped.type,
          subtype: mapped.subtype,
          mask: account.last_four ?? null,
          current_balance: balances.ledger
            ? parseAmount(balances.ledger)
            : null,
          available_balance: balances.available
            ? parseAmount(balances.available)
            : null,
        });
      }

      if (accountRows.length > 0) {
        const { error: accountsError } = await admin.from("accounts").upsert(
          accountRows,
          { onConflict: "plaid_account_id" },
        );
        if (accountsError) throw new Error(accountsError.message);
      }

      const { data: dbAccounts, error: dbAccountsError } = await admin
        .from("accounts")
        .select("id, plaid_account_id")
        .eq("user_id", userId)
        .eq("provider", "teller")
        .eq("plaid_item_id", item.teller_enrollment_id);

      if (dbAccountsError) throw new Error(dbAccountsError.message);

      const accountByExternalId = new Map<string, string>(
        (dbAccounts as AccountRow[] | null ?? []).map((row) => [
          row.plaid_account_id,
          row.id,
        ]),
      );

      const startDate = syncStartDate(item.last_sync_at);
      const endDate = todayISO();

      for (const account of tellerAccounts) {
        const externalAccountId = tellerExternalAccountId(account.id);
        const accountId = accountByExternalId.get(externalAccountId);
        if (!accountId) continue;

        const txns = await tellerListTransactions(
          accessToken,
          account.id,
          startDate,
          endDate,
        );

        const upsertRows = [];

        for (const txn of txns) {
          const externalTxnId = tellerExternalTransactionId(txn.id);
          const amount = parseAmount(txn.amount);
          const merchant = txn.details?.counterparty?.name ??
            txn.description;

          const { data: existing } = await admin
            .from("transactions")
            .select("category, category_source")
            .eq("plaid_transaction_id", externalTxnId)
            .maybeSingle();

          let category = mapTellerCategory(txn.details?.category);
          let subcategory: string | null = null;
          let categorySource: string | null = "teller";

          if (shouldPreserveExistingCategory(existing)) {
            category = existing!.category!;
            categorySource = existing!.category_source ?? null;
          } else {
            const result = await categorizeTransaction(
              admin,
              userId,
              merchant,
              txn.description,
              amount,
              category,
              userHints,
              null,
            );
            category = result.category;
            subcategory = result.subcategory;
            categorySource = result.source;
            if (result.source !== "teller" && result.source !== "plaid") {
              categorized += 1;
            }
          }

          upsertRows.push({
            user_id: userId,
            account_id: accountId,
            plaid_transaction_id: externalTxnId,
            amount,
            date: txn.date,
            merchant_name: merchant,
            name: txn.description,
            category,
            subcategory,
            category_source: categorySource,
            pending: txn.status === "pending",
            is_manual: false,
          });
        }

        if (upsertRows.length > 0) {
          const { error: upsertError } = await admin.from("transactions")
            .upsert(upsertRows, { onConflict: "plaid_transaction_id" });
          if (upsertError) throw new Error(upsertError.message);
          synced += upsertRows.length;
        }
      }

      await admin.from("teller_items").update({
        status: "active",
        error_code: null,
        error_message: null,
        last_sync_at: new Date().toISOString(),
      }).eq("teller_enrollment_id", item.teller_enrollment_id);

      itemsProcessed += 1;
    } catch (error) {
      if (isDisconnectedError(error)) {
        await admin.from("teller_items").update({
          status: "login_required",
          error_code: "DISCONNECTED",
          error_message: "Bank credentials need to be refreshed in Teller Connect.",
        }).eq("teller_enrollment_id", item.teller_enrollment_id);
        continue;
      }
      throw error;
    }
  }

  return { synced, categorized, items_processed: itemsProcessed };
}
