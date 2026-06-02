export type UserCategorizationHint = {
  merchantText: string;
  category: string;
  subcategory: string | null;
};

const STOP_WORDS = new Set([
  "a",
  "an",
  "and",
  "at",
  "by",
  "for",
  "from",
  "in",
  "of",
  "on",
  "or",
  "the",
  "to",
  "us",
  "usa",
  "llc",
  "inc",
]);

const ABBREVIATIONS: Record<string, string> = {
  cr: "credit",
  pmt: "payment",
  pymt: "payment",
  xfer: "transfer",
  ach: "transfer",
  mbl: "mobile",
  mob: "mobile",
  cc: "credit card",
};

export function normalizeMerchantText(raw: string): string {
  let text = raw.toLowerCase();
  text = text.replace(/&/g, " and ");
  text = text.replace(/[^a-z0-9\s]/g, " ");
  text = text.replace(/\s+/g, " ").trim();
  const tokens = text.split(" ").filter(Boolean).map((token) =>
    ABBREVIATIONS[token] ?? token
  );
  return tokens.join(" ");
}

export function merchantTokens(raw: string): string[] {
  const normalized = normalizeMerchantText(raw);
  if (!normalized) return [];
  return normalized
    .split(" ")
    .filter((token) => token.length > 1 && !STOP_WORDS.has(token));
}

export function merchantSimilarityScore(left: string, right: string): number {
  const a = normalizeMerchantText(left);
  const b = normalizeMerchantText(right);
  if (!a || !b) return 0;
  if (a === b) return 1;

  const tokensA = merchantTokens(a);
  const tokensB = merchantTokens(b);
  if (tokensA.length === 0 || tokensB.length === 0) return 0;

  const setA = new Set(tokensA);
  const setB = new Set(tokensB);
  let intersection = 0;
  for (const token of setA) {
    if (setB.has(token)) intersection += 1;
  }
  const union = new Set([...tokensA, ...tokensB]).size;
  const jaccard = union === 0 ? 0 : intersection / union;

  const containsBoost = tokensA.every((t) => setB.has(t)) ||
      tokensB.every((t) => setA.has(t))
    ? 0.15
    : 0;

  const prefixBoost = a.startsWith(b) || b.startsWith(a) ? 0.1 : 0;

  return Math.min(1, jaccard + containsBoost + prefixBoost);
}

export function matchSimilarCategorization(
  searchText: string,
  hints: UserCategorizationHint[],
  minScore = 0.62,
): UserCategorizationHint | null {
  let best: UserCategorizationHint | null = null;
  let bestScore = minScore;

  for (const hint of hints) {
    const score = merchantSimilarityScore(searchText, hint.merchantText);
    if (score >= bestScore) {
      best = hint;
      bestScore = score;
    }
  }

  return best;
}

export function dedupeHints(hints: UserCategorizationHint[]): UserCategorizationHint[] {
  const byKey = new Map<string, UserCategorizationHint>();
  for (const hint of hints) {
    const key = normalizeMerchantText(hint.merchantText);
    if (!key) continue;
    if (!byKey.has(key)) {
      byKey.set(key, hint);
    }
  }
  return [...byKey.values()];
}
