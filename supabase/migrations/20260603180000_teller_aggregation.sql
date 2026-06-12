-- Teller aggregation (parallel to plaid_items; same accounts/transactions tables).

create table if not exists public.teller_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  teller_enrollment_id text not null,
  institution_name text,
  status text not null default 'active',
  error_code text,
  error_message text,
  last_sync_at timestamptz,
  created_at timestamptz not null default now(),
  constraint teller_items_enrollment_uidx unique (teller_enrollment_id),
  constraint teller_items_status_check
    check (status in ('active', 'login_required', 'disconnected', 'error'))
);

create index if not exists teller_items_user_idx
  on public.teller_items (user_id, created_at desc);

alter table public.teller_items enable row level security;

drop policy if exists "Users read own teller items" on public.teller_items;
create policy "Users read own teller items"
  on public.teller_items
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users update own teller items" on public.teller_items;
create policy "Users update own teller items"
  on public.teller_items
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.accounts
  add column if not exists provider text not null default 'plaid';

alter table public.accounts
  drop constraint if exists accounts_provider_check;

alter table public.accounts
  add constraint accounts_provider_check
  check (provider in ('plaid', 'teller'));

create or replace function public.store_teller_access_token(
  p_teller_enrollment_id text,
  p_access_token text
)
returns uuid
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_secret_id uuid;
  v_name text := 'teller_access_token_' || p_teller_enrollment_id;
begin
  delete from vault.secrets where name = v_name;

  v_secret_id := vault.create_secret(
    p_access_token,
    v_name,
    'Teller access token for enrollment ' || p_teller_enrollment_id
  );

  return v_secret_id;
end;
$$;

revoke all on function public.store_teller_access_token(text, text) from public;
grant execute on function public.store_teller_access_token(text, text) to service_role;

create or replace function public.get_teller_access_token(p_teller_enrollment_id text)
returns text
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_name text := 'teller_access_token_' || p_teller_enrollment_id;
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

revoke all on function public.get_teller_access_token(text) from public;
grant execute on function public.get_teller_access_token(text) to service_role;

create or replace function public.delete_teller_access_token(p_teller_enrollment_id text)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_name text := 'teller_access_token_' || p_teller_enrollment_id;
begin
  delete from vault.secrets where name = v_name;
end;
$$;

revoke all on function public.delete_teller_access_token(text) from public;
grant execute on function public.delete_teller_access_token(text) to service_role;
