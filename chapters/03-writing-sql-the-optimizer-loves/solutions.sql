-- ============================================================================
-- Chapter 3 — solutions, with measured output (MySQL 8.4, 1G buffer pool).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 3.3 SELECT * vs projected columns
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT * FROM orders WHERE order_date >= '2025-08-01';
-- -> Index range scan ... with index condition   (actual time=6.5..68.7 rows=33189)
--    Range-seeks the index, then fetches every full row from the table.

EXPLAIN ANALYZE SELECT id, order_date, status, total_cents
FROM orders WHERE order_date >= '2025-08-01';
-- -> Covering index range scan on idx_orders_date_status_total
--        (actual time=0.04..2.9 rows=33189)
-- 69 ms -> 2.9 ms (23x), same rows. The columns you DIDN'T select were
-- the expensive part: dropping them let the index answer alone.

-- ---------------------------------------------------------------------------
-- 3.5 OR vs IN vs UNION
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE customer_id IN (137, 42007, 250999);
-- -> Covering index range scan over 3 ranges, 249 rows, ~0.06 ms. IN = seeks.

EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE customer_id = 137 OR id = 500000;
-- -> Filter (...) -> Covering index SCAN, 1.2M entries, ~90 ms.
--    One tree cannot seek two different columns.

EXPLAIN ANALYZE
SELECT COUNT(*) FROM (
  SELECT id FROM orders WHERE customer_id = 137
  UNION
  SELECT id FROM orders WHERE id = 500000) u;
-- -> two index seeks + dedup materialization: 244 rows, ~0.14 ms. 650x.
--    UNION (not UNION ALL): keeps OR's semantics if a row matches both arms.

EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE customer_id = 137 OR coupon_code = 'SAVE7';
-- -> Table scan, ~81 ms. One unindexed arm poisons the whole OR.

-- ---------------------------------------------------------------------------
-- 3.6 The NOT IN null bomb
-- ---------------------------------------------------------------------------
-- Naive: returns 0 rows. Silently. (Correct answer: 15.)
-- The subquery's coupon_code list contains NULLs (most orders have no
-- coupon). x NOT IN (..., NULL) == x<>... AND x<>NULL == UNKNOWN -> row
-- dropped -> empty result, no warning.

-- fix (a):
SELECT DISTINCT coupon_code FROM orders
WHERE coupon_code IS NOT NULL
  AND coupon_code NOT IN (SELECT coupon_code FROM orders
                          WHERE status = 'cancelled'
                            AND order_date >= '2025-06-15' AND order_date < '2025-06-16'
                            AND coupon_code IS NOT NULL);   -- 15 rows

-- fix (b):
SELECT DISTINCT o.coupon_code FROM orders o
WHERE o.coupon_code IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM orders c
                  WHERE c.status = 'cancelled'
                    AND c.order_date >= '2025-06-15' AND c.order_date < '2025-06-16'
                    AND c.coupon_code = o.coupon_code);     -- 15 rows
-- NOT EXISTS tests row existence, never compares to NULL: immune by design.

-- ---------------------------------------------------------------------------
-- 3.7 Three anti-join shapes — all return 8,266
-- ---------------------------------------------------------------------------
-- LEFT JOIN ... IS NULL:  ~248 ms
--   -> Nested loop antijoin: per customer, one covering-index probe.
-- NOT EXISTS:             ~377 ms
--   -> Materialize with deduplication (291,734 ids) then 300k hash lookups.
-- NOT IN:                 ~342 ms
--   -> same materialize plan (safe only because customer_id is NOT NULL).
-- Folklore ranks these the other way around. Data > folklore.

-- ---------------------------------------------------------------------------
-- 3.9 Hash join vs nested loop
-- ---------------------------------------------------------------------------
-- Optimizer's pick (nested loop through products PRIMARY):
--   -> Table scan on oi (3M) -> 3M Single-row index lookups: total ~1.74 s
-- Forced hash:
EXPLAIN ANALYZE
SELECT p.category, ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS rev
FROM order_items oi JOIN products p IGNORE INDEX (PRIMARY) ON p.id = oi.product_id
GROUP BY p.category;
--   -> Inner hash join (p.id = oi.product_id): build on 5k products,
--      probe with one 3M scan: total ~0.74 s. 2.4x faster than the
--      optimizer's choice — MySQL only *considers* hash join when no index
--      is usable. Know when to overrule it (and document every hint!).

-- The everyday case:
--   before: join key unindexed -> optimizer drives from ALL 1.07M payments,
--           1.07M PK probes into orders: ~541 ms
CREATE INDEX idx_payments_order ON payments(order_id);
--   after:  drives from 10k recent orders -> 10k index lookups: ~25 ms
-- Join keys deserve indexes. Still true in the hash-join era.

-- ---------------------------------------------------------------------------
-- 3.10 ON vs WHERE on a LEFT JOIN
-- ---------------------------------------------------------------------------
-- ON  p.method='klarna'  (filter inside join):  8,550 rows  (all orders kept)
-- WHERE p.method='klarna' (filter after join):  1,553 rows  (LEFT became INNER:
--   NULL-extended rows fail the WHERE and vanish — silently).
-- On INNER joins, ON vs WHERE placement is identical. On OUTER joins it is
-- a different query. Correctness first.

