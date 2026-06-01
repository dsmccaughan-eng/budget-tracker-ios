-- Budget Tracker: bills and rollover flags (iOS Budget model expects these columns).

alter table public.budgets
  add column if not exists is_fixed boolean not null default false,
  add column if not exists is_rollover boolean not null default false;

comment on column public.budgets.is_fixed is 'Fixed monthly bill (rent, utilities) — used for Bills tab due dates';
comment on column public.budgets.is_rollover is 'Unused monthly limit rolls to next month';
