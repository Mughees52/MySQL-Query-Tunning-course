-- ============================================================================
-- LIVE DEMO SCRIPT · video 12 · lesson 3.1 — The logical order of operations
-- Deck: chapter3 slides 1–2
-- STATE REQUIRED: canonical ch-2 end state (covering index exists). CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · aliases don't exist yet in WHERE — let it fail on camera
-- expect: ERROR 1054 Unknown column 'revenue' in 'where clause'
SELECT ship_country, SUM(total_cents) AS revenue
FROM orders WHERE revenue > 100 GROUP BY ship_country;

-- STEP 2 · ...but ORDER BY sees it fine (runs after SELECT) — pipeline proven
SELECT ship_country, ROUND(SUM(total_cents)/100,2) AS revenue
FROM orders GROUP BY ship_country ORDER BY revenue DESC LIMIT 5;

-- STEP 3 · SELECT * vs projecting — the covering index only helps if you let it
-- expect: ~69 ms with *, ~2.9 ms with four columns · same 33,189 rows · 23x
EXPLAIN ANALYZE SELECT * FROM orders WHERE order_date >= '2025-08-01';
EXPLAIN ANALYZE SELECT id, order_date, status, total_cents
FROM orders WHERE order_date >= '2025-08-01';
