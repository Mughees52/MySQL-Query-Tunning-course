-- ============================================================================
-- Improving Query Performance in MySQL 8
-- Seed: deterministic data generator for UrbanCart
-- ============================================================================
-- Everything is derived from CRC32(salt + row number), so every learner gets
-- byte-identical data and the row counts / plans in the transcripts reproduce.
-- Roughly:
--   countries       32
--   customers      300,000
--   products         5,000
--   orders       1,200,000   (2023-01-01 .. mid 2025, skewed statuses)
--   order_items  ~3,000,000  (1-4 items per order)
--   payments     ~1,070,000  (completed + refunded orders)
-- Takes a few minutes on a laptop. Grab a coffee.
-- ============================================================================

USE urbancart;

-- ---------------------------------------------------------------------------
-- Helper tables: digits and a 1M-row sequence
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS digits, seq, multipliers;

CREATE TABLE digits (d TINYINT UNSIGNED NOT NULL PRIMARY KEY);
INSERT INTO digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

CREATE TABLE seq (n INT UNSIGNED NOT NULL PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO seq
SELECT a.d + b.d*10 + c.d*100 + d.d*1000 + e.d*10000 + f.d*100000 + g.g*1000000 + 1
FROM digits a, digits b, digits c, digits d, digits e, digits f,
     (SELECT 0 AS g UNION ALL SELECT 1) g;

CREATE TABLE multipliers (k TINYINT UNSIGNED NOT NULL PRIMARY KEY);
INSERT INTO multipliers VALUES (1),(2),(3),(4);

-- ---------------------------------------------------------------------------
-- Countries
-- ---------------------------------------------------------------------------
INSERT INTO countries (country_code, country_name, region, continent) VALUES
('US','United States','North America','Americas'),
('CA','Canada','North America','Americas'),
('MX','Mexico','Latin America','Americas'),
('BR','Brazil','Latin America','Americas'),
('AR','Argentina','Latin America','Americas'),
('GB','United Kingdom','Western Europe','Europe'),
('IE','Ireland','Western Europe','Europe'),
('FR','France','Western Europe','Europe'),
('DE','Germany','Western Europe','Europe'),
('NL','Netherlands','Western Europe','Europe'),
('BE','Belgium','Western Europe','Europe'),
('ES','Spain','Southern Europe','Europe'),
('PT','Portugal','Southern Europe','Europe'),
('IT','Italy','Southern Europe','Europe'),
('GR','Greece','Southern Europe','Europe'),
('SE','Sweden','Northern Europe','Europe'),
('NO','Norway','Northern Europe','Europe'),
('DK','Denmark','Northern Europe','Europe'),
('FI','Finland','Northern Europe','Europe'),
('PL','Poland','Eastern Europe','Europe'),
('CZ','Czechia','Eastern Europe','Europe'),
('RO','Romania','Eastern Europe','Europe'),
('TR','Turkey','Middle East','Asia'),
('AE','United Arab Emirates','Middle East','Asia'),
('SA','Saudi Arabia','Middle East','Asia'),
('IN','India','South Asia','Asia'),
('PK','Pakistan','South Asia','Asia'),
('SG','Singapore','Southeast Asia','Asia'),
('JP','Japan','East Asia','Asia'),
('AU','Australia','Oceania','Oceania'),
('NZ','New Zealand','Oceania','Oceania'),
('ZA','South Africa','Sub-Saharan Africa','Africa');

-- ---------------------------------------------------------------------------
-- Customers: 300,000
-- ---------------------------------------------------------------------------
INSERT INTO customers (email, full_name, country_code, city, marketing_opt_in, created_at)
SELECT
  CONCAT(LOWER(ELT(1 + (CRC32(CONCAT('fn', n)) % 24),
    'james','maria','wei','fatima','oliver','amara','lucas','yuki','emma','omar',
    'sofia','liam','priya','noah','chloe','mateo','hana','arthur','zara','felix',
    'ines','ravi','elena','tariq')),
    '.',
    LOWER(ELT(1 + (CRC32(CONCAT('ln', n)) % 24),
    'smith','garcia','chen','khan','miller','okafor','silva','tanaka','brown','haddad',
    'rossi','johnson','patel','dubois','kim','novak','wilson','ali','murphy','weber',
    'costa','yamamoto','jensen','moreau')),
    n, '@example.com'),
  CONCAT(ELT(1 + (CRC32(CONCAT('fn', n)) % 24),
    'James','Maria','Wei','Fatima','Oliver','Amara','Lucas','Yuki','Emma','Omar',
    'Sofia','Liam','Priya','Noah','Chloe','Mateo','Hana','Arthur','Zara','Felix',
    'Ines','Ravi','Elena','Tariq'),
    ' ',
    ELT(1 + (CRC32(CONCAT('ln', n)) % 24),
    'Smith','Garcia','Chen','Khan','Miller','Okafor','Silva','Tanaka','Brown','Haddad',
    'Rossi','Johnson','Patel','Dubois','Kim','Novak','Wilson','Ali','Murphy','Weber',
    'Costa','Yamamoto','Jensen','Moreau')),
  CASE
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 280 THEN 'US'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 420 THEN 'GB'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 520 THEN 'DE'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 600 THEN 'FR'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 660 THEN 'CA'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 710 THEN 'IN'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 750 THEN 'AU'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 785 THEN 'NL'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 815 THEN 'ES'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 845 THEN 'IT'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 870 THEN 'BR'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 890 THEN 'SE'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 908 THEN 'PL'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 924 THEN 'JP'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 938 THEN 'MX'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 950 THEN 'IE'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 960 THEN 'PT'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 968 THEN 'DK'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 975 THEN 'NO'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 981 THEN 'FI'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 986 THEN 'SG'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 990 THEN 'AE'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 993 THEN 'NZ'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 995 THEN 'ZA'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 997 THEN 'TR'
    WHEN (CRC32(CONCAT('cc', n)) % 1000) < 998 THEN 'CZ'
    ELSE 'RO'
  END,
  ELT(1 + (CRC32(CONCAT('city', n)) % 30),
    'Springfield','Riverton','Lakewood','Fairview','Ashford','Milton','Brighton','Clayton',
    'Dover','Easton','Georgetown','Hamilton','Kingston','Linden','Marion','Newport',
    'Oakdale','Preston','Quincy','Redmond','Salem','Trenton','Union','Vernon',
    'Weston','York','Arlington','Burlington','Chester','Danbury'),
  (CRC32(CONCAT('opt', n)) % 100) < 38,
  TIMESTAMP('2022-06-01')
    + INTERVAL (CRC32(CONCAT('cd', n)) % 1150) DAY
    + INTERVAL (CRC32(CONCAT('cs', n)) % 86400) SECOND
FROM seq
WHERE n <= 300000;

-- ---------------------------------------------------------------------------
-- Products: 5,000
-- ---------------------------------------------------------------------------
INSERT INTO products (sku, name, category, price_cents, active, created_at)
SELECT
  CONCAT('SKU-', LPAD(n, 6, '0')),
  CONCAT(
    ELT(1 + (CRC32(CONCAT('adj', n)) % 12),
      'Classic','Compact','Deluxe','Eco','Foldable','Heavy-Duty',
      'Portable','Premium','Smart','Ultra','Vintage','Wireless'),
    ' ',
    ELT(1 + (CRC32(CONCAT('noun', n)) % 20),
      'Backpack','Blender','Desk Lamp','Earbuds','Guitar Stand','Hiking Boots',
      'Kettle','Keyboard','Monitor Arm','Notebook','Office Chair','Phone Case',
      'Rain Jacket','Running Shoes','Speaker','Tent','Toaster','Water Bottle',
      'Webcam','Yoga Mat'),
    ' #', n),
  ELT(1 + (CRC32(CONCAT('cat', n)) % 12),
    'audio','fitness','furniture','garden','kitchen','lighting',
    'luggage','music','outdoors','stationery','tech-accessories','wearables'),
  199 + (CRC32(CONCAT('price', n)) % 29800),
  (CRC32(CONCAT('act', n)) % 100) < 93,
  TIMESTAMP('2022-01-01') + INTERVAL (CRC32(CONCAT('pd', n)) % 1000) DAY
FROM seq
WHERE n <= 5000;

-- ---------------------------------------------------------------------------
-- Orders: 1,200,000
--   * ~1 in 10 orders belongs to one of 500 "whale" customers -> skew.
--   * Status distribution: 86% completed, 4% pending, 6% cancelled,
--     3% refunded, 1% failed.
-- ---------------------------------------------------------------------------
INSERT INTO orders (customer_id, status, order_date, total_cents, ship_country, coupon_code)
SELECT
  CASE WHEN n % 10 = 0
       THEN 1 + (CRC32(CONCAT('whale', n)) % 500)
       ELSE 1 + (CRC32(CONCAT('cust', n)) % 300000)
  END,
  CASE
    WHEN (CRC32(CONCAT('st', n)) % 100) < 86 THEN 'completed'
    WHEN (CRC32(CONCAT('st', n)) % 100) < 90 THEN 'pending'
    WHEN (CRC32(CONCAT('st', n)) % 100) < 96 THEN 'cancelled'
    WHEN (CRC32(CONCAT('st', n)) % 100) < 99 THEN 'refunded'
    ELSE 'failed'
  END,
  TIMESTAMP('2023-01-01')
    + INTERVAL (CRC32(CONCAT('od', n)) % 970) DAY
    + INTERVAL (CRC32(CONCAT('os', n)) % 86400) SECOND,
  0,  -- filled in after order_items exist
  CASE
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 300 THEN 'US'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 450 THEN 'GB'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 550 THEN 'DE'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 630 THEN 'FR'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 700 THEN 'CA'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 760 THEN 'IN'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 810 THEN 'AU'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 850 THEN 'NL'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 885 THEN 'ES'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 915 THEN 'IT'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 940 THEN 'BR'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 958 THEN 'SE'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 972 THEN 'PL'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 983 THEN 'JP'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 991 THEN 'MX'
    WHEN (CRC32(CONCAT('sc', n)) % 1000) < 996 THEN 'IE'
    ELSE 'SG'
  END,
  CASE WHEN (CRC32(CONCAT('cp', n)) % 100) < 8
       THEN CONCAT('SAVE', 1 + (CRC32(CONCAT('cpn', n)) % 20))
       ELSE NULL
  END
FROM seq
WHERE n <= 1200000;

-- ---------------------------------------------------------------------------
-- Order items: 1-4 per order (avg 2.5) -> ~3,000,000 rows
-- Price comes from the product, with a per-line historical wobble.
-- ---------------------------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents)
SELECT
  o.id,
  p.id,
  1 + (CRC32(CONCAT('qty', o.id, '-', m.k)) % 3),
  GREATEST(99, CAST(p.price_cents AS SIGNED) - CAST(CRC32(CONCAT('wob', o.id, '-', m.k)) % 300 AS SIGNED))
