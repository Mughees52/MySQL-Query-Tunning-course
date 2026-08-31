-- ============================================================================
-- LIVE DEMO SCRIPT · video 6 · lesson 1.4 — Your first EXPLAIN
-- Deck: chapter1 slides 4–5
-- STATE: PK-only (pre-index). CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · the query support complains about — run it, feel the ~45 ms
-- expect: 1 row
SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';

-- STEP 2 · x-ray it, then talk over [SLIDE 4] column by column
-- expect: type=ALL · key=NULL · rows≈298422 · filtered=10.00 · Using where
EXPLAIN SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';

-- STEP 3 · the habit: SHOW WARNINGS right after any EXPLAIN
-- expect: Note 1003 — the query as the optimizer rewrote it (expanded names)
SHOW WARNINGS;

-- STEP 4 · [SLIDE 5] the ladder's other end — a PK lookup for contrast
-- expect: type=const, rows=1
EXPLAIN SELECT id, status FROM orders WHERE id = 4242;
