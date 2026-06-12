import { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { plaidRequest } from "./plaid.ts";

type PlaidInvestmentSecurity = {
  security_id: string;
  name: string | null;
  ticker_symbol: string | null;
  type: string | null;
  subtype: string | null;
  close_price: number | null;
  close_price_as_of: string | null;
  iso_currency_code: string | null;
};

type PlaidInvestmentHolding = {
  account_id: string;
  security_id: string;
  quantity: number;
  institution_price: number | null;
  institution_value: number | null;
  cost_basis: number | null;
  iso_currency_code: string | null;
};

type HoldingsResponse = {
  accounts: { account_id: string }[];
  holdings: PlaidInvestmentHolding[];
  securities: PlaidInvestmentSecurity[];
};

type PlaidInvestmentTransaction = {
  investment_transaction_id: string;
  account_id: string;
  security_id: string | null;
  date: string;
  name: string;
  quantity: number;
  amount: number;
  price: number | null;
  fees: number | null;
  type: string | null;
  subtype: string | null;
  iso_currency_code: string | null;
};

type InvestmentTransactionsResponse = {
  investment_transactions: PlaidInvestmentTransaction[];
  securities: PlaidInvestmentSecurity[];
  total_investment_transactions: number;
};

type AccountRow = {
  id: string;
  plaid_account_id: string;
};

type SecurityRow = {
  id: string;
  plaid_security_id: string;
};

export type InvestmentSyncResult = {
  holdings: number;
  transactions: number;
  items_processed: number;
  skipped_items: number;
};

const HISTORY_DAYS = 730;

function todayISO(): string {
  return new Date().toISOString().slice(0, 10);
}

function historyStartDate(): string {
  const start = new Date();
  start.setDate(start.getDate() - HISTORY_DAYS);
  return start.toISOString().slice(0, 10);
}

function isInvestmentsUnavailable(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const message = error.message.toLowerCase();
  return message.includes("product_not_ready") ||
    message.includes("products not supported") ||
    message.includes("no valid products") ||
    message.includes("investments product") ||
    message.includes("not authorized") && message.includes("investments");
}

function securityRows(
  userId: string,
  securities: PlaidInvestmentSecurity[],
) {
  return securities.map((security) => ({
    user_id: userId,
    plaid_security_id: security.security_id,
    name: security.name ?? security.ticker_symbol ?? "Security",
    ticker_symbol: security.ticker_symbol,
    type: security.type,
    subtype: security.subtype,
    close_price: security.close_price,
    close_price_as_of: security.close_price_as_of,
    iso_currency_code: security.iso_currency_code ?? "USD",
    updated_at: new Date().toISOString(),
  }));
}

async function upsertSecurities(
  admin: SupabaseClient,
  userId: string,
  securities: PlaidInvestmentSecurity[],
): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (securities.length === 0) return map;

  const uniqueById = new Map<string, PlaidInvestmentSecurity>();
  for (const security of securities) {
    uniqueById.set(security.security_id, security);
  }

  const rows = securityRows(userId, [...uniqueById.values()]);
  const { data, error } = await admin
    .from("investment_securities")
    .upsert(rows, { onConflict: "user_id,plaid_security_id" })
    .select("id, plaid_security_id");

  if (error) throw new Error(error.message);
  for (const row of (data as SecurityRow[] | null) ?? []) {
    map.set(row.plaid_security_id, row.id);
  }
  return map;
}

async function syncHoldingsForItem(
  admin: SupabaseClient,
  userId: string,
  accessToken: string,
  accountByPlaidId: Map<string, string>,
): Promise<number> {
  const payload = await plaidRequest<HoldingsResponse>(
    "/investments/holdings/get",
    { access_token: accessToken },
  );

  const securityMap = await upsertSecurities(admin, userId, payload.securities);
  const touchedAccountIds: string[] = [];

  const holdingRows = [];
  for (const holding of payload.holdings) {
    const accountId = accountByPlaidId.get(holding.account_id);
    if (!accountId) continue;
    touchedAccountIds.push(accountId);
    holdingRows.push({
      user_id: userId,
      account_id: accountId,
      security_id: securityMap.get(holding.security_id) ?? null,
      plaid_account_id: holding.account_id,
      plaid_security_id: holding.security_id,
      quantity: holding.quantity,
      institution_price: holding.institution_price,
      institution_value: holding.institution_value,
      cost_basis: holding.cost_basis,
      iso_currency_code: holding.iso_currency_code ?? "USD",
      synced_at: new Date().toISOString(),
    });
  }

  const uniqueAccountIds = [...new Set(touchedAccountIds)];
  if (uniqueAccountIds.length > 0) {
    await admin.from("investment_holdings")
      .delete()
      .eq("user_id", userId)
      .in("account_id", uniqueAccountIds);
  }

  if (holdingRows.length === 0) return 0;

  const { error } = await admin.from("investment_holdings").upsert(
    holdingRows,
    { onConflict: "user_id,account_id,plaid_security_id" },
  );
  if (error) throw new Error(error.message);
  return holdingRows.length;
}

