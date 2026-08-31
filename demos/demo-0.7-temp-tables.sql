-- ============================================================================
-- LIVE DEMO SCRIPT · video 4 · lesson 0.7 — Temporary tables
-- Deck: chapter0 slides 10–11
-- STATE: fresh seed, PK-only. CREATES: session temp table only (vanishes on quit).
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 10] the report against the base table — feel the 659 ms
SELECT status, COUNT(*), ROUND(AVG(total_cents)/100, 2)
FROM orders WHERE ship_country = 'DE'
GROUP BY status;

-- STEP 2 · materialize the slice (expect ~0.33 s, 119,605 rows), then the habit
CREATE TEMPORARY TABLE tmp_de AS
SELECT id, customer_id, status, order_date, total_cents
FROM orders WHERE ship_country = 'DE';

ANALYZE TABLE tmp_de;

-- STEP 3 · same report on the temp table — expect ~27 ms (≈24x)
SELECT status, COUNT(*), ROUND(AVG(total_cents)/100, 2)
FROM tmp_de
GROUP BY status;

-- STEP 4 · [SLIDE 11] the reopen landmine — let it ERROR on camera
-- expect: ERROR 1137 (HY000): Can't reopen table: 'a'
SELECT COUNT(*) FROM tmp_de a JOIN tmp_de b ON b.customer_id = a.customer_id;
