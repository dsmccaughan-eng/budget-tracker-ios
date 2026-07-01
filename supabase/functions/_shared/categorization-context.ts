import { normalizeMerchantText } from "./merchant-similarity.ts";

export type ExistingCategoryRow = {
  category: string | null;
  category_source: string | null;
};

export function transactionSearchTexts(
  merchantName: string | null,
  transactionName: string,
): string[] {
  const merchant = merchantName?.trim() ?? "";
  const name = transactionName?.trim() ?? "";
  const texts: string[] = [];
  if (merchant) texts.push(merchant);
  if (name) texts.push(name);
  if (merchant && name) texts.push(`${merchant} ${name}`);
  return texts;
}

export function normalizedSearchTexts(
  merchantName: string | null,
  transactionName: string,
): string[] {
  const seen = new Set<string>();
  for (const text of transactionSearchTexts(merchantName, transactionName)) {
    const normalized = normalizeMerchantText(text);
    if (normalized) seen.add(normalized);
  }
  return [...seen];
}

export function shouldPreserveExistingCategory(
  existing: ExistingCategoryRow | null | undefined,
): boolean {
  if (!existing?.category) return false;
  if (
    existing.category_source === "user" ||
    existing.category_source === "merchant_rule"
  ) {
    return true;
  }
  return existing.category !== "Other";
}

export function extractPlaidCategoryLabels(txn: {
  personal_finance_category?: { primary?: string; detailed?: string } | null;
}): { primary: string | null; detailed: string | null } {
  return {
    primary: txn.personal_finance_category?.primary ?? null,
    detailed: txn.personal_finance_category?.detailed ?? null,
  };
}