FROM orders o
JOIN multipliers m ON m.k <= 1 + (o.id % 4)
JOIN products p    ON p.id = 1 + (CRC32(CONCAT('prod', o.id, '-', m.k)) % 5000);

-- ---------------------------------------------------------------------------
-- Order totals: make orders.total_cents equal the sum of its items.
-- ---------------------------------------------------------------------------
UPDATE orders o
JOIN (SELECT order_id, SUM(quantity * unit_price_cents) AS total
      FROM order_items GROUP BY order_id) t ON t.order_id = o.id
SET o.total_cents = t.total;

-- ---------------------------------------------------------------------------
-- Payments: one per completed / refunded order (~1.07M rows)
-- provider_ref is a numeric-looking STRING. This is the Chapter 2 trap.
-- ---------------------------------------------------------------------------
INSERT INTO payments (order_id, method, status, amount_cents, provider_ref, paid_at)
SELECT
  o.id,
  ELT(1 + (CRC32(CONCAT('pm', o.id)) % 100 DIV 20) ,
      'card','card','paypal','apple_pay','klarna') ,
  CASE WHEN o.status = 'refunded' THEN 'refunded' ELSE 'succeeded' END,
  o.total_cents,
  CAST(4000000000 + o.id AS CHAR),
  o.order_date + INTERVAL 2 + (CRC32(CONCAT('pt', o.id)) % 240) MINUTE
FROM orders o
WHERE o.status IN ('completed', 'refunded');

-- ---------------------------------------------------------------------------
-- Clean up generator helpers, refresh statistics
-- ---------------------------------------------------------------------------
DROP TABLE digits, seq, multipliers;

ANALYZE TABLE countries, customers, products, orders, order_items, payments;
