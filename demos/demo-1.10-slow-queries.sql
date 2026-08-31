-- ============================================================================
-- LIVE DEMO SCRIPT · video 8 · lesson 1.10 — Finding the slow queries
-- Deck: chapter1 slide 7
-- STATE: PK-only. CREATES: nothing. NOTE: sys numbers reflect whatever ran this session — warm-up populates them.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · the slow log is on in this container
-- expect: slow_query_log=ON, long_query_time=0.5
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';

-- STEP 2 · [SLIDE 7] the live dashboard — top offenders by average latency
-- expect: your recent demo queries, normalized with ?, avg_s + rows_examined_avg
SELECT query, exec_count,
       ROUND(avg_latency/1e12, 2) AS avg_s,
       rows_examined_avg
FROM sys.x$statement_analysis
WHERE db = 'urbancart'
ORDER BY avg_latency DESC
LIMIT 5;

-- STEP 3 · say the smell out loud: rows examined >> rows sent = index hiding
