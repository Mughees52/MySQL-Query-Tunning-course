-- ============================================================================
-- LIVE DEMO SCRIPT · video 9 · lesson 2.1 — Inside InnoDB
-- Deck: chapter2 slides 1–3
-- STATE: PK-only (chapter-1 state). CREATES: nothing — building the index is lab 2.2, the learners' moment.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 1] re-run the pain so the promise lands — ~45 ms, 300k rows read
EXPLAIN ANALYZE
SELECT id, full_name, city FROM customers
WHERE email = 'amara.dubois150000@example.com';

-- STEP 2 · [after SLIDE 2] the clustered tree is real: PK lookup for contrast
-- expect: actual time ≈ 0.02 ms — the two-step dance's step two, on its own
EXPLAIN ANALYZE SELECT * FROM orders WHERE id = 4242;

-- STEP 3 · [BOARD: selectivity] cardinality at a glance — the number to judge by
-- expect: PRIMARY cardinality ≈ row count
SHOW INDEX FROM customers;
