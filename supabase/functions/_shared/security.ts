import { SupabaseClient } from "npm:@supabase/supabase-js@2";

export const securityHeaders: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "no-referrer",
  "Cache-Control": "no-store",
};

const rateBuckets = new Map<string, number[]>();

export function checkRateLimit(
  userId: string,
  endpoint: string,
  maxPerMinute = 20,
): boolean {
  const key = `${userId}:${endpoint}`;
  const now = Date.now();
  const recent = (rateBuckets.get(key) ?? []).filter((t) => now - t < 60_000);
  if (recent.length >= maxPerMinute) return false;
  recent.push(now);
  rateBuckets.set(key, recent);
  return true;
}

export function clientSafeError(error: unknown, fallback: string): string {
  if (error instanceof Error) {
    const message = error.message.toLowerCase();
    if (
      message.includes("invalid or expired session") ||
      message.includes("missing authorization") ||
      message.includes("rate limit") ||
      message.includes("required") ||
      message.includes("not found") ||
      message.includes("already linked")
    ) {
      return error.message;
    }
  }
  console.error(fallback, error);
  return fallback;
}

export async function writeAuditLog(
  admin: SupabaseClient,
  entry: {
    userId: string;
    action: string;
    resourceType?: string;
    resourceId?: string;
    metadata?: Record<string, unknown>;
  },
): Promise<void> {
  const { error } = await admin.from("security_audit_log").insert({
    user_id: entry.userId,
    action: entry.action,
    resource_type: entry.resourceType ?? null,
    resource_id: entry.resourceId ?? null,
    metadata: entry.metadata ?? null,
  });
  if (error) {
    console.error("audit_log_write_failed", error.message);
  }
}

export async function assertPlaidItemOwnership(
  admin: SupabaseClient,
  userId: string,
  plaidItemId: string,
): Promise<{ user_id: string; status: string }> {
  const { data, error } = await admin
    .from("plaid_items")
    .select("user_id, status")
    .eq("plaid_item_id", plaidItemId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data || data.user_id !== userId) {
    throw new Error("Plaid item not found");
  }
  return data;
}
