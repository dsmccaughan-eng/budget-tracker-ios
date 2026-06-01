-- Track how each transaction category was assigned (rules, AI, Plaid, user override).
alter table public.transactions
  add column if not exists category_source text;
