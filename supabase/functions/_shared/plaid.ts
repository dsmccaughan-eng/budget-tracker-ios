const PLAID_ENV = Deno.env.get("PLAID_ENV") ?? "sandbox";

const PLAID_BASE_URLS: Record<string, string> = {
  sandbox: "https://sandbox.plaid.com",
  development: "https://development.plaid.com",
  production: "https://production.plaid.com",
};

export function plaidBaseUrl(): string {
  return PLAID_BASE_URLS[PLAID_ENV] ?? PLAID_BASE_URLS.sandbox;
}

export async function plaidRequest<T>(
  path: string,
  body: Record<string, unknown>,
): Promise<T> {
  const clientId = Deno.env.get("PLAID_CLIENT_ID");
  const secret = Deno.env.get("PLAID_SECRET");

  if (!clientId || !secret) {
    throw new Error("Plaid credentials are not configured");
  }

  const response = await fetch(`${plaidBaseUrl()}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "PLAID-CLIENT-ID": clientId,
      "PLAID-SECRET": secret,
    },
    body: JSON.stringify(body),
  });

  const payload = await response.json();

  if (!response.ok) {
    const message = typeof payload === "object" && payload !== null &&
        "error_message" in payload
      ? String((payload as { error_message?: string }).error_message)
      : `Plaid request failed (${response.status})`;
    throw new Error(message);
  }

  return payload as T;
}

export type PlaidAccount = {
  account_id: string;
  name: string;
  official_name: string | null;
  type: string;
  subtype: string | null;
  mask: string | null;
  balances: {
    current: number | null;
    available: number | null;
  };
};

export type PlaidTransaction = {
  transaction_id: string;
  account_id: string;
  amount: number;
  date: string;
  name: string;
  merchant_name: string | null;
  pending: boolean;
  personal_finance_category?: {
    primary?: string;
    detailed?: string;
  } | null;
};
