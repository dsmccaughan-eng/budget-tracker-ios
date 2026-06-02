-- Fixed bills are anchored to individual transactions, not budget categories.
alter table public.transactions
  add column if not exists is_fixed_bill boolean not null default false,
  add column if not exists bill_nickname text,
  add column if not exists bill_due_day integer,
  add column if not exists bill_amount numeric;

comment on column public.transactions.is_fixed_bill is 'User-marked recurring bill; drives Bills tab';
comment on column public.transactions.bill_nickname is 'Display name under Bills';
comment on column public.transactions.bill_due_day is 'Typical day of month the bill charges (1-31)';
comment on column public.transactions.bill_amount is 'Expected monthly bill amount override';
