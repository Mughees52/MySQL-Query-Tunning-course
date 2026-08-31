-- ============================================================================
-- LIVE DEMO SCRIPT · video 2 · lesson 0.1 — All about joins, MySQL edition
-- Deck: chapter0 slides 1–5
-- STATE: fresh seed, PK-only. CREATES: nothing. All demos read-only.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 3] INNER JOIN — run it, point at the reunited columns
SELECT c.full_name, c.country_code, co.country_name, co.region
FROM customers c
INNER JOIN countries co ON co.country_code = c.country_code
LIMIT 5;

-- STEP 2 · [SLIDE 4] LEFT JOIN — the NULL is an answer, not dirty data
-- expect: Argentina/Belgium/Greece/Pakistan/Saudi Arabia rows show NULL customer
SELECT co.country_name, c.full_name
FROM countries co
LEFT JOIN customers c ON c.country_code = co.country_code
ORDER BY c.full_name IS NULL DESC, co.country_name
LIMIT 8;

-- STEP 3 · [SLIDE 4] the row arithmetic — say the numbers BEFORE you run
-- expect: 1200000, then 1208266 (the +8,266 never-ordered customers)
SELECT COUNT(*) FROM customers c INNER JOIN orders o ON o.customer_id = c.id;
SELECT COUNT(*) FROM customers c LEFT  JOIN orders o ON o.customer_id = c.id;

-- STEP 4 · [SLIDE 5] the FULL OUTER JOIN MySQL doesn't have — emulated
-- expect: 32 rows (17 matched + 15 lookup-only + 0 ship-only)
WITH ship_stats AS (
  SELECT ship_country, COUNT(*) AS orders FROM orders GROUP BY ship_country)
SELECT co.country_code, co.country_name, s.ship_country, s.orders
FROM countries co LEFT JOIN ship_stats s ON s.ship_country = co.country_code
UNION ALL
SELECT NULL, NULL, s.ship_country, s.orders
FROM ship_stats s LEFT JOIN countries co ON co.country_code = s.ship_country
WHERE co.country_code IS NULL;
