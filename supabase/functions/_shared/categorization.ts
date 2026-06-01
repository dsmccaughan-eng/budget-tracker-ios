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
  source: "merchant_rule" | "merchant_db" | "gemini" | "plaid";
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

export async function categorizeTransaction(
  admin: {
    from: (table: string) => {
      select: (cols: string) => {
        eq: (
          col: string,
          val: string,
        ) => {
          ilike?: (
            col: string,
            pattern: string,
          ) => Promise<{ data: MerchantRuleRow[] | null }>;
        };
      };
    };
  },
  userId: string,
  merchantName: string | null,
  transactionName: string,
  amount: number,
  plaidCategory: string | null,
): Promise<CategorizationResult> {
  const searchText = (merchantName ?? transactionName).toLowerCase();

  const { data: rules } = await admin
    .from("merchant_rules")
    .select("merchant_contains, category, subcategory")
    .eq("user_id", userId) as { data: MerchantRuleRow[] | null };

  for (const rule of rules ?? []) {
    if (searchText.includes(rule.merchant_contains.toLowerCase())) {
      return {
        category: rule.category,
        subcategory: rule.subcategory,
        source: "merchant_rule",
      };
    }
  }

  const { data: merchants } = await admin
    .from("merchant_db")
    .select("merchant_pattern, category, subcategory") as {
      data: MerchantDbRow[] | null;
    };

  for (const merchant of merchants ?? []) {
    if (searchText.includes(merchant.merchant_pattern.toLowerCase())) {
      return {
        category: merchant.category,
        subcategory: merchant.subcategory,
        source: "merchant_db",
      };
    }
  }

  const geminiResult = await categorizeWithGemini(
    merchantName ?? transactionName,
    amount,
    plaidCategory,
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
  const key = raw.toUpperCase().replace(/\s+/g, "_");
  return PLAID_PRIMARY_MAP[key] ?? "Other";
}

async function categorizeWithGemini(
  name: string,
  amount: number,
  plaidCategory: string | null,
): Promise<{ category: string; subcategory: string | null } | null> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return null;

  const systemPrompt =
    "You are a transaction categorizer. Return ONLY valid JSON with 'category' and 'subcategory' fields. Category must be one of: [Housing & Utilities, Groceries, Dining & Bars, Transport, Shopping, Health & Wellness, Travel, Entertainment, Subscriptions, Personal Care, Education, Pets, Gifts & Donations, Insurance, Investments, Business, Income, Transfers, Other]";
  const userPrompt =
    `Merchant: ${name}, Amount: $${amount}, Raw category: ${plaidCategory ?? "unknown"}`;

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
