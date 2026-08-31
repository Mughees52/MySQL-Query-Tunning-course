-- ============================================================================
-- Capstone — one file per step of the rescue. Run a step, measure it, and
-- (from v2 on) diff its result against the saved v2 oracle before moving on.
-- v0 never finishes; v1 and v2 are provably equivalent to it by construction.
-- Timings: see walkthrough.md (measured on the course container).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- v1 — STEP 2 (exercise 4.9): make every date filter sargable.
-- DATE(order_date) >= 'd'  ≡  order_date >= 'd 00:00:00'  (bare column!)
-- ---------------------------------------------------------------------------
SELECT o.ship_country,
       COUNT(DISTINCT o.id) AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS revenue,
       ROUND(SUM(oi.quantity * oi.unit_price_cents)/COUNT(DISTINCT o.id)/100, 2) AS avg_order_value,
       (SELECT p2.category
        FROM order_items oi2
        JOIN products p2 ON p2.id = oi2.product_id
        JOIN orders o2   ON o2.id = oi2.order_id
        WHERE o2.ship_country = o.ship_country
          AND o2.order_date >= '2025-05-29'
          AND o2.status = 'completed'
        GROUP BY p2.category
        ORDER BY SUM(oi2.quantity * oi2.unit_price_cents) DESC
        LIMIT 1) AS top_category
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
WHERE o.order_date >= '2025-05-29'
  AND o.status = 'completed'
  AND o.id NOT IN (SELECT order_id FROM payments WHERE status = 'refunded')
GROUP BY o.ship_country
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- v2 — STEP 3 (exercise 4.10): give the items join its index.
-- ---------------------------------------------------------------------------
CREATE INDEX idx_items_order ON order_items(order_id);
-- then re-run v1 unchanged.

-- ---------------------------------------------------------------------------
-- v3 — STEP 4 (exercise 4.11): kill the per-country correlated subquery.
-- Compute every country's top category ONCE with a window over one grouped
-- pass, and join it in.
-- ---------------------------------------------------------------------------
WITH top_cat AS (
  SELECT ship_country, category FROM (
    SELECT o2.ship_country, p2.category,
           ROW_NUMBER() OVER (PARTITION BY o2.ship_country
                              ORDER BY SUM(oi2.quantity * oi2.unit_price_cents) DESC) AS rn
    FROM orders o2
    JOIN order_items oi2 ON oi2.order_id = o2.id
    JOIN products p2     ON p2.id = oi2.product_id
    WHERE o2.order_date >= '2025-05-29'
      AND o2.status = 'completed'
    GROUP BY o2.ship_country, p2.category) ranked
  WHERE rn = 1)
SELECT o.ship_country,
       COUNT(DISTINCT o.id) AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS revenue,
       ROUND(SUM(oi.quantity * oi.unit_price_cents)/COUNT(DISTINCT o.id)/100, 2) AS avg_order_value,
       tc.category AS top_category
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
JOIN top_cat tc     ON tc.ship_country = o.ship_country
WHERE o.order_date >= '2025-05-29'
  AND o.status = 'completed'
  AND o.id NOT IN (SELECT order_id FROM payments WHERE status = 'refunded')
GROUP BY o.ship_country, tc.category
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- v4 — STEP 5 (exercise 4.12): NOT IN -> NOT EXISTS.
-- Replace in v3:
--   AND o.id NOT IN (SELECT order_id FROM payments WHERE status='refunded')
-- with:
--   AND NOT EXISTS (SELECT 1 FROM payments p
--                   WHERE p.order_id = o.id AND p.status = 'refunded')
-- Measured: identical plan and time — MySQL already antijoined the NOT IN
-- because payments.order_id is NOT NULL. Kept as NULL-safety insurance.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- v5 — STEP 6a (exercise 4.13): the grain fix. Revenue of an order IS
-- orders.total_cents — the outer items join was never needed.
-- ---------------------------------------------------------------------------
WITH top_cat AS (
  SELECT ship_country, category FROM (
    SELECT o2.ship_country, p2.category,
           ROW_NUMBER() OVER (PARTITION BY o2.ship_country
                              ORDER BY SUM(oi2.quantity * oi2.unit_price_cents) DESC) AS rn
    FROM orders o2
    JOIN order_items oi2 ON oi2.order_id = o2.id
    JOIN products p2     ON p2.id = oi2.product_id
    WHERE o2.order_date >= '2025-05-29'
      AND o2.status = 'completed'
    GROUP BY o2.ship_country, p2.category) ranked
  WHERE rn = 1)
SELECT o.ship_country,
       COUNT(*) AS orders,
       ROUND(SUM(o.total_cents)/100, 2) AS revenue,
       ROUND(SUM(o.total_cents)/COUNT(*)/100, 2) AS avg_order_value,
       tc.category AS top_category
FROM orders o
JOIN top_cat tc ON tc.ship_country = o.ship_country
WHERE o.order_date >= '2025-05-29'
  AND o.status = 'completed'
  AND NOT EXISTS (SELECT 1 FROM payments p
                  WHERE p.order_id = o.id AND p.status = 'refunded')
GROUP BY o.ship_country, tc.category
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- v6 — STEP 6b (exercise 4.13): final plan review pays twice more.
--   * IGNORE INDEX (idx_orders_status) on BOTH order reads: the date range
--     drives instead of the 86%-selectivity status index (chapter 2.12).
--   * Aggregate the outer orders to 17 country rows BEFORE joining the
--     17-row CTE (chapter 3.12, properly applied this time).
-- Measured: 1.14 s, diff clean. Ship it.
-- ---------------------------------------------------------------------------
WITH top_cat AS (
  SELECT ship_country, category FROM (
    SELECT o2.ship_country, p2.category,
           ROW_NUMBER() OVER (PARTITION BY o2.ship_country
                              ORDER BY SUM(oi2.quantity * oi2.unit_price_cents) DESC) AS rn
    FROM orders o2 IGNORE INDEX (idx_orders_status)
    JOIN order_items oi2 ON oi2.order_id = o2.id
    JOIN products p2     ON p2.id = oi2.product_id
    WHERE o2.order_date >= '2025-05-29'
      AND o2.status = 'completed'
    GROUP BY o2.ship_country, p2.category) ranked
  WHERE rn = 1),
per_country AS (
  SELECT o.ship_country, COUNT(*) AS orders, SUM(o.total_cents) AS rev
  FROM orders o IGNORE INDEX (idx_orders_status)
  WHERE o.order_date >= '2025-05-29'
    AND o.status = 'completed'
    AND NOT EXISTS (SELECT 1 FROM payments p
                    WHERE p.order_id = o.id AND p.status = 'refunded')
  GROUP BY o.ship_country)
SELECT pc.ship_country,
       pc.orders,
       ROUND(pc.rev/100, 2) AS revenue,
       ROUND(pc.rev/pc.orders/100, 2) AS avg_order_value,
       tc.category AS top_category
FROM per_country pc
JOIN top_cat tc ON tc.ship_country = pc.ship_country
ORDER BY revenue DESC;
