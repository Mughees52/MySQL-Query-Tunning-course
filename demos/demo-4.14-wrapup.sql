-- ============================================================================
-- LIVE DEMO SCRIPT · video 19 · lesson 4.14 — Wrap-up & checklist
-- Deck: chapter4 slides 6–7
-- STATE REQUIRED: capstone replayed (canonical ch-4 end state, idx_items_order exists). CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · the victory lap — re-run the course's first villain, now 9 µs
EXPLAIN ANALYZE
SELECT id, full_name, city FROM customers
WHERE email = 'amara.dubois150000@example.com';

-- STEP 2 · customer history — 110 ms then, 0.4 ms now
EXPLAIN ANALYZE
SELECT id, status, order_date, total_cents FROM orders WHERE customer_id = 137;

-- STEP 3 · [SLIDE 6] say the scorecard over the stopcard slide:
--   45 ms -> 9 µs · 110 ms -> 0.4 ms · 4 s -> 1.47 s · killed@21min -> 1.14 s
-- Then [SLIDE 7] the checklist, one press per block. End of course.
