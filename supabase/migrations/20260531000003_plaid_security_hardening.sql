-- Plaid lifecycle tracking, webhook idempotency, audit log, and vault cleanup.

alter table public.plaid_items
  add column if not exists status text not null default 'active',
  add column if not exists error_code text,
  add column if not exists error_message text,
  add column if not exists last_webhook_at timestamptz,
  add column if not exists last_sync_at timestamptz,
  add column if not exists consent_expires_at timestamptz;

alter table public.plaid_items
  drop constraint if exists plaid_items_status_check;

alter table public.plaid_items
  add constraint plaid_items_status_check
  check (status in ('active', 'login_required', 'pending_disconnect', 'revoked', 'error'));

create table if not exists public.plaid_webhook_events (
  id uuid primary key default gen_random_uuid(),
  plaid_item_id text not null,
  webhook_type text not null,
  webhook_code text not null,
  payload_hash text not null,
  processed_at timestamptz not null default now(),
  sync_triggered boolean not null default false,
  constraint plaid_webhook_events_payload_hash_uidx unique (payload_hash)
);

create index if not exists plaid_webhook_events_item_idx
  on public.plaid_webhook_events (plaid_item_id, processed_at desc);

alter table public.plaid_webhook_events enable row level security;

create table if not exists public.security_audit_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  resource_type text,
  resource_id text,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index if not exists security_audit_log_user_created_idx
  on public.security_audit_log (user_id, created_at desc);

alter table public.security_audit_log enable row level security;

drop policy if exists "Users read own security audit" on public.security_audit_log;
create policy "Users read own security audit"
  on public.security_audit_log
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users read own plaid items" on public.plaid_items;
create policy "Users read own plaid items"
  on public.plaid_items
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users update own plaid items" on public.plaid_items;
create policy "Users update own plaid items"
  on public.plaid_items
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Remove decrypted token from Vault when user disconnects a bank.
create or replace function public.delete_plaid_access_token(p_plaid_item_id text)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_name text := 'plaid_access_token_' || p_plaid_item_id;
begin
  delete from vault.secrets where name = v_name;
end;
$$;

revoke all on function public.delete_plaid_access_token(text) from public;
grant execute on function public.delete_plaid_access_token(text) to service_role;
