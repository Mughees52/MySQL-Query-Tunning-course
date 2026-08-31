# Improving Query Performance in MySQL 8

A hands-on course that takes real queries from **seconds to milliseconds** on a
realistic 5.5-million-row e-commerce database. You will learn to read what
MySQL is actually doing, design indexes it will actually use, write SQL the
optimizer loves, and run a repeatable tuning workflow — ending with a capstone
where you rescue a production dashboard query step by step.

**Audience:** engineers and analysts comfortable with `SELECT`, `JOIN`, and
`GROUP BY` who want their queries to stop timing out.
**Length:** ~4–5 hours · 4 chapters + an optional foundations chapter · 18 lessons ·
54 exercises (incl. 4 concept checks and 6 advanced deep dives) · 1 capstone.

**Start here:** the course introduction —
[chapters/intro/transcript.md](chapters/intro/transcript.md) with its deck
[slides/intro-slides.html](slides/intro-slides.html) — sets the scene, the
method, and walks you through setup in ~5 minutes.
**MySQL:** 8.0.18+ (course verified on 8.4). Everything runs in Docker.

---

## The story

You just joined **UrbanCart**, an online retailer. The database has 300k
customers, 1.2M orders, ~3M order items and ~1M payments — and *not a single
secondary index*. Dashboards take seconds, the morning revenue report takes four, and every
single customer lookup burns 45 ms of CPU doing work an index would do in
microseconds — multiplied across every session, all day.

Over four chapters you will fix that — measuring every step, so you always
know whether you actually made things better. (Need the constructs first?
[Chapter 0](chapters/00-foundations-combining-data/transcript.md) teaches
joins, subqueries, CTEs and temp tables MySQL-style — including the missing
FULL OUTER JOIN and the temp-table reopen error — then hands you to ch. 1.)

## Course map

| Chapter | Title | You will learn |
|---|---|---|
| Intro | **Course Introduction** | The UrbanCart scene, the dataset and its planted traps, the five-chapter arc, the learn-then-do method, setup — start here |
| 0 *(optional)* | **Foundations: Combining Data** | Joins (INNER/LEFT, and the FULL OUTER JOIN MySQL doesn't have), subqueries in three positions, CTEs, temp tables and the reopen error — skip if fluent |
| 1 | **How MySQL Runs Your Query** | Query lifecycle, InnoDB clustered index, reading `EXPLAIN` and `EXPLAIN ANALYZE`, slow query log, sys schema, building a baseline scorecard |
| 2 | **Indexes That Actually Get Used** | Secondary indexes, selectivity, composite & covering indexes, leftmost-prefix rule, the five classic ways an index gets ignored, histograms, invisible indexes |
| 3 | **Writing SQL the Optimizer Loves** | Logical order of operations, filter shapes (OR/IN/UNION, EXISTS vs IN, NOT IN's NULL trap), join algorithms (nested loop vs hash join), aggregate-before-join, subqueries vs CTEs vs derived tables |
| 4 | **The Tuning Workflow: From Ticket to Fix** | A repeatable diagnose→fix→verify loop, reading big plans (`Using temporary`, filesort), optimizer hints, keyset pagination, and the capstone: a 6-step rescue of a slow executive dashboard |

After chapter 4, [advanced/scenarios.md](advanced/scenarios.md) holds five
**production-shaped scenarios** (extra 3.2M-row setup): the ORM that writes
10,000-arm WHERE clauses (11 s → 80 ms, plus the range-optimizer memory
cliff), the polymorphic typed pointer (18,000× index win + a silent
wrong-results join trap), the outbox poller that walks 2.6 years of
history every 5 seconds (188 ms → 0.1 ms), the retention purge that locks
all 1.7M rows in one transaction vs batched deletes, and Big-O for SQL —
measured growth curves from 10k to 1M rows (the non-equi join that is 770×
slower than its equi twin at the same size).

Full lesson-by-lesson syllabus: [OUTLINE.md](OUTLINE.md).
Instructor reference (planted traps, measured timings, reset procedure):
[INSTRUCTOR_NOTES.md](INSTRUCTOR_NOTES.md).
Recording the course? The shot list, per-video checklist, and ready-to-run
live-demo scripts: [RECORDING_GUIDE.md](RECORDING_GUIDE.md) + [demos/](demos/).
Test yourself after each chapter: [quiz/](quiz/) — 42 questions whose wrong
options are real misconceptions and whose answers you can verify on your own
container.

## Getting started

Requirements: Docker.

```bash
cd setup
./setup.sh
```

This starts a MySQL 8 container on port **3307** (so it won't collide with a
local MySQL) and seeds the dataset deterministically — you get byte-identical
data, so your numbers will be close to the ones printed in the
transcripts (hardware varies; ratios should match).

Connect:

```bash
docker exec -it mysql-tuning-course mysql -uroot -pcourse urbancart
```

## How to work through a chapter

Each `chapters/NN-*/` directory contains:

- `transcript.md` — the lesson scripts ("the video"): concepts + live demos
  with real measured output.
- an **animated slide deck** in [slides/](slides/) (`chapterN-slides.html`) —
  open it in any browser. Builds are presenter-paced: each press of → (or
  space) reveals the next element on the slide, then advances to the next
  slide once the slide is fully built; ← undoes the last reveal. The HUD
  shows `slide · build j/m` so you always know how much is left. Nothing
  animates ahead of your narration. Every `[SLIDE]` cue in the
  transcript has a matching animated visual: the query lifecycle, B+tree
  descent vs table sweep, the secondary-index two-step, hash join build &
  probe, the OFFSET treadmill, the capstone rescue timeline, and more.
- `lab.md` — the exercises: context, instructions, starter SQL with blanks,
  hints, and what you should observe.
- `lab_starter.sql` — the same starter queries, runnable.
- `solutions.sql` — full solutions, annotated with the measured timings.

**Work in the learn-then-do rhythm** (each transcript opens with its map):
watch/read one lesson with its deck slides, then immediately do that
lesson's exercises before the next lesson — concepts stick when the
practical follows within minutes. Do the lessons in order — later chapters
assume the indexes and habits built in earlier ones. If you make a mess, `setup/reset_lab_indexes.sql` drops every
index the labs create and returns the database to its chapter-1 state.

## The schema

```
countries      32 rows      country_code -> name, region, continent
customers     300,000       id PK · email · name · country_code · city · created_at
products        5,000       id PK · sku · name · category · price_cents · active
orders      1,200,000       id PK · customer_id · status · order_date · total_cents · ship_country · coupon_code
order_items ~3,000,000      id PK · order_id · product_id · quantity · unit_price_cents
payments    ~1,070,000      id PK · order_id · method · status · amount_cents · provider_ref · paid_at
```

Only primary keys exist at the start — creating the *right* secondary indexes
is your job. A few traps from real production schemas are planted deliberately
(a numeric-looking VARCHAR, heavy status skew, DATETIME columns begging for
`DATE()` mistakes). You'll meet them all.
