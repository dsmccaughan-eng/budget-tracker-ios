import { normalizeMerchantText } from "./merchant-similarity.ts";

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
  "scheduled payment",
  "payment to acct",
  "recurring from chk",
  "online/mobile recurring",
  "online/mobile",
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
  "mobile pmt",
  "mobile payment",
  "mobile pymt",
  "card pmt",
  "card pymt",
  "epayment",
  "e payment",
  "payment from chk",
  "payment from checking",
  "payment to card",
  "payment to credit",
  "cr card pmt",
  "cr card payment",
  "visa payment",
  "mastercard payment",
  "discover payment",
  "amex payment",
  "synchrony bank",
  "apple card",
];

const MOBILE_CARRIER_PATTERNS = [
  "t mobile",
  "t-mobile",
  "tmobile",
  "verizon wireless",
  "verizon",
  "at t wireless",
  "at&t",
  "att wireless",
  "sprint",
  "cricket wireless",
  "google fi",
  "mint mobile",
  "boost mobile",
  "us cellular",
  "metro by t-mobile",
];

const PAYMENT_TOKENS = [
  "payment",
  "pmt",
  "pymt",
  "autopay",
  "payoff",
  "pay",
];

const CHANNEL_TOKENS = ["mobile", "online", "web"];

const CARD_TOKENS = [
  "card",
  "credit",
  "visa",
  "mastercard",
  "discover",
  "amex",
  "synchrony",
];

const AMBIGUOUS_TRANSPORT_PATTERNS = new Set([
  "metro",
  "mobil",
  "bp",
  "marathon",
  "76",
  "enterprise",
]);

export function hasPaymentContext(text: string): boolean {
  const normalized = normalizeMerchantText(text);
  return PAYMENT_TOKENS.some((token) => normalized.includes(token));
}

function looksLikeMobileCarrierPayment(text: string): boolean {
  const normalized = normalizeMerchantText(text);
  return MOBILE_CARRIER_PATTERNS.some((pattern) => normalized.includes(pattern));
}

export function looksLikeMobileCardPayment(
  merchantText: string,
): boolean {
  const lower = merchantText.toLowerCase();
  const normalized = normalizeMerchantText(merchantText);

  if (looksLikeMobileCarrierPayment(merchantText)) return false;
  if (normalized.includes("mobile credit card")) return true;
  if (lower.includes("online/mobile")) return true;

  const hasPayment = PAYMENT_TOKENS.some((token) => normalized.includes(token));
  const hasChannel = CHANNEL_TOKENS.some((token) => normalized.includes(token));
  const hasCard = CARD_TOKENS.some((token) => normalized.includes(token));

  if (hasPayment && hasChannel) return true;
  if (hasPayment && hasCard) return true;
  if (hasChannel && hasCard) return true;

  if (
    /\bmobile\b/.test(normalized) &&
    /\b(cr|credit|card|pmt|payment|xfer|transfer)\b/.test(normalized)
  ) {
    return true;
  }

  return false;
}

export function shouldSkipTransportMerchantMatch(
  merchantPattern: string,
  merchantText: string,
): boolean {
  const pattern = merchantPattern.toLowerCase();
  if (!AMBIGUOUS_TRANSPORT_PATTERNS.has(pattern)) return false;
  return hasPaymentContext(merchantText) ||
    looksLikeMobileCardPayment(merchantText);
}

export function looksLikeTransfer(
  merchantText: string,
  plaidCategory: string | null = null,
  plaidDetailedCategory: string | null = null,
): boolean {
  if (looksLikeMobileCarrierPayment(merchantText)) return false;

  const lower = merchantText.toLowerCase();
  const normalized = normalizeMerchantText(merchantText);

  if (TRANSFER_SUBSTRINGS.some((pattern) => lower.includes(pattern))) {
    return true;
  }
  if (TRANSFER_SUBSTRINGS.some((pattern) => normalized.includes(pattern))) {
    return true;
  }
  if (looksLikeMobileCardPayment(merchantText)) {
    return true;
  }
  if (
    lower.includes("mobile") &&
    lower.includes("credit") &&
    lower.includes("card")
  ) {
    return true;
  }
  if (
    lower.includes("credit card") &&
    (lower.includes("payment") || lower.includes("transfer"))
  ) {
    return true;
  }
  for (const raw of [plaidDetailedCategory, plaidCategory]) {
    if (raw && plaidHintsTransfer(raw)) return true;
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
