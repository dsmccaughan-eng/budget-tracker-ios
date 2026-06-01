#!/usr/bin/env bash
# Deploy migrations and Edge Functions to linked Supabase project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Pushing database migrations"
supabase db push

echo "==> Setting Edge Function secrets (requires PLAID_* in environment or .env)"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

supabase secrets set \
  PLAID_CLIENT_ID="${PLAID_CLIENT_ID:?Set PLAID_CLIENT_ID}" \
  PLAID_SECRET="${PLAID_SECRET:?Set PLAID_SECRET}" \
  PLAID_ENV="${PLAID_ENV:-sandbox}" \
  GEMINI_API_KEY="${GEMINI_API_KEY:-}"

echo "==> Deploying Edge Functions"
supabase functions deploy plaid-create-link-token
supabase functions deploy plaid-exchange-token
supabase functions deploy plaid-get-accounts
supabase functions deploy plaid-sync-transactions

echo "Deploy complete."
