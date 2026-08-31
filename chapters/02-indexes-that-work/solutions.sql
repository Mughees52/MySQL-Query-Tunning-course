-- ============================================================================
-- Chapter 2 — solutions, with measured output (MySQL 8.4, 1G buffer pool).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 2.2 The email index
-- ---------------------------------------------------------------------------
CREATE INDEX idx_customers_email ON customers(email);
-- ~1 s to build on 300k rows.

EXPLAIN ANALYZE
SELECT id, full_name, city FROM customers
WHERE email = 'amara.dubois150000@example.com';
-- -> Index lookup on customers using idx_customers_email (email='...')
--        (cost=0.35 rows=1) (actual time=0.009 rows=1 loops=1)
-- Before: ~45 ms scanning 300,000 rows. After: 9 µs touching 1 row. ~5000x.
-- EXPLAIN (tabular) now shows: type=ref, key=idx_customers_email, rows=1.

-- ---------------------------------------------------------------------------
-- 2.3 SHOW INDEX
-- ---------------------------------------------------------------------------
SHOW INDEX FROM customers;
-- idx_customers_email  Cardinality: ~298422  (== ~row count: fully selective)
-- Cardinality is sampled, expect a few % drift. Ratio ~1 -> equality isolates
-- ~1 row: the perfect index. Ratio near 0 (like status: 5/1.2M) -> lesson 2.12.

-- ---------------------------------------------------------------------------
-- 2.5 Single-column vs composite
-- ---------------------------------------------------------------------------
CREATE INDEX idx_orders_customer ON orders(customer_id);          -- ~2 s

EXPLAIN ANALYZE
SELECT id, status, order_date, total_cents FROM orders WHERE customer_id = 137;
-- -> Index lookup using idx_orders_customer (customer_id=137)
--        (actual time=0.08..0.39 rows=243)          [was ~110 ms full scan]

EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5;
-- -> Limit: 5 row(s)                       (actual time=1.66 rows=5)
--     -> Sort: order_date DESC, limit 5    (actual .. rows=5)      <- SORT!
--         -> Index lookup (customer_id=137)(actual .. rows=243)
-- Fetches all 243, sorts them, keeps 5.

CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date DESC);

EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5;
-- -> Limit: 5 row(s)                                (actual time=0.074 rows=5)
--     -> Index lookup using idx_orders_customer_date (actual .. rows=5)
-- No Sort node. Reads exactly 5 entries, already in DESC order. 23x faster,
-- and the gap grows with the customer's order count.

-- Leftmost-prefix demo — date alone cannot seek this index:
EXPLAIN SELECT id FROM orders WHERE order_date > '2025-08-01';
-- type=index (full index scan over 1.2M entries), filtered 33% — no seek.

-- ---------------------------------------------------------------------------
-- 2.7 Covering index
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT ROUND(SUM(total_cents) / 100, 2) AS revenue
FROM orders WHERE status = 'completed' AND order_date >= '2025-06-01';
-- BEFORE: -> Filter (...) -> Table scan on orders (rows=1.2e6)  actual ~141 ms

CREATE INDEX idx_orders_date_status_total ON orders(order_date, status, total_cents);
-- ~3 s to build.

-- AFTER:
-- -> Aggregate: sum(total_cents)                    (actual time=14.1 rows=1)
--     -> Filter: status='completed' AND date>=...   (actual .. rows=93667)
--         -> Covering index range scan on orders using idx_orders_date_status_total
--            over ('2025-06-01' <= order_date)      (actual .. rows=108957)
-- 141 ms -> 14 ms, and the table itself is never opened ("Covering").
-- Every needed column (seek: order_date, filter: status, sum: total_cents)
-- lives in the index leaves.

-- ---------------------------------------------------------------------------
-- 2.9 The DATE() trap
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE DATE(order_date) = '2025-06-15';
-- -> Filter: (cast(order_date as date) = '2025-06-15') (actual ..78 rows=1299)
--     -> Covering index scan on orders (rows=1.2e6)     <- scans EVERY entry
-- 78 ms. An index *scan* is still a scan; DATE() hides the column's order.

EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders
WHERE order_date >= '2025-06-15' AND order_date < '2025-06-16';
-- -> Covering index range scan over ('2025-06-15' <= order_date < '2025-06-16')
--        (actual time=0.018..0.079 rows=1299)
-- 0.14 ms total. Same 1,299 rows, 550x faster. Half-open interval: never
-- BETWEEN ... '23:59:59' (drops the final second).

-- ---------------------------------------------------------------------------
-- 2.10 The implicit-cast trap
-- ---------------------------------------------------------------------------
CREATE INDEX idx_payments_provider_ref ON payments(provider_ref);

EXPLAIN SELECT id, order_id, amount_cents FROM payments WHERE provider_ref = 4000000042;
-- type=ALL, key=NULL, rows=1.06M  — index visible in possible_keys but unused!
SHOW WARNINGS;
-- Warning 1739: Cannot use ref access on index 'idx_payments_provider_ref'
--               due to type or collation conversion on field 'provider_ref'
-- MySQL names the disease. actual: ~90 ms full scan for 1 row.

EXPLAIN ANALYZE
SELECT id, order_id, amount_cents FROM payments WHERE provider_ref = '4000000042';
-- -> Index lookup (provider_ref='4000000042') (actual time=0.009 rows=1)
-- Two quote characters: 10,000x.

-- ---------------------------------------------------------------------------
-- 2.11 LIKE patterns
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT COUNT(*) FROM customers WHERE email LIKE 'amara.dubois15%';
-- -> Covering index RANGE scan ('amara.dubois15' <= email <= 'amara.dubois15\xff...')
--    141 rows, ~0.05 ms. Prefix LIKE == range seek.

EXPLAIN SELECT COUNT(*) FROM customers WHERE email LIKE '%@example.com';
-- type=index (scan of all 298k index entries, Using where; Using index).
-- No prefix -> no seek. It still prefers scanning the small covering index
-- over the table; a non-covered query would degrade to type=ALL.

-- ---------------------------------------------------------------------------
-- 2.12 Skew: index vs scan
-- ---------------------------------------------------------------------------
CREATE INDEX idx_orders_status ON orders(status);

EXPLAIN SELECT * FROM orders WHERE status = 'completed';
-- type=ref, rows≈597313   <- estimate; truth is 1.03M (86% of table)
EXPLAIN SELECT * FROM orders WHERE status = 'failed';
-- type=ref, rows≈22022    <- truth: 11,826. Index dives estimate per value.

EXPLAIN ANALYZE SELECT SUM(total_cents) FROM orders WHERE status = 'completed';
-- -> Index lookup using idx_orders_status (actual time=0.49..414  rows=1.03e6)
--    total ~431 ms  — 1M random clustered-index fetches.
EXPLAIN ANALYZE SELECT SUM(total_cents) FROM orders IGNORE INDEX (idx_orders_status)
WHERE status = 'completed';
-- -> Filter -> Covering index scan on idx_orders_date_status_total
--    total ~139 ms  — sequential read beats a million random hops, 3x.
-- The optimizer CHOSE the slower plan (estimate was 2x low). EXPLAIN ANALYZE
-- is the referee; hints like IGNORE INDEX are the whistle (sparingly!).

EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE status = 'failed';
-- -> Covering index lookup (status='failed') (actual time=0.94 rows=11826)
-- ~1 ms. Low-cardinality index: gold for rare values, poison for common ones.

-- ---------------------------------------------------------------------------
-- 2.13 Histograms
-- ---------------------------------------------------------------------------
EXPLAIN SELECT COUNT(*) FROM orders WHERE ship_country = 'SG';
-- rows=1194627 filtered=10.00  -> estimate ≈ 119,463 matching. Blind default.

ANALYZE TABLE orders UPDATE HISTOGRAM ON ship_country WITH 32 BUCKETS;

EXPLAIN SELECT COUNT(*) FROM orders WHERE ship_country = 'SG';
-- filtered=0.41  -> estimate ≈ 4,898 matching.
SELECT COUNT(*) FROM orders WHERE ship_country = 'SG';   -- 4845 actual.
-- 25x wrong -> 1% wrong, zero write cost, no index maintained. The query is
-- NOT faster — plans elsewhere (join order!) get smarter. Re-ANALYZE after
-- bulk loads; histograms are snapshots, not live.

