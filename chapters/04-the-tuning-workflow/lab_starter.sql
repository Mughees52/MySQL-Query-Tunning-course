-- ============================================================================
-- Chapter 4 lab starters — fill in the ___ blanks.
-- Capstone SQL lives in capstone/dashboard_v0.sql and dashboard_steps.sql.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 4.2 / 4.3 Reading a big plan: top 10 cities by completed revenue
-- ---------------------------------------------------------------------------
EXPLAIN
SELECT c.city, ROUND(SUM(o.total_cents)/100, 2) AS rev
FROM orders o
JOIN customers c ON c.id = o.customer_id
WHERE o.status = 'completed'
GROUP BY c.city
ORDER BY rev DESC
LIMIT 10;

EXPLAIN ANALYZE
SELECT c.city, ROUND(SUM(o.total_cents)/100, 2) AS rev
FROM orders o
JOIN customers c ON c.id = o.customer_id
WHERE o.status = 'completed'
GROUP BY c.city
ORDER BY rev DESC
LIMIT 10;

-- 4.3 (a): why is the temporary table unavoidable?
-- 4.3 (b): does ORDER BY c.city still filesort? test it.
-- 4.3 bonus: dodge the status index and re-measure
EXPLAIN ANALYZE
SELECT c.city, ROUND(SUM(o.total_cents)/100, 2) AS rev
FROM orders o ___ ___ (idx_orders_status)
JOIN customers c ON c.id = o.customer_id
WHERE o.status = 'completed'
GROUP BY c.city
ORDER BY rev DESC
LIMIT 10;

-- ---------------------------------------------------------------------------
-- 4.5 Deep pagination
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
ORDER BY id LIMIT 20 OFFSET 1000000;

EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE id > ___ ORDER BY id LIMIT 20;

-- ---------------------------------------------------------------------------
-- 4.8 Capstone step 1 — baseline (bounded! v0 does not finish)
-- ---------------------------------------------------------------------------
--   Add /*+ MAX_EXECUTION_TIME(600000) */ after SELECT in dashboard_v0.sql,
--   then run it. Record the baseline as "did not complete; aborted at 10 min".
--   (Escape hatch: SHOW PROCESSLIST; KILL <id>;)

-- ---------------------------------------------------------------------------
-- 4.9 Capstone step 2 — sargable dates (edit v0: both occurrences)
-- ---------------------------------------------------------------------------
--   WHERE DATE(o.order_date)  >= '2025-05-29'   ->   o.order_date  >= '___'
--   AND   DATE(o2.order_date) >= '2025-05-29'   ->   o2.order_date >= '___'
--   Equivalent BY DEFINITION (no diff needed — or possible: still >10 min).
--   EXPLAIN it anyway and compare access paths against v0's plan.

-- ---------------------------------------------------------------------------
-- 4.10 Capstone step 3 — the join index
-- ---------------------------------------------------------------------------
CREATE INDEX idx_items_order ON order_items(___);
-- re-run v1's text UNCHANGED — it finishes now (~9 s). Save the 17-row
-- output as the identity oracle:
--   docker exec -i mysql-tuning-course mysql -uroot -pcourse urbancart \
--       < your_v1.sql > /tmp/v2.txt
-- Sound because every step so far was provably equivalent (date rewrite by
-- definition; an index cannot change results). Diff all later steps vs it.

-- ---------------------------------------------------------------------------
-- 4.11 Capstone step 4 — one-pass top categories (skeleton)
-- ---------------------------------------------------------------------------
WITH top_cat AS (
  SELECT ship_country, category FROM (
    SELECT o2.ship_country, p2.category,
           ROW_NUMBER() OVER (PARTITION BY ___
                              ORDER BY SUM(oi2.quantity * oi2.unit_price_cents) DESC) AS rn
    FROM orders o2
    JOIN order_items oi2 ON oi2.order_id = o2.id
    JOIN products p2     ON p2.id = oi2.product_id
    WHERE o2.order_date >= '2025-05-29' AND o2.status = 'completed'
    GROUP BY o2.ship_country, p2.category) ranked
  WHERE rn = ___)
SELECT o.ship_country,
       COUNT(DISTINCT o.id) AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS revenue,
       ROUND(SUM(oi.quantity * oi.unit_price_cents)/COUNT(DISTINCT o.id)/100, 2) AS avg_order_value,
       tc.category AS top_category
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
JOIN top_cat tc     ON tc.ship_country = o.ship_country
WHERE o.order_date >= '2025-05-29' AND o.status = 'completed'
  AND o.id NOT IN (SELECT order_id FROM payments WHERE status = 'refunded')
GROUP BY o.ship_country, tc.category
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- 4.12 Capstone step 5 — refund exclusion, the safe fast shape
-- ---------------------------------------------------------------------------
--   AND o.id NOT IN (SELECT order_id FROM payments WHERE status='refunded')
-- becomes:
--   AND NOT ___ (SELECT 1 FROM payments p
--                WHERE p.___ = o.id AND p.status = 'refunded')

-- ---------------------------------------------------------------------------
-- 4.13 Capstone step 6 — right grain (delete the outer items join)
-- ---------------------------------------------------------------------------
--   revenue        -> ROUND(SUM(o.___)/100, 2)
--   orders         -> COUNT(*)
--   avg order value-> SUM(o.___)/COUNT(*)
--   FROM orders o JOIN top_cat tc ...   (no order_items in the outer query)
-- Then v6 (capstone/dashboard_steps.sql): IGNORE INDEX (idx_orders_status)
-- on both order reads + aggregate to 17 country rows BEFORE joining the CTE.
-- Final: EXPLAIN ANALYZE, verify the < 2 s requirement, diff vs /tmp/v2.txt.
