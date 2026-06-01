import { plaidRequest } from "./plaid.ts";

type LinkTokenResponse = {
  link_token: string;
  expiration: string;
};

export function plaidWebhookUrl(): string | undefined {
  return Deno.env.get("PLAID_WEBHOOK_URL") ?? undefined;
}

export function plaidRedirectUri(): string | undefined {
  return Deno.env.get("PLAID_REDIRECT_URI") ?? undefined;
}

export async function createPlaidLinkToken(options: {
  userId: string;
  accessToken?: string;
}): Promise<LinkTokenResponse> {
  const body: Record<string, unknown> = {
    user: { client_user_id: options.userId },
    client_name: "Budget Tracker",
    products: ["transactions"],
    country_codes: ["US"],
    language: "en",
    transactions: { days_requested: 730 },
  };

  const webhook = plaidWebhookUrl();
  if (webhook) body.webhook = webhook;

  const redirectUri = plaidRedirectUri();
  if (redirectUri) body.redirect_uri = redirectUri;

  if (options.accessToken) {
    body.access_token = options.accessToken;
  }

  return await plaidRequest<LinkTokenResponse>("/link/token/create", body);
}
