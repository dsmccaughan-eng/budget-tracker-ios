const TELLER_API_BASE = "https://api.teller.io";

export type TellerAccount = {
  id: string;
  name: string;
  type: string;
  subtype: string | null;
  status: string;
  institution: { id: string; name: string };
  last_four?: string | null;
  currency?: string;
  links?: Record<string, string>;
};

export type TellerTransaction = {
  id: string;
  account_id: string;
  amount: string;
  date: string;
  description: string;
  status: string;
  type: string;
  details?: {
    category?: string | null;
    counterparty?: { name?: string | null; type?: string | null } | null;
  } | null;
};

export async function tellerRequest<T>(
  path: string,
  accessToken: string,
  init: RequestInit = {},
): Promise<T> {
  const auth = btoa(`${accessToken}:`);
  const response = await fetch(`${TELLER_API_BASE}${path}`, {
    ...init,
    headers: {
      Authorization: `Basic ${auth}`,
      Accept: "application/json",
      ...(init.headers ?? {}),
    },
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Teller request failed (${response.status}): ${text}`);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return await response.json() as T;
}

export function tellerExternalAccountId(accountId: string): string {
  return `teller:${accountId}`;
}

export function tellerExternalTransactionId(transactionId: string): string {
  return `teller:${transactionId}`;
}

export function mapTellerAccountType(type: string, subtype: string | null): {
  type: string;
  subtype: string | null;
} {
  const normalized = type.toLowerCase();
  if (normalized === "credit") {
    return { type: "credit", subtype: subtype ?? "credit card" };
  }
  if (normalized === "depository") {
    return { type: "depository", subtype: subtype ?? "checking" };
  }
  if (normalized === "loan") {
    return { type: "loan", subtype: subtype };
  }
  return { type: normalized || "other", subtype };
}

export function mapTellerCategory(
  tellerCategory: string | null | undefined,
): string {
  if (!tellerCategory) return "Other";

  const map: Record<string, string> = {
    groceries: "Groceries",
    dining: "Food & Drink",
    bar: "Food & Drink",
    fuel: "Transportation",
    transport: "Transportation",
    transportation: "Transportation",
    shopping: "Shopping",
    clothing: "Shopping",
    entertainment: "Entertainment",
    sport: "Entertainment",
    health: "Healthcare",
    insurance: "Healthcare",
    utilities: "Bills & Utilities",
    service: "Bills & Utilities",
    phone: "Bills & Utilities",
    home: "Housing",
    accommodation: "Travel",
    education: "Education",
    income: "Income",
    investment: "Investments",
    loan: "Debt Payments",
    tax: "Bills & Utilities",
    charity: "Gifts & Donations",
    software: "Subscriptions",
    general: "Other",
    office: "Business",
    advertising: "Business",
    electronics: "Shopping",
  };

  return map[tellerCategory.toLowerCase()] ?? "Other";
}

export async function tellerListAccounts(
  accessToken: string,
): Promise<TellerAccount[]> {
  return await tellerRequest<TellerAccount[]>("/accounts", accessToken);
}

export async function tellerListTransactions(
  accessToken: string,
  accountId: string,
  startDate: string,
  endDate: string,
): Promise<TellerTransaction[]> {
  const params = new URLSearchParams({
    start_date: startDate,
    end_date: endDate,
  });
  return await tellerRequest<TellerTransaction[]>(
    `/accounts/${accountId}/transactions?${params.toString()}`,
    accessToken,
  );
}

export async function tellerAccountBalances(
  accessToken: string,
  accountId: string,
): Promise<{ ledger: string | null; available: string | null }> {
  try {
    return await tellerRequest<{ ledger: string | null; available: string | null }>(
      `/accounts/${accountId}/balances`,
      accessToken,
    );
  } catch {
    return { ledger: null, available: null };
  }
}
