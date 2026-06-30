import {
  matchSimilarCategorization,
  merchantSimilarityScore,
  type UserCategorizationHint,
} from "./merchant-similarity.ts";
import {
  looksLikeTransfer,
  matchesMerchantPattern,
  plaidHintsTransfer,
} from "./transfer-heuristics.ts";

export const VALID_CATEGORIES = [
  "Housing & Utilities",
  "Groceries",
  "Dining & Bars",
  "Transport",
  "Shopping",
  "Health & Wellness",
  "Travel",
  "Entertainment",
  "Subscriptions",
  "Personal Care",
  "Education",
  "Pets",
  "Gifts & Donations",
  "Insurance",
  "Investments",
  "Business",
  "Income",
  "Transfers",
  "Other",
] as const;

export type Category = typeof VALID_CATEGORIES[number];

export type CategorizationResult = {
  category: string;
  subcategory: string | null;
  source: "merchant_rule" | "merchant_db" | "gemini" | "plaid" | "user_similar";
};

const PLAID_PRIMARY_MAP: Record<string, Category> = {
  RENT_AND_UTILITIES: "Housing & Utilities",
  HOME_IMPROVEMENT: "Housing & Utilities",
  FOOD_AND_DRINK: "Dining & Bars",
  GROCERIES: "Groceries",
  TRANSPORTATION: "Transport",
  TRAVEL: "Travel",
  ENTERTAINMENT: "Entertainment",
  GENERAL_MERCHANDISE: "Shopping",
  MEDICAL: "Health & Wellness",
  PERSONAL_CARE: "Personal Care",
  EDUCATION: "Education",
  GOVERNMENT_AND_NON_PROFIT: "Gifts & Donations",
  INSURANCE: "Insurance",
  INVESTMENTS: "Investments",
  INCOME: "Income",
  TRANSFER_IN: "Transfers",
  TRANSFER_OUT: "Transfers",
  LOAN_PAYMENTS: "Transfers",
  BANK_FEES: "Other",
};

type MerchantRuleRow = {
  merchant_contains: string;
  category: string;
  subcategory: string | null;
};

type MerchantDbRow = {
  merchant_pattern: string;
  category: string;
  subcategory: string | null;
};

const FUZZY_RULE_MIN_SCORE = 0.68;

export async function categorizeTransaction(
  admin: unknown,
  userId: string,
  merchantName: string | null,
  transactionName: string,
  amount: number,
  plaidCategory: string | null,
  userHints: UserCategorizationHint[] = [],
): Promise<CategorizationResult> {
  const searchText = (merchantName ?? transactionName).toLowerCase();
  const nameText = transactionName.toLowerCase();
  const displayName = merchantName ?? transactionName;

  const matchesMerchant = (pattern: string) =>
    matchesMerchantPattern(searchText, pattern) ||
    matchesMerchantPattern(nameText, pattern);

  const { data: rules } = await (admin as {
    from: (table: string) => {
      select: (cols: string) => {
        eq: (col: string, val: string) => Promise<{ data: MerchantRuleRow[] | null }>;
      };
    };
  })
    .from("merchant_rules")
    .select("merchant_contains, category, subcategory")
    .eq("user_id", userId);

  for (const rule of rules ?? []) {
    const pattern = rule.merchant_contains.toLowerCase();
    if (searchText.includes(pattern)) {
      return {
        category: rule.category,
        subcategory: rule.subcategory,
        source: "merchant_rule",
      };
    }
  }

  let bestFuzzyRule: MerchantRuleRow | null = null;
  let bestFuzzyScore = FUZZY_RULE_MIN_SCORE;
  for (const rule of rules ?? []) {
    const score = merchantSimilarityScore(searchText, rule.merchant_contains);
    if (score >= bestFuzzyScore) {
      bestFuzzyRule = rule;
      bestFuzzyScore = score;
    }
  }
  if (bestFuzzyRule) {
    return {
      category: bestFuzzyRule.category,
      subcategory: bestFuzzyRule.subcategory,
      source: "merchant_rule",
    };
  }

  const similar = matchSimilarCategorization(searchText, userHints);
  if (similar) {
    return {
      category: similar.category,
      subcategory: similar.subcategory,
      source: "user_similar",
    };
  }

  if (looksLikeTransfer(searchText, plaidCategory) || looksLikeTransfer(nameText, plaidCategory)) {
    return {
      category: "Transfers",
      subcategory: plaidCategory,
      source: "merchant_db",
    };
  }

  const { data: merchants } = await (admin as {
    from: (table: string) => {
      select: (cols: string) => Promise<{ data: MerchantDbRow[] | null }>;
    };
  })
    .from("merchant_db")
    .select("merchant_pattern, category, subcategory");

  const sortedMerchants = (merchants ?? []).slice().sort(
    (a, b) => b.merchant_pattern.length - a.merchant_pattern.length,
  );
  for (const merchant of sortedMerchants) {
    if (matchesMerchant(merchant.merchant_pattern)) {
      return {
        category: merchant.category,
        subcategory: merchant.subcategory,
        source: "merchant_db",
      };
    }
  }

  const geminiResult = await categorizeWithGemini(
    displayName,
    amount,
    plaidCategory,
    userHints,
  );
  if (geminiResult) {
    return { ...geminiResult, source: "gemini" };
  }

  return {
    category: mapPlaidCategory(plaidCategory),
    subcategory: plaidCategory,
    source: "plaid",
  };
}

