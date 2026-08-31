-- ============================================================================
-- LIVE DEMO SCRIPT · video 10 · lesson 2.4 — Composite indexes & leftmost prefix
-- Deck: chapter2 slides 4–5
-- STATE REQUIRED: idx_customers_email exists (lab 2.2 done). CREATES: idx_orders_customer + idx_orders_customer_date — SKIP the matching CREATEs when replaying lab 2.5.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · the single-column index first (the "before" of the race)
CREATE INDEX idx_orders_customer ON orders(customer_id);   -- ~2 s, narrate while it builds

-- STEP 2 · newest-5 orders — watch the Sort node fetch all 243 to keep 5
-- expect: Limit <- Sort (order_date DESC) <- Index lookup rows=243 · ~1.7 ms
EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5;

-- STEP 3 · [SLIDE 4] the composite — sorted by customer, then date DESC within
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date DESC);

-- STEP 4 · same query — Sort node GONE, reads exactly 5 entries · ~0.07 ms
EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5;

-- STEP 5 · [SLIDE 4, continued] the leftmost-prefix rule, violated live
-- expect: type=index — a full 1.2M-entry scan, no seek (date alone has no prefix)
EXPLAIN SELECT id FROM orders WHERE order_date > '2025-08-01';
