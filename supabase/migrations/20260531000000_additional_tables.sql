-- Additional Budget Tracker tables (base tables already exist in remote project).

-- savings_goals
create table if not exists public.savings_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  target_amount numeric(12, 2) not null check (target_amount >= 0),
  current_amount numeric(12, 2) not null default 0 check (current_amount >= 0),
  monthly_contribution numeric(12, 2) not null default 0 check (monthly_contribution >= 0),
  target_date date,
  linked_account_id uuid references public.accounts (id) on delete set null,
  emoji text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists savings_goals_user_id_idx on public.savings_goals (user_id);

alter table public.savings_goals enable row level security;

create policy "Users manage own savings goals"
  on public.savings_goals
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- merchant_rules
create table if not exists public.merchant_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  merchant_contains text not null,
  category text not null,
  subcategory text,
  created_at timestamptz not null default now()
);

create index if not exists merchant_rules_user_id_idx on public.merchant_rules (user_id);
create index if not exists merchant_rules_merchant_contains_idx on public.merchant_rules (merchant_contains);

alter table public.merchant_rules enable row level security;

create policy "Users manage own merchant rules"
  on public.merchant_rules
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- merchant_db (curated reference data — read-only for authenticated users)
create table if not exists public.merchant_db (
  id uuid primary key default gen_random_uuid(),
  merchant_name text not null,
  merchant_pattern text not null,
  category text not null,
  subcategory text,
  created_at timestamptz not null default now()
);

create unique index if not exists merchant_db_pattern_uidx on public.merchant_db (merchant_pattern);
create index if not exists merchant_db_pattern_idx on public.merchant_db (merchant_pattern);

alter table public.merchant_db enable row level security;

create policy "Authenticated users read merchant_db"
  on public.merchant_db
  for select
  to authenticated
  using (true);

-- price_history
create table if not exists public.price_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  item_name text not null,
  price numeric(12, 2) not null check (price >= 0),
  merchant text not null,
  date date not null,
  created_at timestamptz not null default now()
);

create index if not exists price_history_user_id_idx on public.price_history (user_id);
create index if not exists price_history_item_name_idx on public.price_history (item_name);

alter table public.price_history enable row level security;

create policy "Users manage own price history"
  on public.price_history
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- net_worth_snapshots
create table if not exists public.net_worth_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  date date not null,
  total_assets numeric(14, 2) not null,
  total_liabilities numeric(14, 2) not null,
  net_worth numeric(14, 2) not null,
  created_at timestamptz not null default now(),
  unique (user_id, date)
);

create index if not exists net_worth_snapshots_user_id_idx on public.net_worth_snapshots (user_id);

alter table public.net_worth_snapshots enable row level security;

create policy "Users manage own net worth snapshots"
  on public.net_worth_snapshots
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