-- ---------------------------------------------------------------------------
-- 3.12 The monster at the right grain
-- ---------------------------------------------------------------------------
-- attempt 1 (pre-aggregate items):        4.14 s  — WORSE than 4.0 s baseline.
--   Grouping 3M rows into a 1.2M temp table is the bottleneck; no shrinkage.
-- attempt 2 (order grain, no items join): 1.75 s  — identical results.
SELECT co.region, COUNT(*) AS orders, ROUND(SUM(o.total_cents)/100, 2) AS revenue
FROM orders o IGNORE INDEX (idx_orders_status)      -- attempt 2b: 1.47 s
JOIN customers c  ON c.id = o.customer_id
JOIN countries co ON co.country_code = c.country_code
WHERE o.status = 'completed'
GROUP BY co.region ORDER BY revenue DESC;
-- COUNT(DISTINCT o.id) became COUNT(*) — no fan-out, no dedup tax.
-- Verify identity vs the original monster before celebrating (we did:
-- row-for-row equal). 4.0 s -> 1.47 s by deleting a join.

-- ---------------------------------------------------------------------------
-- 3.13 Latest order per customer, three shapes
-- ---------------------------------------------------------------------------
-- A correlated MAX:   ~320 ms — 300k dependent subqueries, ~1 µs each
--                     (Covering index lookup, loops=300000). Returns 300k
--                     rows incl. NULL for never-ordered customers.
-- B GROUP BY:         ~97 ms  — "Covering index skip scan for grouping":
--                     jumps customer to customer inside the composite.
--                     Returns 291,734 rows (only customers with orders).
-- C ROW_NUMBER():     ~900 ms — sorts + materializes all 1.2M rows first.
-- The fashionable shape lost. Shapes are fast or slow ON YOUR INDEXES.

-- ---------------------------------------------------------------------------
-- 3.14 One CTE, used twice
-- ---------------------------------------------------------------------------
WITH monthly AS (
  SELECT EXTRACT(YEAR_MONTH FROM order_date) AS ym, SUM(total_cents) AS rev
  FROM orders WHERE status = 'completed' GROUP BY ym)
SELECT a.ym, ROUND(a.rev/100, 2) AS rev,
       ROUND((a.rev - b.rev) / b.rev * 100, 1) AS mom_pct
FROM monthly a
LEFT JOIN monthly b ON b.ym = PERIOD_ADD(a.ym, -1)
ORDER BY a.ym;
-- CTE version:    ~0.51 s. Second reference's plan node reads:
--                 "Materialize CTE monthly if needed ... (never executed)"
-- Inline-twice:   ~0.96 s (aggregates 1.03M orders twice).
-- Reused expensive intermediate -> CTE is a performance feature.

-- ---------------------------------------------------------------------------
-- Scorecard after chapter 3:
--   Q1 0.009 ms | Q2 0.4 ms | Q3 ~1 ms | Q4 1.47 s (was 4.0 s)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 3.15 Deep dive: semijoin strategies
-- ---------------------------------------------------------------------------
EXPLAIN FORMAT=TREE
SELECT COUNT(*) FROM customers c
WHERE c.id IN (SELECT o.customer_id FROM orders o WHERE o.status = 'refunded');
-- semijoin ON (default), measured plan:
--   -> Nested loop inner join
--       -> Table scan on <subquery2>
--           -> Materialize with deduplication (rows≈70324)
--               -> Index lookup on o using idx_orders_status (status='refunded')
--       -> Single-row covering PK lookup on c
-- The IN became a JOIN against a deduplicated build side.

SET optimizer_switch = 'semijoin=off';
-- same EXPLAIN, measured plan:
--   -> Filter: <in_optimizer>(c.id, c.id in (select #2))
--       -> Covering index scan on c (298k rows)          <- customers drives
--       -> Select #2: per-row probe of a materialized subquery
SET optimizer_switch = 'semijoin=on';
-- Same rows either way; the transform changes who drives and what's reusable.

-- ---------------------------------------------------------------------------
-- 3.16 Deep dive: derived_merge
-- ---------------------------------------------------------------------------
EXPLAIN SELECT * FROM (SELECT id, status FROM orders WHERE customer_id = 137) d
WHERE d.status = 'completed';
-- merged: ONE row — type=ref, key=idx_orders_customer_date, rows=243.
-- The derived table is gone; both predicates pushed into one index access.

SET optimizer_switch = 'derived_merge=off';
-- unmerged: TWO rows —
--   1 PRIMARY  <derived2>  ALL   rows=121
--   2 DERIVED  orders      ref   idx_orders_customer_date  rows=243
-- A real temp table is built, then scanned. Small tax here; on reused CTEs
-- (3.14) materialization is what you WANT — the point is: it's a choice the
-- optimizer makes, and EXPLAIN shows you which way it went.
SET optimizer_switch = 'derived_merge=on';

-- ---------------------------------------------------------------------------
-- 3.17 GROUP BY discipline + DISTINCT's cost
-- ---------------------------------------------------------------------------
SELECT ship_country, status, COUNT(*) FROM orders GROUP BY ship_country;
-- ERROR 1055 (42000): Expression #2 of SELECT list is not in GROUP BY clause
-- and contains nonaggregated column ... incompatible with only_full_group_by
-- Right and proper: each country has MANY statuses; which one would it show?
-- Pre-5.7 MySQL silently returned an arbitrary one. Never disable the mode;
-- fix the query (add to GROUP BY, or aggregate it).

EXPLAIN ANALYZE SELECT DISTINCT status FROM orders;
EXPLAIN ANALYZE SELECT status FROM orders GROUP BY status;
-- BOTH: -> Covering index skip scan for deduplication on idx_orders_status
--          (~0.7 ms). DISTINCT == GROUP-BY-without-aggregates. Same engine op.

EXPLAIN ANALYZE SELECT DISTINCT status FROM orders
IGNORE INDEX (idx_orders_status, idx_orders_date_status_total, idx_orders_customer_date);
-- -> Temporary table with deduplication (1.2M rows in) -> 5 rows out. 159 ms.
-- DISTINCT runs at pipeline position 6 (after SELECT): it deduplicates
-- whatever survived — 240x cheaper when an index already knows the answer.
