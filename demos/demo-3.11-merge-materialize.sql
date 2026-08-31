-- ============================================================================
-- LIVE DEMO SCRIPT · video 15 · lesson 3.11 — Merge or materialize (the monster falls)
-- Deck: chapter3 slides 7–8
-- STATE REQUIRED: canonical ch-2 state + idx_payments_order. CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 7] the monster as-written — item grain, COUNT(DISTINCT) tax · ~4 s
-- (the exact monster text is in chapter-1 lab 1.9 / your scorecard)

-- STEP 2 · the grain insight — orders already carries total_cents. Delete the join.
-- expect ~1.75 s, byte-identical result
SELECT co.region, COUNT(*) AS orders, ROUND(SUM(o.total_cents)/100, 2) AS revenue
FROM orders o
JOIN customers c  ON c.id = o.customer_id
JOIN countries co ON co.country_code = c.country_code
WHERE o.status = 'completed'
GROUP BY co.region ORDER BY revenue DESC;

-- STEP 3 · the chapter-2 payoff stacks — skip the poisonous status index · ~1.47 s
SELECT co.region, COUNT(*) AS orders, ROUND(SUM(o.total_cents)/100, 2) AS revenue
FROM orders o IGNORE INDEX (idx_orders_status)
JOIN customers c  ON c.id = o.customer_id
JOIN countries co ON co.country_code = c.country_code
WHERE o.status = 'completed'
GROUP BY co.region ORDER BY revenue DESC;

-- STEP 4 · [SLIDE 8] three shapes race — latest order per customer
-- A · correlated MAX — 300k probes at ~1 µs each · ~320 ms
EXPLAIN ANALYZE
SELECT c.id, (SELECT MAX(o.order_date) FROM orders o WHERE o.customer_id = c.id) AS last_order
FROM customers c;
-- B · GROUP BY — loose index skip scan · ~97 ms · the winner
EXPLAIN ANALYZE
SELECT customer_id, MAX(order_date) FROM orders GROUP BY customer_id;
-- C · ROW_NUMBER() — sorts + materializes all 1.2M · ~900 ms · fashionable, last
EXPLAIN ANALYZE
SELECT customer_id, order_date FROM (
  SELECT customer_id, order_date,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rn
  FROM orders) x
WHERE rn = 1;

-- STEP 5 · [SLIDE 8, footer] one CTE, used twice — materialized ONCE · ~0.51 s
-- find "(never executed)" on the second reference in the plan
EXPLAIN ANALYZE
WITH monthly AS (
  SELECT EXTRACT(YEAR_MONTH FROM order_date) AS ym, SUM(total_cents) AS rev
  FROM orders WHERE status = 'completed' GROUP BY ym)
SELECT a.ym, ROUND(a.rev/100, 2) AS rev,
       ROUND((a.rev - b.rev) / b.rev * 100, 1) AS mom_pct
FROM monthly a
LEFT JOIN monthly b ON b.ym = PERIOD_ADD(a.ym, -1)
ORDER BY a.ym;
