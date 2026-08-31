-- ============================================================================
-- LIVE DEMO SCRIPT · video 13 · lesson 3.4 — Filter shapes
-- Deck: chapter3 slides 3–4
-- STATE REQUIRED: canonical ch-2 end state. CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 3] IN = native index shape · 3 range seeks · ~0.06 ms
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE customer_id IN (137, 42007, 250999);

-- STEP 2 · OR across two DIFFERENT columns — both indexed, plan dies anyway
-- expect: covering index SCAN of 1.2M entries · ~90 ms
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE customer_id = 137 OR id = 500000;

-- STEP 3 · the mechanical rewrite — UNION of two seeks · ~0.14 ms · 650x
EXPLAIN ANALYZE
SELECT COUNT(*) FROM (
  SELECT id FROM orders WHERE customer_id = 137
  UNION
  SELECT id FROM orders WHERE id = 500000) u;

-- STEP 4 · one unindexed arm poisons everything · full scan · ~81 ms
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders
WHERE customer_id = 137 OR coupon_code = 'SAVE7';

-- STEP 5 · [SLIDE 4] the NOT IN null bomb — run the naive version, get NOTHING
-- expect: Empty set. No error. (The right answer is 15 rows.)
SELECT DISTINCT coupon_code FROM orders
WHERE coupon_code IS NOT NULL
  AND coupon_code NOT IN (SELECT coupon_code FROM orders
                          WHERE status = 'cancelled'
                            AND order_date >= '2025-06-15' AND order_date < '2025-06-16');

-- STEP 6 · NOT EXISTS — immune by design · 15 rows appear
SELECT DISTINCT o.coupon_code FROM orders o
WHERE o.coupon_code IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM orders c
                  WHERE c.status = 'cancelled'
                    AND c.order_date >= '2025-06-15' AND c.order_date < '2025-06-16'
                    AND c.coupon_code = o.coupon_code);
