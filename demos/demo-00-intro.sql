-- ============================================================================
-- LIVE DEMO SCRIPT · video 1 · lesson 0.0 — Why this course exists
-- Deck: intro-slides.html (all 7 slides)
-- STATE: fresh seed, PK-only. CREATES: nothing.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- This video is deck-driven; the terminal appears once, at slide 6.

-- STEP 1 · [SLIDE 6] the sanity check — prove the environment is real
-- expect: 1200000
SELECT COUNT(*) FROM orders;

-- STEP 2 · (optional flourish) the size of the patient
-- expect: ~350 MB total, orders ~77 MB
SELECT table_name, ROUND((data_length+index_length)/1024/1024, 1) AS mb
FROM information_schema.tables WHERE table_schema = 'urbancart'
ORDER BY mb DESC;
