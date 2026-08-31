-- ============================================================================
-- LIVE DEMO SCRIPT · video 17 · lesson 4.4 — Hints, histograms, pagination
-- Deck: chapter4 slide 4
-- STATE REQUIRED: canonical ch-3 end state. CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 4] the OFFSET treadmill — page 50,001 · walks 1,000,020 entries
-- expect ~67 ms, growing linearly with depth
EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
ORDER BY id LIMIT 20 OFFSET 1000000;

-- STEP 2 · keyset — seek straight to where the last page ended
-- expect ~0.045 ms · 1,500x · constant at ANY depth
EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE id > 1000000 ORDER BY id LIMIT 20;

-- STEP 3 · hints recap — you already used the honest kind twice:
--   IGNORE INDEX (idx_orders_status)   431 -> 139 ms   (2.12)
--   IGNORE INDEX (PRIMARY)             1.74 -> 0.74 s  (3.9)
-- Say the rule: a hint is a dated, measured bet — comment the benchmark next to it.
