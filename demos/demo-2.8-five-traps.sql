-- ============================================================================
-- LIVE DEMO SCRIPT · video 11 · lesson 2.8 — Five ways to lose an index
-- Deck: chapter2 slides 6–8
-- STATE REQUIRED: labs 2.2–2.7 done (email, composite, covering idx_orders_date_status_total). CREATES: idx_payments_provider_ref, idx_orders_status, ship_country histogram; makes idx_orders_customer invisible then DROPS it. Leaves DB at canonical ch-2 end state. SKIP matching statements when replaying labs 2.10–2.14.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [trap 1] DATE() on the column — index scanned, not seeked · ~78 ms
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE DATE(order_date) = '2025-06-15';

-- STEP 2 · same rows, sargable — half-open range · ~0.14 ms, 550x
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders
WHERE order_date >= '2025-06-15' AND order_date < '2025-06-16';

-- STEP 3 · [trap 2] the implicit cast. Build the index, then watch it be ignored
CREATE INDEX idx_payments_provider_ref ON payments(provider_ref);
EXPLAIN SELECT id, order_id, amount_cents FROM payments WHERE provider_ref = 4000000042;
SHOW WARNINGS;   -- MySQL names the disease: "type or collation conversion"

-- STEP 4 · two quote characters: 10,000x
-- expect: Index lookup, actual ≈ 0.009 ms
EXPLAIN ANALYZE
SELECT id, order_id, amount_cents FROM payments WHERE provider_ref = '4000000042';

-- STEP 5 · [trap 3] wildcards: prefix seeks, leading wildcard scans
EXPLAIN ANALYZE SELECT COUNT(*) FROM customers WHERE email LIKE 'amara.dubois15%';
EXPLAIN         SELECT COUNT(*) FROM customers WHERE email LIKE '%@example.com';

-- STEP 6 · [trap 4] skew: index the status column, then catch the optimizer wrong
CREATE INDEX idx_orders_status ON orders(status);
EXPLAIN ANALYZE SELECT SUM(total_cents) FROM orders WHERE status = 'completed';
-- expect ~431 ms via the index — a million random two-step lookups

-- STEP 7 · overrule it — sequential beats random 3x
EXPLAIN ANALYZE SELECT SUM(total_cents) FROM orders IGNORE INDEX (idx_orders_status)
WHERE status = 'completed';
-- expect ~139 ms. Then show the index is GOLD for the rare value:
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE status = 'failed';   -- ~1 ms

-- STEP 8 · [trap 5 · SLIDE 7] statistics: 10% guess -> histogram -> honest
EXPLAIN SELECT COUNT(*) FROM orders WHERE ship_country = 'SG';   -- est ≈ 119,463
ANALYZE TABLE orders UPDATE HISTOGRAM ON ship_country WITH 32 BUCKETS;
EXPLAIN SELECT COUNT(*) FROM orders WHERE ship_country = 'SG';   -- est ≈ 4,898
SELECT COUNT(*)  FROM orders WHERE ship_country = 'SG';          -- 4,845 true

-- STEP 9 · [SLIDE 8] retire dead weight, invisible-first
SELECT table_name, redundant_index_name, dominant_index_name
FROM sys.schema_redundant_indexes WHERE table_schema = 'urbancart';
ALTER TABLE orders ALTER INDEX idx_orders_customer INVISIBLE;
EXPLAIN SELECT id, status FROM orders WHERE customer_id = 137;   -- composite serves it
ALTER TABLE orders DROP INDEX idx_orders_customer;
