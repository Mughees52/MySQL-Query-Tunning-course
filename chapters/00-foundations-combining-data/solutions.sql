-- ============================================================================
-- Chapter 0 — solutions, with measured output (MySQL 8.4, 1G buffer pool).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0.2 Join-type arithmetic
-- ---------------------------------------------------------------------------
SELECT COUNT(*) FROM customers c INNER JOIN orders o ON o.customer_id = c.id;
-- 1,200,000  — one row per order; a 243-order customer appears 243 times.
SELECT COUNT(*) FROM customers c LEFT  JOIN orders o ON o.customer_id = c.id;
-- 1,208,266  — +8,266: the never-ordered customers, NULL-extended once each.
SELECT co.country_code, co.country_name
FROM countries co
LEFT JOIN customers c ON c.country_code = co.country_code
WHERE c.id IS NULL;
-- 5 rows: AR Argentina, BE Belgium, GR Greece, PK Pakistan, SA Saudi Arabia.
-- The NULL side of a LEFT JOIN is an answer, not missing data (-> lab 3.7).

-- ---------------------------------------------------------------------------
-- 0.3 FULL OUTER JOIN emulation
-- ---------------------------------------------------------------------------
WITH ship_stats AS (
  SELECT ship_country, COUNT(*) AS orders FROM orders GROUP BY ship_country)
SELECT co.country_code, co.country_name, s.ship_country, s.orders
FROM countries co LEFT JOIN ship_stats s ON s.ship_country = co.country_code
UNION ALL
SELECT NULL, NULL, s.ship_country, s.orders
FROM ship_stats s LEFT JOIN countries co ON co.country_code = s.ship_country
WHERE co.country_code IS NULL;
-- 32 rows: 17 matched + 15 lookup-only (never shipped to) + 0 ship-only.
-- UNION ALL because the arms cannot overlap — arm 2 keeps only rows arm 1
-- could not have produced. UNION would sort 32 rows to remove 0 duplicates.
-- Arm 2 doubling as a data-quality check: a rogue ship code would land there.

-- ---------------------------------------------------------------------------
-- 0.5 Subqueries in three positions
-- ---------------------------------------------------------------------------
-- SELECT position: plan prints
--   -> Select #2 (subquery in projection; run only once)
-- WHERE position: plan prints
--   -> Select #2 (subquery in condition; run only once)
SELECT COUNT(*) FROM orders
WHERE total_cents > (SELECT AVG(total_cents) FROM orders);
-- 543,009 orders above the mean. Uncorrelated scalar subqueries run ONCE.
-- Correlated ones run per row: fine at 1 µs/probe on an index (3.13),
-- fatal at 460 ms/probe (capstone step 4).

-- ---------------------------------------------------------------------------
-- 0.6 Your first CTE
-- ---------------------------------------------------------------------------
WITH country_rev AS (
  SELECT ship_country, COUNT(*) AS orders, SUM(total_cents) AS rev
  FROM orders WHERE status = 'completed' GROUP BY ship_country)
SELECT co.region, SUM(cr.orders) AS orders, ROUND(SUM(cr.rev)/100, 2) AS revenue
FROM country_rev cr
JOIN countries co ON co.country_code = cr.ship_country
GROUP BY co.region ORDER BY revenue DESC;
-- ~0.5 s. Top rows (revenue by SHIP-TO region — deliberately different from
-- the chapter-1 monster, which groups by the CUSTOMER's region):
--   Western Europe   386,885   287,832,285.99
--   North America    382,307   284,595,910.83
--   Southern Europe   67,472    50,093,918.71
-- Identical plan to the FROM-subquery version; WITH is free and readable.

-- ---------------------------------------------------------------------------
-- 0.8 Materialize a slow view
-- ---------------------------------------------------------------------------
-- Through the view: ~1.6 s PER QUERY (the 3-table join re-runs every time).
CREATE TEMPORARY TABLE tmp_geo AS
SELECT id, status, total_cents, order_date, region
FROM v_order_geo WHERE status = 'completed';   -- 2.5 s, once (1.03M rows)
ANALYZE TABLE tmp_geo;
-- Follow-up aggregates, measured: 0.18 s and 0.21 s  (~8x per query).
-- Break-even at the second use; profit forever after. Views store queries,
-- temp tables store DATA.
DROP VIEW v_order_geo;

-- ---------------------------------------------------------------------------
-- 0.9 The reopen gotcha + ANALYZE
-- ---------------------------------------------------------------------------
CREATE TEMPORARY TABLE tmp_de AS
SELECT id, customer_id, status, order_date, total_cents
FROM orders WHERE ship_country = 'DE';         -- 0.33 s, 119,605 rows
ANALYZE TABLE tmp_de;
SELECT status, COUNT(*), ROUND(AVG(total_cents)/100,2) FROM tmp_de GROUP BY status;
-- 27 ms  (base-table equivalent: 659 ms)

SELECT a.id FROM tmp_de a JOIN tmp_de b ON b.id = a.id LIMIT 1;
-- ERROR 1137 (HY000): Can't reopen table: 'a'
-- MySQL cannot reference a CREATE TEMPORARY TABLE table twice in one
-- statement (PostgreSQL can — classic porting trap). Workarounds: two temp
-- copies, or a CTE (internal materialization has no such limit).
