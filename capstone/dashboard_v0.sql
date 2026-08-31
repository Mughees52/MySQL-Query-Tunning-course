-- ============================================================================
-- Capstone v0 — the dashboard query, exactly as found in the app.
-- DO NOT "fix while reading". Baseline it first (exercise 4.8).
--
-- WARNING: this does not finish in reasonable time (we killed it at 21 min).
-- Run it bounded, so MySQL aborts it for you:
--     SELECT /*+ MAX_EXECUTION_TIME(600000) */ o.ship_country, ...
-- ============================================================================
SELECT o.ship_country,
       COUNT(DISTINCT o.id) AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS revenue,
       ROUND(SUM(oi.quantity * oi.unit_price_cents)/COUNT(DISTINCT o.id)/100, 2) AS avg_order_value,
       (SELECT p2.category
        FROM order_items oi2
        JOIN products p2 ON p2.id = oi2.product_id
        JOIN orders o2   ON o2.id = oi2.order_id
        WHERE o2.ship_country = o.ship_country
          AND DATE(o2.order_date) >= '2025-05-29'
          AND o2.status = 'completed'
        GROUP BY p2.category
        ORDER BY SUM(oi2.quantity * oi2.unit_price_cents) DESC
        LIMIT 1) AS top_category
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
WHERE DATE(o.order_date) >= '2025-05-29'
  AND o.status = 'completed'
  AND o.id NOT IN (SELECT order_id FROM payments WHERE status = 'refunded')
GROUP BY o.ship_country
ORDER BY revenue DESC;
