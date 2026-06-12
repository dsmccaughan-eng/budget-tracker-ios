-- Plaid Investments: holdings, securities, and investment transactions.

create table if not exists public.investment_securities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plaid_security_id text not null,
  name text not null,
  ticker_symbol text,
  type text,
  subtype text,
  close_price numeric(14, 6),
  close_price_as_of date,
  iso_currency_code text not null default 'USD',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, plaid_security_id)
);

create index if not exists investment_securities_user_idx
  on public.investment_securities (user_id, ticker_symbol);

create table if not exists public.investment_holdings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  security_id uuid references public.investment_securities (id) on delete set null,
  plaid_account_id text not null,
  plaid_security_id text not null,
  quantity numeric(18, 8) not null default 0,
  institution_price numeric(14, 6),
  institution_value numeric(14, 2),
  cost_basis numeric(14, 2),
  iso_currency_code text not null default 'USD',
  synced_at timestamptz not null default now(),
  unique (user_id, account_id, plaid_security_id)
);

create index if not exists investment_holdings_account_idx
  on public.investment_holdings (user_id, account_id);

create table if not exists public.investment_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  security_id uuid references public.investment_securities (id) on delete set null,
  plaid_investment_transaction_id text not null,
  plaid_account_id text not null,
  plaid_security_id text,
  name text not null,
  type text,
  subtype text,
  date date not null,
  quantity numeric(18, 8),
  amount numeric(14, 2) not null,
  price numeric(14, 6),
  fees numeric(14, 2),
  iso_currency_code text not null default 'USD',
  created_at timestamptz not null default now(),
  unique (user_id, plaid_investment_transaction_id)
);

create index if not exists investment_transactions_account_date_idx
  on public.investment_transactions (user_id, account_id, date desc);

alter table public.investment_securities enable row level security;
alter table public.investment_holdings enable row level security;
alter table public.investment_transactions enable row level security;

create policy "Users manage own investment securities"
  on public.investment_securities
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users manage own investment holdings"
  on public.investment_holdings
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users manage own investment transactions"
  on public.investment_transactions
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
