-- ============================================================================
-- Chapter 4 — solutions, with measured output (MySQL 8.4, 1G buffer pool).
-- Capstone measurements: see capstone/walkthrough.md for full plans.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 4.2 Reading a big plan
-- ---------------------------------------------------------------------------
EXPLAIN
SELECT c.city, ROUND(SUM(o.total_cents)/100, 2) AS rev
FROM orders o JOIN customers c ON c.id = o.customer_id
WHERE o.status = 'completed'
GROUP BY c.city ORDER BY rev DESC LIMIT 10;
-- orders: type=ref key=idx_orders_status rows=597313
--         Extra: Using temporary; Using filesort
-- customers: eq_ref PRIMARY

EXPLAIN ANALYZE ...;   -- same query
-- -> Limit: 10                                (actual time=1348..1348)
--   -> Sort: rev DESC, limit 10               (actual time=1348..1348 rows=10)
--     -> Table scan on <temporary>            (rows=30)
--       -> Aggregate using temporary table    (actual time=1345 rows=30)
--         -> Nested loop inner join           (actual ..1214 rows=1.03e6)
--           -> Index lookup idx_orders_status (actual ..436 rows=1.03e6)
--           -> Single-row PK lookup on c      (0.7 µs x 1.03e6 loops ≈ 0.7 s)
-- Expensive node: the JOIN (~1.2 s of the 1.35 s) — NOT the scary-sounding
-- Sort, which handles 30 rows. time x loops, then judge.

-- ---------------------------------------------------------------------------
-- 4.3 Using temporary, Using filesort
-- ---------------------------------------------------------------------------
-- (a) GROUP BY c.city: no index delivers rows in city order (city lives in
--     customers, reached per-order), so MySQL buckets into a temp table.
-- (b) ORDER BY c.city: the flag pair remains — grouping still needs the
--     temp table; only the final sort key changed (30 rows either way).
-- bonus: IGNORE INDEX (idx_orders_status) -> driving read 436 ms -> ~140 ms
--     (chapter 2's skew lesson, third appearance; total ~1.35 s -> ~1.05 s).

-- ---------------------------------------------------------------------------
-- 4.5 Deep pagination
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT id, order_date, total_cents FROM orders
ORDER BY id LIMIT 20 OFFSET 1000000;
-- -> Limit/Offset: 20/1000000  (actual time=67.1 rows=20)
--     -> Index scan on PRIMARY (actual .. rows=1e6)     <- walked 1,000,020
-- 67 ms, linear in depth.

EXPLAIN ANALYZE SELECT id, order_date, total_cents FROM orders
WHERE id > 1000000 ORDER BY id LIMIT 20;
-- -> Limit: 20 -> Index RANGE scan over (1000000 < id) (actual time=0.045)
-- 0.045 ms, constant at any depth. 1500x. Keyset pagination: the client
-- passes the last id it saw; works for any unique ordered key.

-- ---------------------------------------------------------------------------
-- 4.8–4.13 Capstone — summary (full journey: capstone/walkthrough.md)
-- ---------------------------------------------------------------------------
-- v0  baseline                                   killed at 21 min
-- v1  sargable dates                             still > 10 min (capped);
--                                                plan improved, not sufficient
-- v2  + idx_items_order                          8.85 s  <- first finish; oracle
-- v3  correlated top-category -> one-pass CTE    1.64 s
-- v4  NOT IN -> NOT EXISTS                       1.64 s  (identical plan:
--                                                order_id is NOT NULL; kept
--                                                as NULL-safety insurance)
-- v5  order-grain outer (items join deleted)     1.34 s
-- v6  agg-before-join + IGNORE INDEX polish      1.14 s  <- ship it (< 2 s req)
-- Identity verified with diff at every step from v2 on; 17 rows each time.

-- ---------------------------------------------------------------------------
-- 4.15 Deep dive: cost anatomy + index census
-- ---------------------------------------------------------------------------
EXPLAIN FORMAT=JSON
SELECT SUM(total_cents) FROM orders
WHERE order_date >= '2025-08-01' AND status = 'completed';
-- Measured (course container):
--   "query_cost": "14324.96"
--   access_type: range on idx_orders_date_status_total, using_index: true
--   "rows_examined_per_scan": 67408, "rows_produced_per_join": 33703
--   "read_cost": "10954.56", "eval_cost": "3370.40"
-- read_cost ~76% of total: the budget is fetching entries, not evaluating
-- them -> covering + tighter ranges beat micro-optimizing expressions.

SELECT object_name, index_name
FROM sys.schema_unused_indexes WHERE object_schema = 'urbancart';
-- Fresh after restart this listed idx_customers_email and
-- idx_payments_provider_ref; one real SELECT through each and they left
-- the list. Counters live in performance_schema (reset at restart):
-- evidence over a representative window, then invisible -> verify -> drop.

-- ---------------------------------------------------------------------------
-- 4.16 The dialect card + sort spill
-- ---------------------------------------------------------------------------
-- PostgreSQL            -> MySQL
--   pg_class stats      -> information_schema.TABLES, SHOW INDEX,
--                          mysql.innodb_index_stats (sizes; 2.16)
--   pg_stats            -> information_schema.COLUMN_STATISTICS (histograms,
--                          2.13); no null_frac/avg_width catalog exists
--   EXPLAIN VERBOSE     -> EXPLAIN FORMAT=JSON ("used_columns")
--   cost=startup..total -> JSON cost_info: read_cost + eval_cost (4.15)
--   Planning/Execution  -> TREE prints neither; optimizer trace (1.14) shows
--                          planning work — scenario A: 11 s mostly planning
--   Sort Method/Memory  -> never printed; watch the counter instead:
SET SESSION sort_buffer_size = 32768;
SELECT COUNT(*) FROM (SELECT id FROM orders
  IGNORE INDEX (idx_orders_customer_date, idx_orders_date_status_total, idx_orders_status)
  ORDER BY total_cents DESC LIMIT 1000000) t;
SHOW SESSION STATUS LIKE 'Sort_merge_passes';   -- 0 -> 195: spilled to disk
SET SESSION sort_buffer_size = 268435456;
-- same sort again -> Sort_merge_passes unchanged (fit in memory).
SET SESSION sort_buffer_size = DEFAULT;         -- default: 256 KB
-- Note: ORDER BY ... LIMIT 5 shows 0 passes even with a tiny buffer — the
-- top-N heap (3.1) never performs a full sort. LIMIT size changes the
-- ALGORITHM, not just the output.
