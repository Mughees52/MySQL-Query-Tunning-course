-- ============================================================================
-- LIVE DEMO SCRIPT · video 5 · lesson 1.1 — Welcome to UrbanCart
-- Deck: chapter1 slides 1–3
-- STATE: fresh seed, PK-only. CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- This video is deck-driven (schema → lifecycle → tree vs sweep).
-- Optional terminal beat after [SLIDE 3], "let's meet the patient":

-- STEP 1 · six tables, and how much of them
-- expect: orders ~1.2M rows / ~77 MB, total ~350 MB
SELECT table_name, table_rows,
       ROUND((data_length+index_length)/1024/1024, 1) AS mb
FROM information_schema.tables
WHERE table_schema = 'urbancart' ORDER BY mb DESC;

-- STEP 2 · the punchline for the chapter — zero secondary indexes
-- expect: every table shows PRIMARY only
SELECT table_name, index_name FROM information_schema.statistics
WHERE table_schema = 'urbancart' GROUP BY table_name, index_name;
