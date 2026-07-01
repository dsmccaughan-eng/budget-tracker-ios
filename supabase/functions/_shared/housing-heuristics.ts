import { normalizeMerchantText } from "./merchant-similarity.ts";

const HOUSING_SUBSTRINGS = [
  "rent payment",
  "monthly rent",
  "apt rent",
  "apartment rent",
  "landlord",
  "property management",
  "property mgmt",
  "lease payment",
  "rental payment",
  "housing payment",
  "home rent",
  "residential rent",
  "pay rent",
  "appfolio",
  "greystar",
  "equity residential",
  "avalon communities",
  "camden living",
  "progress residential",
  "invitation homes",
  "american homes 4 rent",
  "firstkey homes",
  "morgan properties",
  "udr apartments",
  "essex property",
  "bozzuto",
  "lincoln property",
];

const HOUSING_EXCLUSIONS = [
  "rental car",
  "rent the runway",
  "tool rental",
  "equipment rental",
];

function plaidSignalsHousing(
  plaidPrimary: string | null,
  plaidDetailed: string | null,
): boolean {
  for (const raw of [plaidDetailed, plaidPrimary]) {
    if (!raw) continue;
    const key = raw.toUpperCase().replace(/\s+/g, "_");
    if (key.includes("RENT_AND_UTILITIES")) return true;
    if (key.includes("_RENT")) return true;
    if (key === "RENT") return true;
  }
  return false;
}

export function looksLikeHousing(
  merchantText: string,
  plaidPrimary: string | null = null,
  plaidDetailed: string | null = null,
): boolean {
  const lower = merchantText.toLowerCase();
  for (const exclusion of HOUSING_EXCLUSIONS) {
    if (lower.includes(exclusion)) return false;
  }

  const normalized = normalizeMerchantText(merchantText);
  if (/\brent\b/.test(normalized)) return true;
  if (HOUSING_SUBSTRINGS.some((pattern) => normalized.includes(pattern))) {
    return true;
  }

  return plaidSignalsHousing(plaidPrimary, plaidDetailed);
}
