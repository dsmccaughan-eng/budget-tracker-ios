-- Daily per-account balance history (recorded on Plaid refresh and client sync).

create table if not exists public.account_balance_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  date date not null,
  current_balance numeric(14, 2),
  available_balance numeric(14, 2),
  created_at timestamptz not null default now(),
  unique (user_id, account_id, date)
);

create index if not exists account_balance_snapshots_user_account_idx
  on public.account_balance_snapshots (user_id, account_id, date desc);

alter table public.account_balance_snapshots enable row level security;

create policy "Users manage own account balance snapshots"
  on public.account_balance_snapshots
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
