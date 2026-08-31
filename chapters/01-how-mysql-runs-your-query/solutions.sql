-- ============================================================================
-- Chapter 1 — solutions, with measured output (MySQL 8.4, 1G buffer pool).
-- Your machine's absolute numbers will differ; the plans and ratios won't.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1.2 Sizing up the database
-- ---------------------------------------------------------------------------
SELECT table_name,
       table_rows,
       ROUND((data_length + index_length) / 1024 / 1024, 1) AS size_mb
FROM information_schema.tables
WHERE table_schema = 'urbancart'
ORDER BY size_mb DESC;
-- +-------------+-----------+---------+
-- | order_items | ~3.0M     | 146.7   |
-- | payments    | ~1.07M    |  84.6   |
-- | orders      | ~1.2M     |  76.6   |
-- | customers   | ~300k     |  26.6   |
-- | products    | 5000      |   0.4   |
-- | countries   | 32        |   0.0   |
-- +-------------+-----------+---------+
-- table_rows is an InnoDB *estimate* — expect it to be a few % off.

-- ---------------------------------------------------------------------------
-- 1.3 The customer lookup
-- ---------------------------------------------------------------------------
SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';
-- 1 row (id 150000, Amara Dubois, ...). Warm run: ~45 ms.
-- ~45 ms of CPU to return one row. Now imagine it on every support search.

-- ---------------------------------------------------------------------------
-- 1.5 EXPLAIN the slow lookup
-- ---------------------------------------------------------------------------
EXPLAIN SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';
-- type: ALL | possible_keys: NULL | key: NULL | rows: 298422 | filtered: 10.00
-- Extra: Using where
-- Full scan; no index exists that could serve the predicate; the 10% guess
-- is a hard-coded default for equality on a column with no statistics.

-- ---------------------------------------------------------------------------
-- 1.7 Estimates vs reality
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE status = 'failed';
-- -> Aggregate: count(0)                        (actual time=99.8 rows=1)
--     -> Filter: (orders.status = 'failed')
--            (cost=120689 rows=119463)          (actual time=..99.6 rows=11826)
--         -> Table scan on orders (rows=1.19e6) (actual .. rows=1.2e6)
-- Estimate: 119,463 matching rows. Actual: 11,826. A 10x overestimate —
-- the same fixed 10% guess. Chapter 2 fixes this with a histogram.

-- ---------------------------------------------------------------------------
-- 1.9 Revenue by region: the monster baseline
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT co.region,
       COUNT(DISTINCT o.id) AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price_cents) / 100, 2) AS revenue
FROM orders o
JOIN customers c    ON c.id = o.customer_id
JOIN countries co   ON co.country_code = c.country_code
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status = 'completed'
GROUP BY co.region
ORDER BY revenue DESC;
-- Total: ~4.0 s. Reading the tree bottom-up:
--   -> Table scan on oi (3M rows, ~206 ms)         <- the flood starts here
--   -> 3M single-row PK lookups into orders, filter status  (~1.2 s)
--   -> 2.58M survivors -> PK lookups into customers, countries (~1.7 s)
--   -> Sort 2.58M rows by region (~0.7 s), group to 12 rows
-- ~9M rows examined to send 12. Remember this number.

-- ---------------------------------------------------------------------------
-- 1.11 The slow query log
-- ---------------------------------------------------------------------------
SHOW VARIABLES LIKE 'slow_query_log%';   -- ON, /var/lib/mysql/slow.log
SHOW VARIABLES LIKE 'long_query_time';   -- 0.500000
-- shell:  docker exec mysql-tuning-course sh -c "tail -40 /var/lib/mysql/slow.log"
-- The monster's entry shows:
--   # Query_time: ~4.0  Lock_time: ...  Rows_sent: 12  Rows_examined: ~9M
-- Rows_examined >> Rows_sent is the smell. The log is your flight recorder.

-- ---------------------------------------------------------------------------
-- 1.12 Top offenders with the sys schema
-- ---------------------------------------------------------------------------
SELECT query,
       exec_count,
       ROUND(avg_latency / 1e12, 2) AS avg_s,
       rows_examined_avg
FROM sys.x$statement_analysis
WHERE db = 'urbancart'
ORDER BY avg_latency DESC
LIMIT 5;
-- Your chapter-1 history, ranked by pain. The monster tops the list;
-- the email lookup appears once per distinct literal, normalized to `?`.
-- Real sessions START here: pick the target by exec_count x avg_latency.

-- ---------------------------------------------------------------------------
-- 1.13 Baseline scorecard — measured reference values
-- ---------------------------------------------------------------------------
-- Q1 customer by email        ALL, 298k rows examined      ~45 ms
-- Q2 orders of customer 137   ALL, 1.2M rows examined      ~110 ms
-- Q3 failed orders count      ALL, 1.2M rows examined      ~100 ms
-- Q4 revenue by region        ALL on oi + 3M PK lookups    ~4.0 s

-- ---------------------------------------------------------------------------
-- 1.14 Deep dive: the optimizer trace + buffer pool
-- ---------------------------------------------------------------------------
SET optimizer_trace = 'enabled=on';
SELECT COUNT(*) FROM orders WHERE customer_id = 137;
SELECT SUBSTRING(trace, LOCATE('rows_estimation', trace), 700) AS cost_math
FROM information_schema.optimizer_trace\G
SET optimizer_trace = 'enabled=off';
-- Measured on the course container:
--   "table_scan": { "rows": 1194627, "cost": 120691 }
-- In the chapter-1 state (no secondary indexes) the scan runs unopposed —
-- re-run after chapter 2 and range_analysis fills with candidate indexes
-- and their costs. Cost is in the optimizer's own units (page reads + row
-- evaluations), NOT time — comparing costs across different queries is
-- meaningless; comparing candidate plans of ONE query is exactly what the
-- optimizer does.

SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read%';
--   Innodb_buffer_pool_read_requests  ~10,426,299,453   (logical reads)
--   Innodb_buffer_pool_reads               ~12,150      (had to touch disk)
-- Miss rate ≈ 0.0001%. The dataset lives in the 1G buffer pool; every
-- timing in this course measures query SHAPE, not disk luck.
