-- Credit-card and bill-pay patterns (Plaid PFC + common US bank descriptors).
insert into public.merchant_db (merchant_name, merchant_pattern, category, subcategory)
values
  ('Mobile Credit Card', 'mobile credit card', 'Transfers', 'credit card payment'),
  ('Credit Card Payment', 'credit card payment', 'Transfers', 'credit card payment'),
  ('Credit Card Transfer', 'credit card transfer', 'Transfers', 'credit card payment'),
  ('Card Payment', 'card payment', 'Transfers', 'credit card payment'),
  ('Online Payment Thank You', 'payment thank you', 'Transfers', 'credit card payment'),
  ('Autopay Payment', 'autopay payment', 'Transfers', 'credit card payment'),
  ('Bill Pay', 'bill pay', 'Transfers', 'bill payment'),
  ('Loan Payment', 'loan payment', 'Transfers', 'loan payment'),
  ('Mortgage Payment', 'mortgage payment', 'Transfers', 'loan payment'),
  ('Chase Credit Card', 'payment to chase', 'Transfers', 'credit card payment'),
  ('Capital One Payment', 'payment to capital one', 'Transfers', 'credit card payment'),
  ('Amex Payment', 'payment to amex', 'Transfers', 'credit card payment'),
  ('Citi Payment', 'payment to citi', 'Transfers', 'credit card payment'),
  ('Discover Payment', 'payment to discover', 'Transfers', 'credit card payment'),
  ('Bank of America Payment', 'payment to bank of america', 'Transfers', 'credit card payment'),
  ('Wells Fargo Payment', 'payment to wells fargo', 'Transfers', 'credit card payment'),
  ('USAA Payment', 'payment to usaa', 'Transfers', 'credit card payment'),
  ('Apple Card Payment', 'apple card payment', 'Transfers', 'credit card payment'),
  ('Apple Card', 'apple card', 'Transfers', 'credit card payment'),
  ('Synchrony Payment', 'synchrony', 'Transfers', 'credit card payment')
on conflict (merchant_pattern) do nothing;
