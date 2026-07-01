-- Rent/housing and mobile payment patterns for categorization.
insert into public.merchant_db (merchant_name, merchant_pattern, category, subcategory)
values
  ('Rent Payment', 'rent payment', 'Housing & Utilities', 'Rent'),
  ('Monthly Rent', 'monthly rent', 'Housing & Utilities', 'Rent'),
  ('Landlord Payment', 'landlord', 'Housing & Utilities', 'Rent'),
  ('Property Management', 'property management', 'Housing & Utilities', 'Rent'),
  ('Greystar Rent', 'greystar', 'Housing & Utilities', 'Rent'),
  ('Appfolio Rent', 'appfolio', 'Housing & Utilities', 'Rent'),
  ('Mobile Pmt', 'mobile pmt', 'Transfers', 'credit card payment'),
  ('Mobile Payment', 'mobile payment', 'Transfers', 'credit card payment'),
  ('Online Mobile Pmt', 'online mobile pmt', 'Transfers', 'credit card payment'),
  ('Cr Card Pmt', 'cr card pmt', 'Transfers', 'credit card payment'),
  ('Card Pmt', 'card pmt', 'Transfers', 'credit card payment'),
  ('Payment From Checking', 'payment from checking', 'Transfers', 'internal transfer'),
  ('Payment From Chk', 'payment from chk', 'Transfers', 'internal transfer'),
  ('Online Mobile Recurring', 'online/mobile recurring', 'Transfers', 'credit card payment')
on conflict (merchant_pattern) do nothing;
