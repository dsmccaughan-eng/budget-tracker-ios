import { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { categorizeTransaction } from "./categorization.ts";
import { loadUserCategorizationHints } from "./user-categorization-history.ts";

type TransactionRow = {
  id: string;
  merchant_name: string | null;
  name: string;
  amount: number;
  subcategory: string | null;
  category: string;
  category_source: string | null;
};

export type RecategorizeResult = {
  scanned: number;
  updated: number;
  categorized: number;
};

/** Re-run categorization for Plaid rows stuck at default Other. */
export async function recategorizeOtherTransactionsForUser(
  admin: SupabaseClient,
  userId: string,
  options?: { since?: string; limit?: number },
): Promise<RecategorizeResult> {
  const limit = options?.limit ?? 500;

  let idQuery = admin
    .from("transactions")
    .select("id")
    .eq("user_id", userId)
    .eq("category", "Other")
    .eq("is_manual", false)
    .or("category_source.is.null,category_source.eq.plaid")
    .order("date", { ascending: false })
    .limit(limit);

  if (options?.since) {
    idQuery = idQuery.gte("date", options.since);
  }

  const { data: idRows, error: idError } = await idQuery;
  if (idError) throw new Error(idError.message);
  if (!idRows?.length) {
    return { scanned: 0, updated: 0, categorized: 0 };
  }

  const userHints = await loadUserCategorizationHints(admin, userId);

  let scanned = 0;
  let updated = 0;
  let categorized = 0;

  for (const { id } of idRows) {
    const { data: row, error: rowError } = await admin
      .from("transactions")
      .select(
        "id, merchant_name, name, amount, subcategory, category, category_source",
      )
      .eq("id", id)
      .maybeSingle();

    if (rowError) throw new Error(rowError.message);
    if (!row) continue;

    const txn = row as TransactionRow;
    if (txn.category !== "Other") continue;
    if (txn.category_source === "user") continue;

    scanned += 1;

    const result = await categorizeTransaction(
      admin,
      userId,
      txn.merchant_name,
      txn.name,
      txn.amount,
      txn.subcategory,
      userHints,
    );

    if (result.category !== "Other" || result.source !== "plaid") {
      categorized += 1;
    }

    const { error: updateError } = await admin
      .from("transactions")
      .update({
        category: result.category,
        subcategory: result.subcategory,
        category_source: result.source,
      })
      .eq("id", txn.id);

    if (updateError) throw new Error(updateError.message);
    updated += 1;
  }

  return { scanned, updated, categorized };
}
