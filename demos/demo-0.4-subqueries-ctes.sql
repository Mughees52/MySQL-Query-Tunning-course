-- ============================================================================
-- LIVE DEMO SCRIPT · video 3 · lesson 0.4 — Subqueries and CTEs
-- Deck: chapter0 slides 8–9
-- STATE: fresh seed, PK-only. CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 8, card 1] subquery in SELECT — then EXPLAIN: "run only once"
SELECT ship_country,
       ROUND(AVG(total_cents)/100, 2) AS country_avg,
       (SELECT ROUND(AVG(total_cents)/100, 2) FROM orders) AS global_avg
FROM orders
GROUP BY ship_country
LIMIT 6;

-- STEP 2 · prove it runs once, not per row — read the tree
-- expect plan line: "Select #2 (subquery in projection; run only once)"
EXPLAIN FORMAT=TREE
SELECT ship_country, AVG(total_cents),
       (SELECT AVG(total_cents) FROM orders)
FROM orders GROUP BY ship_country;

-- STEP 3 · [SLIDE 8, card 2] subquery in WHERE — a threshold computed at run time
-- expect: 543009
SELECT COUNT(*) FROM orders
WHERE total_cents > (SELECT AVG(total_cents) FROM orders);

-- STEP 4 · [SLIDE 9] the CTE — read it aloud top-to-bottom, then run (~0.5 s)
WITH country_rev AS (
  SELECT ship_country, COUNT(*) AS orders, SUM(total_cents) AS rev
  FROM orders WHERE status = 'completed'
  GROUP BY ship_country)
SELECT co.region, SUM(cr.orders) AS orders, ROUND(SUM(cr.rev)/100, 2) AS revenue
FROM country_rev cr
JOIN countries co ON co.country_code = cr.ship_country
GROUP BY co.region ORDER BY revenue DESC;
