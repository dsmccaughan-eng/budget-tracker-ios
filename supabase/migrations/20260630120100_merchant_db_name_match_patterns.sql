insert into public.merchant_db (merchant_name, merchant_pattern, category, subcategory)
values
  ('Micro Mart', 'micromart', 'Groceries', null),
  ('Ben & Jerry''s', 'ben & jerry', 'Dining & Bars', null),
  ('Sushi City', 'sushi city', 'Dining & Bars', null),
  ('Cafe Rio', 'cafe rio', 'Dining & Bars', null),
  ('McKay Books', 'mckay used books', 'Shopping', null),
  ('Honey Seed', 'honey seed', 'Dining & Bars', null),
  ('Payment From Checking', 'payment from chk', 'Transfers', 'internal transfer')
on conflict (merchant_pattern) do nothing;
