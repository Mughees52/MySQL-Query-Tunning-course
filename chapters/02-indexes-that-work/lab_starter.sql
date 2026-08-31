-- ============================================================================
-- Chapter 2 lab starters — fill in the ___ blanks.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 2.2 The email index
-- ---------------------------------------------------------------------------
-- baseline, one last time (warm):
SELECT id, full_name, city FROM customers
WHERE email = 'amara.dubois150000@example.com';

CREATE INDEX idx_customers_email ON ___(___);

EXPLAIN ANALYZE
SELECT id, full_name, city FROM customers
WHERE email = 'amara.dubois150000@example.com';

-- ---------------------------------------------------------------------------
-- 2.3 SHOW INDEX
-- ---------------------------------------------------------------------------
SHOW INDEX FROM ___;
SELECT COUNT(*) FROM customers;   -- compare Cardinality to this

-- ---------------------------------------------------------------------------
-- 2.5 Single-column vs composite
-- ---------------------------------------------------------------------------
CREATE INDEX idx_orders_customer ON orders(customer_id);

EXPLAIN ANALYZE
SELECT id, status, order_date, total_cents FROM orders WHERE customer_id = 137;

EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5;

CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date ___);

EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5;

-- ---------------------------------------------------------------------------
-- 2.7 Covering index
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT ROUND(SUM(total_cents) / 100, 2) AS revenue
FROM orders
WHERE status = 'completed' AND order_date >= '2025-06-01';

CREATE INDEX idx_orders_date_status_total ON orders(___, ___, ___);

EXPLAIN ANALYZE
SELECT ROUND(SUM(total_cents) / 100, 2) AS revenue
FROM orders
WHERE status = 'completed' AND order_date >= '2025-06-01';

-- ---------------------------------------------------------------------------
-- 2.9 The DATE() trap
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders WHERE DATE(order_date) = '2025-06-15';

EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders
WHERE order_date >= '___' AND order_date < '___';

-- ---------------------------------------------------------------------------
-- 2.10 The implicit-cast trap
-- ---------------------------------------------------------------------------
CREATE INDEX idx_payments_provider_ref ON payments(provider_ref);

EXPLAIN SELECT id, order_id, amount_cents FROM payments WHERE provider_ref = 4000000042;
SHOW WARNINGS;

EXPLAIN ANALYZE
SELECT id, order_id, amount_cents FROM payments WHERE provider_ref = ___;

-- ---------------------------------------------------------------------------
-- 2.11 LIKE patterns
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT COUNT(*) FROM customers WHERE email LIKE 'amara.dubois15%';
EXPLAIN         SELECT COUNT(*) FROM customers WHERE email LIKE '%@example.com';

-- ---------------------------------------------------------------------------
-- 2.12 Skew: index vs scan
-- ---------------------------------------------------------------------------
CREATE INDEX idx_orders_status ON orders(status);

EXPLAIN SELECT * FROM orders WHERE status = 'completed';
EXPLAIN SELECT * FROM orders WHERE status = 'failed';

EXPLAIN ANALYZE SELECT SUM(total_cents) FROM orders WHERE status = 'completed';
EXPLAIN ANALYZE SELECT SUM(total_cents) FROM orders IGNORE INDEX (idx_orders_status)
WHERE status = 'completed';

EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE status = 'failed';

-- ---------------------------------------------------------------------------
-- 2.13 Histograms
-- ---------------------------------------------------------------------------
EXPLAIN SELECT COUNT(*) FROM orders WHERE ship_country = 'SG';

ANALYZE TABLE orders UPDATE ___ ON ship_country WITH ___ BUCKETS;

EXPLAIN SELECT COUNT(*) FROM orders WHERE ship_country = 'SG';
SELECT COUNT(*) FROM orders WHERE ship_country = 'SG';

-- ---------------------------------------------------------------------------
-- 2.14 Invisible + drop redundant
-- ---------------------------------------------------------------------------
SELECT table_name, redundant_index_name, dominant_index_name
FROM sys.schema_redundant_indexes WHERE table_schema = 'urbancart';

ALTER TABLE orders ALTER INDEX idx_orders_customer ___;
EXPLAIN SELECT id, status FROM orders WHERE customer_id = 137;
ALTER TABLE orders DROP INDEX idx_orders_customer;
