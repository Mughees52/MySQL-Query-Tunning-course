-- ============================================================================
-- Advanced scenarios — solutions, with measured output (MySQL 8.4, 1G pool).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- A. The 10,000-arm OR-chain
-- ---------------------------------------------------------------------------
-- Shapes (generated; see scenarios.md for the generator):
--   1) WHERE (order_id=? AND product_id=?) OR ... x10000
--   2) WHERE (order_id, product_id) IN ((?,?), ...) x10000
--   3) CREATE TEMPORARY TABLE wanted(order_id, product_id, PRIMARY KEY(...));
--      INSERT 10000 rows; JOIN order_items USING both columns.
-- Measured (identical results: c=10000, s=301015466):
--   OR-chain 1,000 arms:    ~70 ms
--   OR-chain 10,000 arms:   ~11 s      <- superlinear: planning + 10k-arm filter
--   row-constructor IN:     ~80 ms     (140x)
--   temp-table join:        ~76 ms
--   OR-chain, range_optimizer_max_mem_size=1MB:
--                           killed after 5 min, still running.
--     The range optimizer overflowed its memory cap, silently abandoned
--     range access, and fell back to: full scan x 10,000 OR evaluations
--     per row. This is the "only sometimes" production timeout.
-- Escape hatch you practiced in the capstone:
--   SHOW PROCESSLIST;  KILL <id>;
-- Fixes: ORM emits row-constructor IN, or chunks 500-1,000 per statement;
-- temp-table join for the biggest batches.

-- ---------------------------------------------------------------------------
-- B. The typed pointer
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT id, action, actor, created_at
FROM activity WHERE entity_type='order' AND entity_id=4242;
-- before: -> Filter (...) -> Table scan on activity (rows=1.5e6)
--         actual ~180 ms for 2 rows.

CREATE INDEX idx_activity_entity ON activity(entity_type, entity_id);
-- after:  -> Index lookup (entity_type='order', entity_id=4242)
--         actual 0.01 ms. 18,000x.
-- Column order: entity_type is ALWAYS equality -> it leads (2.6). It also
-- makes one index serve per-type scans (leftmost prefix).

-- The type-pin trap:
SELECT COUNT(*) FROM activity a
JOIN orders o ON a.entity_type='order' AND a.entity_id=o.id
WHERE o.order_date >= '2025-08-20';                        -- 7,819  (correct)
SELECT COUNT(*) FROM activity a
JOIN orders o ON a.entity_id=o.id
WHERE o.order_date >= '2025-08-20';                        -- 12,462 (WRONG)
-- 4,643 phantom rows: customer/payment activities whose entity_id collides
-- with an order id. No error. Plausible totals. Every join/WHERE on a typed
-- pointer must pin the type.

-- ---------------------------------------------------------------------------
-- C. The outbox poller
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT id, aggregate, aggregate_id, event_type, payload
FROM outbox WHERE status='PENDING' ORDER BY id LIMIT 100;
-- before:
--   -> Limit: 100  (cost=9.16 rows=10) (actual time=188..188)
--       -> Filter: status='PENDING'
--           -> Index scan on PRIMARY (actual .. rows=1.7e6)   <- ALL history
-- 188 ms per poll, every 5 s. The optimizer priced it at cost≈9: it assumed
-- PENDING is uniformly spread, so "the first 100 will turn up quickly".
-- Reality: PENDING lives at the very end of the id order. Skew blindness.

CREATE INDEX idx_outbox_status ON outbox(status, id);
-- after: -> Index lookup (status='PENDING') (actual 0.05..0.099 rows=100)
-- 0.099 ms, no Sort node: within one status value the secondary index is
-- already ordered by its PK suffix -> ORDER BY id LIMIT is a pure prefix read.

EXPLAIN ANALYZE SELECT id, event_type, created_at
FROM outbox WHERE status='FAILED' ORDER BY id LIMIT 200;
-- 0.3 ms per sweep — but 9,466 FAILED rows re-swept every 5 s forever is
-- ~163M wasted row-touches/day, plus whatever the retry side effects cost.
-- Query tuning cannot fix a missing state machine:
--   * FAILED_PERMANENT after N attempts (stop retrying)
--   * archive table for terminal rows; batch-purge SENT on retention
--   * the hot set then stays small enough that even mediocre plans are fine.

-- ---------------------------------------------------------------------------
-- D. The retention purge (DESTRUCTIVE — restore with setup_advanced.sql)
-- ---------------------------------------------------------------------------
SELECT COUNT(*) FROM outbox WHERE created_at < '2024-03-01';   -- 749,387
-- Terminal A:
--   START TRANSACTION;
--   DELETE FROM outbox WHERE created_at < '2024-03-01';   -- measured: 1.6 s
--   SELECT SLEEP(25);  ROLLBACK;                          -- rollback: 1.2 s
-- Terminal B, during the window:
SELECT trx_rows_locked, trx_rows_modified FROM information_schema.innodb_trx;
--   trx_rows_locked = 1,710,969  <- the WHOLE 1.7M-row table.
--   Unindexed DELETE under REPEATABLE READ locks every row it scans.
SET SESSION innodb_lock_wait_timeout = 2;
INSERT INTO outbox (aggregate, aggregate_id, event_type, status, payload, created_at)
VALUES ('order', 999999, 'order.created', 'PENDING', '{"v":1}', NOW());
--   ERROR 1205 (HY000): Lock wait timeout exceeded  <- writes are frozen.
-- The fix (each statement autocommits -> locks released per batch):
--   loop:  DELETE FROM outbox WHERE created_at < '2024-03-01' LIMIT 50000;
-- Measured: 16 batches, 3.7 s total, mid-loop INSERT succeeds instantly.
-- Production extras: PK-ordered batches, inter-batch sleep for replicas,
-- archive-then-delete in the same loop.

-- ---------------------------------------------------------------------------
-- E. Big-O for SQL — scale tables
-- ---------------------------------------------------------------------------
CREATE TABLE t10k  AS SELECT id, customer_id, status, order_date, total_cents FROM orders WHERE id <= 10000;
CREATE TABLE t100k AS SELECT id, customer_id, status, order_date, total_cents FROM orders WHERE id <= 100000;
CREATE TABLE t1m   AS SELECT id, customer_id, status, order_date, total_cents FROM orders WHERE id <= 1000000;
ALTER TABLE t10k ADD PRIMARY KEY (id);
ALTER TABLE t100k ADD PRIMARY KEY (id);
ALTER TABLE t1m ADD PRIMARY KEY (id);
CREATE TABLE t5k AS SELECT * FROM t10k WHERE id <= 5000;
ANALYZE TABLE t5k, t10k, t100k, t1m;

-- Measured (EXPLAIN ANALYZE actuals):
--   PK lookup:      t10k 0.002 ms | t100k 0.0001 ms | t1m 0.0002 ms  = flat
--   full-scan SUM:  t10k 0.72 ms  | t100k 8.0 ms    | t1m 80 ms     = O(n)
--   top-10 sort:    t10k 0.75 ms  | t100k 6.9 ms    | t1m 69 ms     = O(n log k)
--   equi hash join (customer_id):     5k 1.3 ms  -> 10k 2.7 ms      = O(n+m)
--   non-equi join (total_cents >):    5k 1,007 ms -> 10k 3,968 ms   = O(n*m)
--     plan: Inner hash join (NO CONDITION) -> n^2 rows -> Filter.
--     Same size, 770x apart: equality is what makes joins linear.
DROP TABLE t5k, t10k, t100k, t1m;