function mapPlaidCategory(raw: string | null): string {
  if (!raw) return "Other";
  if (plaidHintsTransfer(raw)) return "Transfers";
  const key = raw.toUpperCase().replace(/\s+/g, "_");
  return PLAID_PRIMARY_MAP[key] ?? "Other";
}

async function categorizeWithGemini(
  name: string,
  amount: number,
  plaidCategory: string | null,
  userHints: UserCategorizationHint[],
): Promise<{ category: string; subcategory: string | null } | null> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return null;

  const examples = userHints
    .slice(0, 12)
    .map((hint) => `- "${hint.merchantText}" → ${hint.category}`)
    .join("\n");

  const systemPrompt =
    "You are a transaction categorizer. Return ONLY valid JSON with 'category' and 'subcategory' fields. Category must be one of: [Housing & Utilities, Groceries, Dining & Bars, Transport, Shopping, Health & Wellness, Travel, Entertainment, Subscriptions, Personal Care, Education, Pets, Gifts & Donations, Insurance, Investments, Business, Income, Transfers, Other]. Credit card payments, bill pay, and account transfers are always Transfers — never Transport. When the merchant text is similar to a user example below, use that same category.";
  const userPrompt = [
    `Merchant: ${name}, Amount: $${amount}, Raw category: ${plaidCategory ?? "unknown"}`,
    examples.length > 0
      ? `\nUser's past categorizations (prefer these when the merchant is similar):\n${examples}`
      : "",
  ].join("");

  const endpoint =
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent";

  const response = await fetch(`${endpoint}?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: systemPrompt }] },
      contents: [{ parts: [{ text: userPrompt }] }],
      generationConfig: { temperature: 0.1 },
    }),
  });

  if (!response.ok) return null;

  const payload = await response.json();
  const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string") return null;

  try {
    const jsonText = extractJsonBlock(text);
    const parsed = JSON.parse(jsonText) as {
      category?: string;
      subcategory?: string | null;
    };
    if (!parsed.category || !VALID_CATEGORIES.includes(parsed.category as Category)) {
      return null;
    }
    return {
      category: parsed.category,
      subcategory: parsed.subcategory ?? null,
    };
  } catch {
    return null;
  }
}

function extractJsonBlock(text: string): string {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced?.[1]) return fenced[1].trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) return text.slice(start, end + 1);
  return text.trim();
}

export function normalizePlaidCategory(
  txn: {
    personal_finance_category?: { primary?: string; detailed?: string } | null;
  },
): string | null {
  return txn.personal_finance_category?.primary ??
    txn.personal_finance_category?.detailed ??
    null;
}
