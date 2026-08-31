-- ============================================================================
-- LIVE DEMO SCRIPT · video 7 · lesson 1.8 — Measuring honestly
-- Deck: chapter1 slides 6 and 8
-- STATE: PK-only. CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 6] forecast vs reality on one screen
-- expect: Filter (rows est≈29842, actual rows=1) over Table scan (rows=300000, ~37 ms)
EXPLAIN ANALYZE
SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';

-- STEP 2 · read it bottom-up on camera: scan produced 300k in ~37 ms,
-- filter kept 1. Point at est 29842 vs actual 1 — four orders of magnitude.

-- STEP 3 · [SLIDE 8] rule 1 demonstrated — run the same thing twice, times differ
-- (first run may be slower; the SECOND number is the one you write down)
SELECT COUNT(*) FROM orders WHERE ship_country = 'DE';
SELECT COUNT(*) FROM orders WHERE ship_country = 'DE';