async function syncInvestmentTransactionsForItem(
  admin: SupabaseClient,
  userId: string,
  accessToken: string,
  accountByPlaidId: Map<string, string>,
): Promise<number> {
  const startDate = historyStartDate();
  const endDate = todayISO();
  let offset = 0;
  const pageSize = 500;
  let total = Number.POSITIVE_INFINITY;
  let synced = 0;

  while (offset < total) {
    const payload = await plaidRequest<InvestmentTransactionsResponse>(
      "/investments/transactions/get",
      {
        access_token: accessToken,
        start_date: startDate,
        end_date: endDate,
        options: { count: pageSize, offset },
      },
    );

    total = payload.total_investment_transactions;
    const securityMap = await upsertSecurities(
      admin,
      userId,
      payload.securities,
    );

    const rows = [];
    for (const txn of payload.investment_transactions) {
      const accountId = accountByPlaidId.get(txn.account_id);
      if (!accountId) continue;
      rows.push({
        user_id: userId,
        account_id: accountId,
        security_id: txn.security_id
          ? securityMap.get(txn.security_id) ?? null
          : null,
        plaid_investment_transaction_id: txn.investment_transaction_id,
        plaid_account_id: txn.account_id,
        plaid_security_id: txn.security_id,
        name: txn.name,
        type: txn.type,
        subtype: txn.subtype,
        date: txn.date,
        quantity: txn.quantity,
        amount: txn.amount,
        price: txn.price,
        fees: txn.fees,
        iso_currency_code: txn.iso_currency_code ?? "USD",
      });
    }

    if (rows.length > 0) {
      const { error } = await admin.from("investment_transactions").upsert(
        rows,
        { onConflict: "user_id,plaid_investment_transaction_id" },
      );
      if (error) throw new Error(error.message);
      synced += rows.length;
    }

    if (payload.investment_transactions.length === 0) break;
    offset += payload.investment_transactions.length;
  }

  return synced;
}

export async function syncPlaidInvestmentsForUser(
  admin: SupabaseClient,
  userId: string,
  plaidItemId?: string,
): Promise<InvestmentSyncResult> {
  let itemsQuery = admin
    .from("plaid_items")
    .select("plaid_item_id, status")
    .eq("user_id", userId);

  if (plaidItemId) {
    itemsQuery = itemsQuery.eq("plaid_item_id", plaidItemId);
  }

  const { data: items, error: itemsError } = await itemsQuery;
  if (itemsError) throw new Error(itemsError.message);
  if (!items?.length) {
    return { holdings: 0, transactions: 0, items_processed: 0, skipped_items: 0 };
  }

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

  let holdings = 0;
  let transactions = 0;
  let itemsProcessed = 0;
  let skippedItems = 0;

  for (const item of items) {
    if (item.status === "revoked") {
      skippedItems += 1;
      continue;
    }

    const { data: accessToken, error: tokenError } = await admin.rpc(
      "get_plaid_access_token",
      { p_plaid_item_id: item.plaid_item_id },
    );

    if (tokenError || !accessToken) {
      skippedItems += 1;
      continue;
    }

    try {
      holdings += await syncHoldingsForItem(
        admin,
        userId,
        accessToken,
        accountByPlaidId,
      );
      transactions += await syncInvestmentTransactionsForItem(
        admin,
        userId,
        accessToken,
        accountByPlaidId,
      );
      itemsProcessed += 1;
    } catch (error) {
      if (isInvestmentsUnavailable(error)) {
        skippedItems += 1;
        continue;
      }
      throw error;
    }
  }

  return {
    holdings,
    transactions,
    items_processed: itemsProcessed,
    skipped_items: skippedItems,
  };
}
