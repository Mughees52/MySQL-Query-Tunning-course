-- ============================================================================
-- Chapter 0 lab starters — fill in the ___ blanks.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0.2 Join-type arithmetic
-- ---------------------------------------------------------------------------
SELECT COUNT(*) FROM customers c ___ JOIN orders o ON o.customer_id = c.id;
SELECT COUNT(*) FROM customers c ___ JOIN orders o ON o.customer_id = c.id;

-- countries with no customers at all:
SELECT co.country_code, co.country_name
FROM countries co
LEFT JOIN customers c ON c.country_code = co.country_code
WHERE c.___ IS NULL;

-- ---------------------------------------------------------------------------
-- 0.3 FULL OUTER JOIN emulation (MySQL has none!)
-- ---------------------------------------------------------------------------
WITH ship_stats AS (
  SELECT ship_country, COUNT(*) AS orders
  FROM orders GROUP BY ship_country)
SELECT co.country_code, co.country_name, s.ship_country, s.orders
FROM countries co ___ JOIN ship_stats s ON s.ship_country = co.country_code
UNION ___
SELECT NULL, NULL, s.ship_country, s.orders
FROM ship_stats s ___ JOIN countries co ON co.country_code = s.ship_country
WHERE co.___ IS NULL;

-- ---------------------------------------------------------------------------
-- 0.5 Subqueries in three positions
-- ---------------------------------------------------------------------------
-- SELECT position (scalar):
EXPLAIN FORMAT=TREE
SELECT ship_country,
       ROUND(AVG(total_cents)/100, 2) AS country_avg,
       (SELECT ___ FROM orders) AS global_avg
FROM orders
GROUP BY ship_country;

-- WHERE position (dynamic filter):
EXPLAIN FORMAT=TREE
SELECT COUNT(*) FROM orders
WHERE total_cents > (SELECT ___ FROM orders);

-- ---------------------------------------------------------------------------
-- 0.6 Your first CTE
-- ---------------------------------------------------------------------------
WITH country_rev AS (
  SELECT ship_country, COUNT(*) AS orders, SUM(total_cents) AS rev
  FROM orders WHERE status = '___'
  GROUP BY ship_country)
SELECT co.region, SUM(cr.orders) AS orders, ROUND(SUM(cr.rev)/100, 2) AS revenue
FROM ___ cr
JOIN countries co ON co.country_code = cr.ship_country
GROUP BY co.region ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- 0.8 Materialize a slow view
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_order_geo AS
SELECT o.id, o.status, o.total_cents, o.order_date, co.region
FROM orders o
JOIN customers c  ON c.id = o.customer_id
JOIN countries co ON co.country_code = c.country_code;

SELECT region, COUNT(*) FROM v_order_geo WHERE status='completed' GROUP BY region;
-- run it twice; time both. Then:

CREATE TEMPORARY TABLE tmp_geo AS
SELECT ___ FROM v_order_geo WHERE status = 'completed';
ANALYZE TABLE ___;

SELECT region, COUNT(*) FROM tmp_geo GROUP BY region;
SELECT region, ROUND(AVG(total_cents)/100,2) FROM tmp_geo GROUP BY region;

DROP VIEW v_order_geo;

-- ---------------------------------------------------------------------------
-- 0.9 The reopen gotcha + ANALYZE
-- ---------------------------------------------------------------------------
CREATE TEMPORARY TABLE tmp_de AS
SELECT id, customer_id, status, order_date, total_cents
FROM orders WHERE ship_country = 'DE';
___ TABLE tmp_de;

SELECT status, COUNT(*), ROUND(AVG(total_cents)/100,2) FROM tmp_de GROUP BY status;

-- now try it (and read the error):
SELECT a.id FROM tmp_de a JOIN tmp_de b ON b.id = a.id LIMIT 1;
