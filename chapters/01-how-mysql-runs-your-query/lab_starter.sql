-- ============================================================================
-- Chapter 1 lab starters — fill in the ___ blanks.
-- Run inside: docker exec -it mysql-tuning-course mysql -uroot -pcourse urbancart
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1.2 Sizing up the database
-- ---------------------------------------------------------------------------
SELECT table_name,
       table_rows,
       ROUND((data_length + index_length) / 1024 / 1024, 1) AS size_mb
FROM information_schema.___
WHERE table_schema = '___'
ORDER BY ___ DESC;

-- ---------------------------------------------------------------------------
-- 1.3 The customer lookup (run twice, note the warm timing)
-- ---------------------------------------------------------------------------
SELECT id, full_name, city
FROM customers
WHERE ___ = '___';

-- ---------------------------------------------------------------------------
-- 1.5 EXPLAIN the slow lookup
-- ---------------------------------------------------------------------------
___ SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';

-- ---------------------------------------------------------------------------
-- 1.7 Estimates vs reality
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE ___ = 'failed';

-- ---------------------------------------------------------------------------
-- 1.9 Revenue by region: the monster baseline
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT co.region,
       COUNT(DISTINCT o.id) AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price_cents) / 100, 2) AS revenue
FROM orders o
JOIN customers c    ON c.id = o.___
JOIN countries co   ON co.country_code = c.___
JOIN order_items oi ON oi.___ = o.id
WHERE o.status = 'completed'
GROUP BY co.region
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- 1.11 The slow query log
-- ---------------------------------------------------------------------------
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';
-- then from your shell:
--   docker exec mysql-tuning-course sh -c "tail -40 /var/lib/mysql/slow.log"

-- ---------------------------------------------------------------------------
-- 1.12 Top offenders with the sys schema
-- ---------------------------------------------------------------------------
SELECT query,
       exec_count,
       ROUND(avg_latency / 1e12, 2) AS avg_s,
       rows_examined_avg
FROM sys.___
WHERE db = 'urbancart'
ORDER BY ___ DESC
LIMIT 5;
