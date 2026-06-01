import { SupabaseClient } from "npm:@supabase/supabase-js@2";

type AccountRow = {
  id: string;
  plaid_account_id: string;
  current_balance: number | null;
  available_balance: number | null;
};

export async function recordAccountBalanceSnapshots(
  admin: SupabaseClient,
  userId: string,
  plaidAccountIds: string[],
): Promise<void> {
  if (plaidAccountIds.length === 0) return;

  const { data: accounts, error } = await admin
    .from("accounts")
    .select("id, plaid_account_id, current_balance, available_balance")
    .eq("user_id", userId)
    .in("plaid_account_id", plaidAccountIds);

  if (error) {
    console.error("account_balance_snapshot_lookup_failed", error.message);
    return;
  }

  const today = new Date().toISOString().slice(0, 10);
  const rows = (accounts as AccountRow[] | null ?? []).map((account) => ({
    user_id: userId,
    account_id: account.id,
    date: today,
    current_balance: account.current_balance,
    available_balance: account.available_balance,
  }));

  if (rows.length === 0) return;

  const { error: upsertError } = await admin
    .from("account_balance_snapshots")
    .upsert(rows, { onConflict: "user_id,account_id,date" });

  if (upsertError) {
    console.error("account_balance_snapshot_upsert_failed", upsertError.message);
  }
}
