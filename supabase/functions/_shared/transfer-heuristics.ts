const TRANSFER_SUBSTRINGS = [
  "credit card payment",
  "credit card transfer",
  "mobile credit card",
  "card payment",
  "card autopay",
  "autopay payment",
  "online payment",
  "payment thank you",
  "thank you payment",
  "payoff",
  "bill pay",
  "bill payment",
  "loan payment",
  "mortgage payment",
  "ach payment",
  "ach debit",
  "ach credit",
  "wire transfer",
  "internal transfer",
  "transfer to",
  "transfer from",
  "xfer",
  "p2p transfer",
  "payment to chase",
  "payment to capital one",
  "payment to amex",
  "payment to citi",
  "payment to discover",
  "payment to bank of america",
  "payment to wells fargo",
  "payment to usaa",
  "apple cash",
  "cash advance",
];

export function looksLikeTransfer(
  merchantText: string,
  plaidCategory: string | null = null,
): boolean {
  const text = merchantText.toLowerCase();
  if (TRANSFER_SUBSTRINGS.some((pattern) => text.includes(pattern))) {
    return true;
  }
  if (text.includes("mobile") && text.includes("credit") && text.includes("card")) {
    return true;
  }
  if (
    text.includes("credit card") &&
    (text.includes("payment") || text.includes("transfer"))
  ) {
    return true;
  }
  if (plaidCategory && plaidHintsTransfer(plaidCategory)) {
    return true;
  }
  return false;
}

export function plaidHintsTransfer(raw: string): boolean {
  const key = raw.toUpperCase().replace(/\s+/g, "_");
  if (key.includes("TRANSFER")) return true;
  if (key.includes("CREDIT_CARD")) return true;
  if (key.includes("LOAN_PAYMENT")) return true;
  return false;
}

export function matchesMerchantPattern(text: string, pattern: string): boolean {
  const normalized = text.toLowerCase();
  const needle = pattern.toLowerCase();
  if (needle.length <= 5 && !needle.includes(" ")) {
    const escaped = needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`\\b${escaped}\\b`, "i").test(normalized);
  }
  return normalized.includes(needle);
}