-- ---------------------------------------------------------------------------
-- 2.14 Invisible + drop redundant
-- ---------------------------------------------------------------------------
SELECT table_name, redundant_index_name, dominant_index_name
FROM sys.schema_redundant_indexes WHERE table_schema = 'urbancart';
-- orders | idx_orders_customer | idx_orders_customer_date

ALTER TABLE orders ALTER INDEX idx_orders_customer INVISIBLE;
EXPLAIN SELECT id, status FROM orders WHERE customer_id = 137;
-- type=ref, key=idx_orders_customer_date, rows=243  — composite serves it.
ALTER TABLE orders DROP INDEX idx_orders_customer;
-- Safe drop, proven in advance. Every INSERT on orders now maintains
-- 3 secondary indexes instead of 4.

-- ---------------------------------------------------------------------------
-- Scorecard after chapter 2 (measured):
--   Q1 email lookup      ref              0.009 ms   (was 45 ms)
--   Q2 customer orders   ref, 243 rows    0.4 ms     (was 110 ms)
--   Q3 failed count      covering ref     ~1 ms      (was 100 ms)
--   Q4 monster           unchanged        ~4 s       -> chapter 3
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2.15 Deep dive: the optimizer's decision sheet
-- ---------------------------------------------------------------------------
SET optimizer_trace = 'enabled=on', optimizer_trace_max_mem_size = 262144;
EXPLAIN SELECT SUM(total_cents) FROM orders WHERE status = 'completed';
SELECT SUBSTRING(trace, LOCATE('considered_execution_plans', trace), 600) AS decision
FROM information_schema.optimizer_trace\G
SET optimizer_trace = 'enabled=off';
-- Measured (course container):
--   "access_type": "ref", "index": "idx_orders_status",
--       "rows": 597313, "cost": 63409.3, "chosen": true
--   "best_covering_index_scan": { "index": "idx_orders_date_status_total",
--       "cost": 134392, "chosen": false, "cause": "cost" }
-- Stopwatch truth (2.12): ref path 431 ms, forced scan 139 ms.
-- Failure 1: rows estimate 597k vs 1.03M actual (2x low).
-- Failure 2: 1M random secondary->clustered hops priced too cheap vs one
--            sequential pass. Cost units are a model, not milliseconds.
-- When trace and stopwatch disagree, the stopwatch wins -> IGNORE INDEX.

-- ---------------------------------------------------------------------------
-- 2.16 Deep dive: the prefix-index trade
-- ---------------------------------------------------------------------------
SELECT COUNT(DISTINCT LEFT(email,12)) AS pfx12, COUNT(*) AS total FROM customers;
--   16152 vs 300000 -> ~18.6 emails share each 12-char prefix. Bad sign.
CREATE INDEX idx_customers_email_pfx ON customers(email(12));
SHOW INDEX FROM customers WHERE Key_name LIKE 'idx_customers_email%';
--   full index  cardinality ~298422 | prefix cardinality ~14183 (sampled)
SELECT index_name, ROUND(stat_value*16384/1024/1024,1) AS size_mb
FROM mysql.innodb_index_stats
WHERE database_name='urbancart' AND table_name='customers'
  AND stat_name='size' AND index_name LIKE 'idx%';
--   idx_customers_email 14.6 MB | idx_customers_email_pfx 9.5 MB (-35%)
EXPLAIN ANALYZE SELECT id, full_name FROM customers USE INDEX (idx_customers_email_pfx)
WHERE email = 'amara.dubois150000@example.com';
--   -> Filter (email='...') (actual ..2.49 rows=1)
--       -> Index lookup via prefix (actual ..2.31 rows=2754)   <- 2754 fetches!
--   2.49 ms vs 9 µs on the full index. ~275x slower for 35% space.
DROP INDEX idx_customers_email_pfx ON customers;
-- Verdict: on UrbanCart, no. Prefix indexes pay only when the string's
-- entropy is front-loaded — measure COUNT(DISTINCT LEFT(col,n)) first.
