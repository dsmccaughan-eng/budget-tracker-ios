-- Additional merchant + transfer patterns (Gemini fallback when quota unavailable).
insert into public.merchant_db (merchant_name, merchant_pattern, category, subcategory)
values
  ('Vercel', 'vercel', 'Subscriptions', null),
  ('Micro Mart', 'micro mart', 'Groceries', null),
  ('Niedlov''s Bakery', 'niedlov', 'Dining & Bars', null),
  ('Taichi Bubble Tea', 'taichi bubble tea', 'Dining & Bars', null),
  ('Yellow Deli', 'yellow deli', 'Dining & Bars', null),
  ('El Metate', 'el metate', 'Dining & Bars', null),
  ('Cava', 'cava', 'Dining & Bars', null),
  ('State of Confusion', 'state of confusion', 'Dining & Bars', null),
  ('Stone Age', 'stone age', 'Dining & Bars', null),
  ('Ox2 Buns', 'ox2 buns', 'Dining & Bars', null),
  ('Corporate Filings', 'corporate filings', 'Business', null),
  ('KeyMe Locksmiths', 'key.me', 'Housing & Utilities', null),
  ('Workspace Pantry', 'workspace pantry', 'Dining & Bars', null),
  ('Toast POS', 'tst*', 'Dining & Bars', null),
  ('Scheduled Payment', 'scheduled payment', 'Transfers', 'bill payment'),
  ('Recurring Transfer', 'recurring from chk', 'Transfers', 'internal transfer'),
  ('Micro Mart', 'micromart', 'Groceries', null),
  ('Ben & Jerry''s', 'ben & jerry', 'Dining & Bars', null),
  ('Sushi City', 'sushi city', 'Dining & Bars', null),
  ('Cafe Rio', 'cafe rio', 'Dining & Bars', null),
  ('McKay Books', 'mckay used books', 'Shopping', null),
  ('Honey Seed', 'honey seed', 'Dining & Bars', null),
  ('Payment From Checking', 'payment from chk', 'Transfers', 'internal transfer')
on conflict (merchant_pattern) do nothing;
