import { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  categorizeTransaction,
  normalizePlaidCategory,
} from "./categorization.ts";
import { plaidRequest, PlaidTransaction } from "./plaid.ts";

type SyncResponse = {
  added: PlaidTransaction[];
  modified: PlaidTransaction[];
  removed: { transaction_id: string }[];
  next_cursor: string;
  has_more: boolean;
};

type AccountRow = {
  id: string;
  plaid_account_id: string;
};

type PlaidItemRow = {
  plaid_item_id: string;
  sync_cursor: string | null;
  user_id: string;
};

export type SyncResult = {
  synced: number;
  categorized: number;
  itemsProcessed: number;
};

function isLoginRequiredError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const message = error.message.toLowerCase();
  return message.includes("item_login_required") ||
    message.includes("login required");
}

export async function syncPlaidItemsForUser(
  admin: SupabaseClient,
  userId: string,
  plaidItemId?: string,
): Promise<SyncResult> {
  let itemsQuery = admin
    .from("plaid_items")
    .select("plaid_item_id, sync_cursor, user_id")
    .eq("user_id", userId);

  if (plaidItemId) {
    itemsQuery = itemsQuery.eq("plaid_item_id", plaidItemId);
  }

  const { data: items, error: itemsError } = await itemsQuery;
  if (itemsError) throw new Error(itemsError.message);
  if (!items?.length) return { synced: 0, categorized: 0, itemsProcessed: 0 };

  const { data: accounts, error: accountsError } = await admin
    .from("accounts")
    .select("id, plaid_account_id")
    .eq("user_id", userId);

  if (accountsError) throw new Error(accountsError.message);

  const accountByPlaidId = new Map<string, string>(
    (accounts as AccountRow[] | null ?? []).map((row) => [
      row.plaid_account_id,
      row.id,
    ]),
  );

  let synced = 0;
  let categorized = 0;
  let itemsProcessed = 0;

  for (const item of items as PlaidItemRow[]) {
    const { data: accessToken, error: tokenError } = await admin.rpc(
      "get_plaid_access_token",
      { p_plaid_item_id: item.plaid_item_id },
    );

    if (tokenError || !accessToken) continue;

    try {
      let cursor = item.sync_cursor ?? undefined;
      let hasMore = true;

      while (hasMore) {
        const syncPayload = await plaidRequest<SyncResponse>(
          "/transactions/sync",
          {
            access_token: accessToken,
            cursor,
            count: 500,
          },
        );

        const upsertRows = [];

        for (const txn of [...syncPayload.added, ...syncPayload.modified]) {
          const accountId = accountByPlaidId.get(txn.account_id);
          if (!accountId) continue;

          const plaidCategory = normalizePlaidCategory(txn);
          let category = "Other";
          let subcategory: string | null = null;

          const { data: existing } = await admin
            .from("transactions")
            .select("category")
            .eq("plaid_transaction_id", txn.transaction_id)
            .maybeSingle();

          if (existing?.category && existing.category !== "Other") {
            category = existing.category;
          } else {
            const result = await categorizeTransaction(
              admin,
              userId,
              txn.merchant_name,
              txn.name,
              txn.amount,
              plaidCategory,
            );
            category = result.category;
            subcategory = result.subcategory;
            if (result.source !== "plaid") categorized += 1;
          }

          upsertRows.push({
            user_id: userId,
            account_id: accountId,
            plaid_transaction_id: txn.transaction_id,
            amount: txn.amount,
            date: txn.date,
            merchant_name: txn.merchant_name,
            name: txn.name,
            category,
            subcategory,
            pending: txn.pending,
            is_manual: false,
          });
        }

        if (upsertRows.length > 0) {
          const { error: upsertError } = await admin.from("transactions")
            .upsert(upsertRows, { onConflict: "plaid_transaction_id" });
          if (upsertError) throw new Error(upsertError.message);
          synced += upsertRows.length;
        }

        if (syncPayload.removed.length > 0) {
          const removedIds = syncPayload.removed.map((row) =>
            row.transaction_id
          );
          await admin.from("transactions")
            .delete()
            .in("plaid_transaction_id", removedIds);
        }

        cursor = syncPayload.next_cursor;
        hasMore = syncPayload.has_more;
      }

      await admin.from("plaid_items").update({
        sync_cursor: cursor,
        status: "active",
        error_code: null,
        error_message: null,
        last_sync_at: new Date().toISOString(),
      }).eq("plaid_item_id", item.plaid_item_id);

      itemsProcessed += 1;
    } catch (error) {
      if (isLoginRequiredError(error)) {
        await admin.from("plaid_items").update({
          status: "login_required",
          error_code: "ITEM_LOGIN_REQUIRED",
          error_message: "Bank credentials need to be refreshed.",
        }).eq("plaid_item_id", item.plaid_item_id);
        continue;
      }
      throw error;
    }
  }

  return { synced, categorized, itemsProcessed };
}

export async function syncPlaidItemById(
  admin: SupabaseClient,
  plaidItemId: string,
): Promise<SyncResult> {
  const { data: item, error } = await admin
    .from("plaid_items")
    .select("user_id")
    .eq("plaid_item_id", plaidItemId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!item?.user_id) return { synced: 0, categorized: 0, itemsProcessed: 0 };

  return syncPlaidItemsForUser(admin, item.user_id, plaidItemId);
}
