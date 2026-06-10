import { SupabaseClient } from "npm:@supabase/supabase-js@2";

export type AggregationProvider = "plaid" | "teller";

export type LinkPolicyResponse = {
  provider: AggregationProvider;
  plaid_item_count: number;
  plaid_trial_limit: number;
  teller_configured: boolean;
  plaid: {
    environment: string;
  } | null;
  teller: {
    application_id: string;
    environment: string;
  } | null;
};

export function plaidTrialItemLimit(): number {
  const raw = Deno.env.get("PLAID_TRIAL_ITEM_LIMIT");
  const parsed = raw ? Number.parseInt(raw, 10) : 10;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 10;
}

export function tellerEnvironment(): string {
  return Deno.env.get("TELLER_ENV") ?? "sandbox";
}

export function isTellerConfigured(): boolean {
  return Boolean(Deno.env.get("TELLER_APPLICATION_ID")?.trim());
}

export function pickLinkProvider(
  plaidEnvironment: string,
  globalPlaidItemCount: number,
  tellerConfigured: boolean,
): AggregationProvider {
  if (!tellerConfigured) return "plaid";
  if (plaidEnvironment === "sandbox") return "plaid";
  if (globalPlaidItemCount < plaidTrialItemLimit()) return "plaid";
  return "teller";
}

export async function countPlaidItems(admin: SupabaseClient): Promise<number> {
  const { count, error } = await admin
    .from("plaid_items")
    .select("plaid_item_id", { count: "exact", head: true });

  if (error) throw new Error(error.message);
  return count ?? 0;
}

export async function buildLinkPolicy(
  admin: SupabaseClient,
): Promise<LinkPolicyResponse> {
  const plaidEnv = Deno.env.get("PLAID_ENV") ?? "sandbox";
  const tellerConfigured = isTellerConfigured();
  const plaidItemCount = await countPlaidItems(admin);
  const provider = pickLinkProvider(plaidEnv, plaidItemCount, tellerConfigured);

  const tellerAppId = Deno.env.get("TELLER_APPLICATION_ID")?.trim() ?? "";

  return {
    provider,
    plaid_item_count: plaidItemCount,
    plaid_trial_limit: plaidTrialItemLimit(),
    teller_configured: tellerConfigured,
    plaid: provider === "plaid" || plaidEnv === "sandbox"
      ? { environment: plaidEnv }
      : null,
    teller: provider === "teller" && tellerConfigured
      ? {
        application_id: tellerAppId,
        environment: tellerEnvironment(),
      }
      : null,
  };
}
