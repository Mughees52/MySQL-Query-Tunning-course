-- ============================================================================
-- LIVE DEMO SCRIPT · video 14 · lesson 3.8 — Nested loops and hash joins
-- Deck: chapter3 slides 5–6
-- STATE REQUIRED: canonical ch-2 end state. CREATES: idx_payments_order (canonical ch-3 addition) — SKIP the CREATE when replaying lab 3.9.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 5] the optimizer's pick: nested loop, 3M PK descents · ~1.74 s
EXPLAIN ANALYZE
SELECT p.category, ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS rev
FROM order_items oi JOIN products p ON p.id = oi.product_id
GROUP BY p.category;

-- STEP 2 · forced hash join — build on 5k, probe with one 3M scan · ~0.74 s · 2.4x
EXPLAIN ANALYZE
SELECT p.category, ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS rev
FROM order_items oi JOIN products p IGNORE INDEX (PRIMARY) ON p.id = oi.product_id
GROUP BY p.category;

-- STEP 3 · the everyday case — unindexed join key drives from the WRONG side
-- expect: probes from all 1.07M payments · ~541 ms
EXPLAIN ANALYZE
SELECT COUNT(*), ROUND(SUM(p.amount_cents)/100,2)
FROM orders o JOIN payments p ON p.order_id = o.id
WHERE o.order_date >= '2025-08-20';

-- STEP 4 · index the join key — now drives from 10k recent orders · ~25 ms
CREATE INDEX idx_payments_order ON payments(order_id);
EXPLAIN ANALYZE
SELECT COUNT(*), ROUND(SUM(p.amount_cents)/100,2)
FROM orders o JOIN payments p ON p.order_id = o.id
WHERE o.order_date >= '2025-08-20';

-- STEP 5 · [SLIDE 6] ON vs WHERE on a LEFT join — 8,550 rows vs 1,553, silently
SELECT COUNT(*) FROM orders o
LEFT JOIN payments p ON p.order_id = o.id AND p.method = 'klarna'
WHERE o.order_date >= '2025-08-01' AND o.order_date < '2025-08-08';
SELECT COUNT(*) FROM orders o
LEFT JOIN payments p ON p.order_id = o.id
WHERE o.order_date >= '2025-08-01' AND o.order_date < '2025-08-08'
  AND p.method = 'klarna';
