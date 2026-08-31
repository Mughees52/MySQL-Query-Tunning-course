-- ============================================================================
-- LIVE DEMO SCRIPT · video 2 · lesson 0.1 — All about joins, MySQL edition
-- Deck: chapter0 slides 1–7
-- STATE: fresh seed, PK-only. CREATES: nothing. All demos read-only.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 2] how MySQL reads a SELECT — run the pipeline query
-- expect: 3 rows — US 309,882 · GB 154,855 · DE 102,838
SELECT ship_country, COUNT(*) AS orders
FROM orders
WHERE status = 'completed'
GROUP BY ship_country
HAVING COUNT(*) > 50000
ORDER BY orders DESC
LIMIT 3;

-- STEP 2 · the proof of execution order — alias in WHERE fails, in ORDER BY works
-- expect: ERROR 1054 (42S22): Unknown column 'orders' in 'where clause'
SELECT ship_country, COUNT(*) AS orders
FROM orders
WHERE orders > 50000
GROUP BY ship_country;

-- STEP 3 · [SLIDE 3] a query inside a query — uncorrelated runs ONCE
-- expect: avg 743.82 · then 543,009 orders above it · plan prints "run only once"
SELECT ROUND(AVG(total_cents)/100, 2) AS avg_order_value FROM orders;
SELECT COUNT(*) FROM orders
WHERE total_cents > (SELECT AVG(total_cents) FROM orders);
EXPLAIN FORMAT=TREE
SELECT COUNT(*) FROM orders
WHERE total_cents > (SELECT AVG(total_cents) FROM orders);
-- (do NOT run the correlated MAX example live in chapter-0 state — no index
--  yet, 300k probes would each scan the table. That is exactly the point;
--  it gets its measured 320 ms moment in lab 3.13, on chapter-2's index.)

-- STEP 4 · [SLIDE 5] INNER JOIN — run it, point at the reunited columns
SELECT c.full_name, c.country_code, co.country_name, co.region
FROM customers c
INNER JOIN countries co ON co.country_code = c.country_code
LIMIT 5;

-- STEP 5 · [SLIDE 6] LEFT JOIN — the NULL is an answer, not dirty data
-- expect: Argentina/Belgium/Greece/Pakistan/Saudi Arabia rows show NULL customer
SELECT co.country_name, c.full_name
FROM countries co
LEFT JOIN customers c ON c.country_code = co.country_code
ORDER BY c.full_name IS NULL DESC, co.country_name
LIMIT 8;

-- STEP 6 · [SLIDE 6] the row arithmetic — say the numbers BEFORE you run
-- expect: 1200000, then 1208266 (the +8,266 never-ordered customers)
SELECT COUNT(*) FROM customers c INNER JOIN orders o ON o.customer_id = c.id;
SELECT COUNT(*) FROM customers c LEFT  JOIN orders o ON o.customer_id = c.id;

-- STEP 7 · [SLIDE 7] the FULL OUTER JOIN MySQL doesn't have — emulated
-- expect: 32 rows (17 matched + 15 lookup-only + 0 ship-only)
WITH ship_stats AS (
  SELECT ship_country, COUNT(*) AS orders FROM orders GROUP BY ship_country)
SELECT co.country_code, co.country_name, s.ship_country, s.orders
FROM countries co LEFT JOIN ship_stats s ON s.ship_country = co.country_code
UNION ALL
SELECT NULL, NULL, s.ship_country, s.orders
FROM ship_stats s LEFT JOIN countries co ON co.country_code = s.ship_country
WHERE co.country_code IS NULL;
