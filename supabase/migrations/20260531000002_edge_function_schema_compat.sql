-- Columns and indexes expected by Edge Functions (safe if base schema already exists).

alter table public.plaid_items
  add column if not exists sync_cursor text;

create unique index if not exists plaid_items_plaid_item_id_uidx
  on public.plaid_items (plaid_item_id);

create unique index if not exists accounts_plaid_account_id_uidx
  on public.accounts (plaid_account_id);

create unique index if not exists transactions_plaid_transaction_id_uidx
  on public.transactions (plaid_transaction_id);

alter table public.transactions
  add column if not exists subcategory text,
  add column if not exists pending boolean not null default false,
  add column if not exists is_manual boolean not null default false,
  add column if not exists split_items jsonb;

alter table public.accounts
  add column if not exists official_name text,
  add column if not exists subtype text,
  add column if not exists mask text,
  add column if not exists current_balance numeric(14, 2),
  add column if not exists available_balance numeric(14, 2);
