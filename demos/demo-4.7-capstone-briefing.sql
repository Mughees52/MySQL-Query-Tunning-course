-- ============================================================================
-- LIVE DEMO SCRIPT · video 18 · lesson 4.7 — Capstone briefing
-- Deck: chapter4 slide 1
-- STATE REQUIRED: canonical ch-3 end state. CREATES: nothing. Open capstone/dashboard_v0.sql in your editor for this video.
-- Warm-up: run this file top-to-bottom once OFF CAMERA before recording
-- (buffer pool warm + you verify your numbers land near the printed ones).
-- On camera: paste ONE step at a time. Run it. Then explain what appeared.
-- ============================================================================

-- STEP 1 · [SLIDE 1] read the ticket from the deck. Then show the beast's text:
-- scroll capstone/dashboard_v0.sql in the editor — point at the five sins.

-- STEP 2 · DO NOT run v0 bare (it needed a kill at 21 min). Demo the bounded run:
-- paste v0's SELECT with the hint added, like this pattern:
--   SELECT /*+ MAX_EXECUTION_TIME(60000) */ ...rest of v0...
-- expect after 60 s: ERROR 3024 (HY000): Query execution was interrupted,
-- maximum statement execution time exceeded
-- That error IS the baseline measurement: "killed at N minutes" goes on the scorecard.

-- STEP 3 · if a runaway ever escapes on camera, show the professional recovery:
SHOW PROCESSLIST;
-- KILL <id>;   -- narrate it; run it only if something is actually stuck
