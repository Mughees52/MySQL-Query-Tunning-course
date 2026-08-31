# Recording guide — how to film this course

The unit of recording is **one lesson = one video (~5–7 min)**. Learners do
the labs on their own between videos, so you only film the ▶ lessons:
**19 videos total** (intro + 18 lessons). Each `transcript.md` is the literal
narration script, with `[SLIDE N]` cues telling you when to advance the deck
and where live terminal demos happen.

## The two scenes

Every video alternates between two screens:

1. **Deck** — `slides/*.html` fullscreen in a browser (16:9 window,
   presentation mode). Decks are presenter-paced: nothing animates until you
   press **→**, so narrate first, press when you reach the thing you're about
   to show. The HUD reads `slide · build j/m` so you always know what's left.
   **←** undoes a mis-press; **Home** restarts the slide clean. Be online so
   IBM Plex loads from Google Fonts (system fallbacks otherwise).
2. **Terminal** — the course container, big font, for every demo the
   transcript shows measured output for:
   ```bash
   docker exec -it mysql-tuning-course mysql -uroot -pcourse urbancart
   ```

Switch scenes exactly where the transcript switches: prose + `[SLIDE N]` cue
→ deck; a SQL block with measured output → terminal.

## Live demos: the snippets are pre-written — never type SQL on camera

`demos/` holds **one runnable script per video** (`demo-2.8-five-traps.sql`
etc.), with every statement extracted from the transcripts and verified
against the live container. Each file has:

- a header stating the **DB state it requires**, what it **CREATEs**, and
  which lab CREATEs to skip afterwards so nothing collides;
- numbered `STEP` blocks in narration order, tagged with their `[SLIDE]`
  cue and the **expected output/timing** so you can sanity-check live;
- deliberate on-camera failures (error 1137, error 1054, the NOT IN empty
  set, the implicit-cast warning) marked as such — let them error; that's
  the beat.

Workflow: keep the demo file open in an editor beside the terminal.
**Run the whole file once off-camera first** (warms the cache and verifies
your numbers). On camera: copy ONE step, paste, run, then explain what
appeared — improvement queries are run live, but never composed live.
The rhythm per demo is always: run the slow thing → feel it → EXPLAIN it →
apply the one fix → run again → point at the delta.

## The shot list (19 videos)

| # | Video | Deck · slides | Learners then do |
|---|---|---|---|
| 1 | Intro 0.0 | intro-slides.html · 1–7 | run `setup/setup.sh`, connect |
| 2 | 0.1 Joins | chapter0 · 1–7 | 0.2–0.3 |
| 3 | 0.4 Subqueries & CTEs | chapter0 · 8–9 | 0.5–0.6 |
| 4 | 0.7 Temp tables | chapter0 · 10–11 | 0.8–0.9 |
| 5 | 1.1 Journey of a query | chapter1 · 1–3 | 1.2–1.3 |
| 6 | 1.4 Your first EXPLAIN | chapter1 · 4–5 | 1.5–1.7 |
| 7 | 1.8 Measuring honestly | chapter1 · 6, 8 | 1.9 |
| 8 | 1.10 Slow queries in prod | chapter1 · 7 | 1.11–1.13, ⚙1.14 |
| 9 | 2.1 Inside InnoDB | chapter2 · 1–3 | 2.2–2.3 |
| 10 | 2.4 Composite indexes | chapter2 · 4–5 | 2.5–2.7 |
| 11 | 2.8 Five ways to lose an index | chapter2 · 6–8 | 2.9–2.14, ⚙2.15–2.16 |
| 12 | 3.1 Logical order | chapter3 · 1–2 | 3.2–3.3 |
| 13 | 3.4 Filter shapes | chapter3 · 3–4 | 3.5–3.7 |
| 14 | 3.8 Joins under the hood | chapter3 · 5–6 | 3.9–3.10 |
| 15 | 3.11 Merge or materialize | chapter3 · 7–8 | 3.12–3.14, 3.17, ⚙3.15–3.16 |
| 16 | 4.1 The tuning loop | chapter4 · 2–3 | 4.2–4.3 |
| 17 | 4.4 Hints, histograms, pagination | chapter4 · 4 | 4.5–4.6 |
| 18 | 4.7 Capstone briefing | chapter4 · 1 | capstone 4.8–4.13 (slide 5 is the journey they produce) |
| 19 | 4.14 Wrap-up & checklist | chapter4 · 6–7 | ⚙4.15, 4.16 |

Optional extra videos later: a capstone walkthrough narrated from
`capstone/walkthrough.md`, and one per advanced scenario (A–E).

## Database state — the one thing that will bite you

Lesson demos assume every earlier exercise has already happened (indexes are
created *in the labs*, and later lessons use them). Two rules:

- **Record in course order**, and between recording sessions run the
  intervening labs yourself — or replay the chapter's `solutions.sql` up to
  the exercise just before the lesson you're about to film.
- The canonical end-of-chapter index state is in
  `INSTRUCTOR_NOTES.md` — verify with `SHOW INDEX` before pressing record.
  `setup/reset_lab_indexes.sql` takes you back to the chapter-1 state from
  anywhere.

Mid-chapter examples: lesson 2.4's demos need `idx_customers_email` (lab
2.2); lesson 2.8's need the composite and covering indexes (labs 2.5, 2.7);
lesson 3.11 beats the monster using chapter-2's indexes plus
`idx_payments_order` (lab 3.9).

## Pre-record checklist (per video)

1. DB state = everything before this lesson has run (see above; the demo
   file's header names exactly what it requires).
2. **Warm the demos off-camera**: run the video's `demos/demo-*.sql` file
   top-to-bottom once. The printed numbers are warm-cache second runs — a
   cold buffer pool after a container restart will not match them.
3. Open the deck, press **Home** (fresh, nothing revealed).
4. Terminal cleared, font large, connected to `urbancart`.
5. Skim the lesson's traps in `INSTRUCTOR_NOTES.md` ("Gotchas" + trap table).

## While recording

- Narrate from the transcript; treat each **→** press as a beat, not a
  slideshow advance. Rule of thumb: say the sentence, *then* press — the
  build appears as its punchline. The step counts per slide are sized to the
  script's paragraphs.
- Your live numbers will differ ±50% from the printed ones. Say so once in
  the intro (the script already does) and never again — but the **ratios
  and plans must match**. If a plan differs, stop: your index state is wrong.
- Never compare an `EXPLAIN ANALYZE` time to a bare wall-clock time
  on camera (instrumentation adds ~10–15%).
- **Do not run capstone v0 live** (21 minutes). The briefing (video 18)
  shows the ticket; the kill itself is the learners' first capstone
  exercise, with `MAX_EXECUTION_TIME` — if you demo it, use the capped
  version and cut the wait.
- Scenario A's runaway is real — keep `SHOW PROCESSLIST` / `KILL` ready in a
  second terminal for any advanced-scenario recording.

## After each chapter

Your DB now sits at that chapter's canonical state — leave it: it's the
starting state the next chapter's recordings need. Only reset if you must
re-record an earlier lesson (reset, replay solutions up to that point).
