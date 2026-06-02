import { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  dedupeHints,
  type UserCategorizationHint,
} from "./merchant-similarity.ts";

type MerchantRuleRow = {
  merchant_contains: string;
  category: string;
  subcategory: string | null;
};

type TransactionRow = {
  merchant_name: string | null;
  name: string;
  category: string;
  subcategory: string | null;
  date: string;
};

export async function loadUserCategorizationHints(
  admin: SupabaseClient,
  userId: string,
): Promise<UserCategorizationHint[]> {
  const hints: UserCategorizationHint[] = [];

  const { data: rules } = await admin
    .from("merchant_rules")
    .select("merchant_contains, category, subcategory")
    .eq("user_id", userId);

  for (const rule of (rules as MerchantRuleRow[] | null) ?? []) {
    hints.push({
      merchantText: rule.merchant_contains,
      category: rule.category,
      subcategory: rule.subcategory,
    });
  }

  const { data: transactions } = await admin
    .from("transactions")
    .select("merchant_name, name, category, subcategory, date")
    .eq("user_id", userId)
    .in("category_source", ["user", "merchant_rule", "user_similar"])
    .order("date", { ascending: false })
    .limit(300);

  for (const txn of (transactions as TransactionRow[] | null) ?? []) {
    const label = (txn.merchant_name?.trim() || txn.name?.trim() || "").trim();
    if (!label) continue;
    hints.push({
      merchantText: label,
      category: txn.category,
      subcategory: txn.subcategory,
    });
  }

  return dedupeHints(hints);
}
