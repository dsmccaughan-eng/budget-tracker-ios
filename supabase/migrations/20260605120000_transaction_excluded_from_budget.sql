alter table public.transactions
  add column if not exists excluded_from_budget boolean not null default false;

comment on column public.transactions.excluded_from_budget is 'When true, transaction is omitted from budget spend totals';
