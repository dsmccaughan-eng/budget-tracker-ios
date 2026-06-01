-- Vault helpers for Plaid access tokens (never stored in plaid_items rows).

create extension if not exists supabase_vault with schema vault;

-- Ensure plaid_items has expected columns for edge functions (no-op if table already matches).
alter table public.plaid_items
  add column if not exists institution_name text,
  add column if not exists created_at timestamptz not null default now();

-- Store access token in Vault; returns secret id.
create or replace function public.store_plaid_access_token(
  p_plaid_item_id text,
  p_access_token text
)
returns uuid
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_secret_id uuid;
  v_name text := 'plaid_access_token_' || p_plaid_item_id;
begin
  delete from vault.secrets where name = v_name;

  v_secret_id := vault.create_secret(
    p_access_token,
    v_name,
    'Plaid access token for item ' || p_plaid_item_id
  );

  return v_secret_id;
end;
$$;

revoke all on function public.store_plaid_access_token(text, text) from public;
grant execute on function public.store_plaid_access_token(text, text) to service_role;

-- Retrieve decrypted access token (service role only).
create or replace function public.get_plaid_access_token(p_plaid_item_id text)
returns text
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_name text := 'plaid_access_token_' || p_plaid_item_id;
  v_token text;
begin
  select decrypted_secret
  into v_token
  from vault.decrypted_secrets
  where name = v_name
  limit 1;

  return v_token;
end;
$$;

revoke all on function public.get_plaid_access_token(text) from public;
grant execute on function public.get_plaid_access_token(text) to service_role;
