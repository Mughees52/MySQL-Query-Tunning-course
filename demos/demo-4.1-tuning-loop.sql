-- ============================================================================
-- LIVE DEMO SCRIPT · video 16 · lesson 4.1 — The tuning loop
-- Deck: chapter4 slides 2–3
-- STATE REQUIRED: canonical ch-3 end state. CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 3] a big plan to practice on — run, then find the expensive node
-- expect total ~1.35 s
EXPLAIN ANALYZE
SELECT c.city, ROUND(SUM(o.total_cents)/100, 2) AS rev
FROM orders o JOIN customers c ON c.id = o.customer_id
WHERE o.status = 'completed'
GROUP BY c.city ORDER BY rev DESC LIMIT 10;

-- STEP 2 · narrate the arithmetic on camera:
--   Sort node: 30 rows — innocent, despite the scary name.
--   PK lookup on c: 0.7 µs x 1.03M loops ≈ 0.7 s  <- THE bill. time x loops.
