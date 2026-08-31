# Course Outline — Improving Query Performance in MySQL 8

> Format: each chapter has 3–4 **lessons** (the `transcript.md` scripts, ~5 min
> each as videos) interleaved with **exercises** (the `lab.md` tasks). ▶ = lesson,
> ⌨ = hands-on exercise, ❓ = concept check, ⚙ = advanced deep dive.

---

## Course Introduction

*The scene (UrbanCart and its index-free schema), the dataset, the five-chapter
arc, the teach-then-do method, the measured-honesty rule, and setup.
Transcript: `chapters/intro/transcript.md` · deck: `slides/intro-slides.html`.*

| # | Type | Title |
|---|------|-------|
| 0.0 | ▶ | Why this course exists (+ practical: run `setup/setup.sh` and connect) |

## Chapter 0 — Foundations: Combining Data *(optional refresher)*

*Joins, subqueries, CTEs and temp tables taught MySQL-style — including what
MySQL lacks (FULL OUTER JOIN) and what bites porters (error 1137). Skip if fluent.*

| # | Type | Title |
|---|------|-------|
| 0.1 | ▶ | All about joins, MySQL edition |
| 0.2 | ⌨ | Join-type arithmetic |
| 0.3 | ⌨ | The FULL OUTER JOIN MySQL doesn't have |
| 0.4 | ▶ | Subqueries and CTEs |
| 0.5 | ⌨ | Subqueries in three positions |
| 0.6 | ⌨ | Your first CTE |
| 0.7 | ▶ | Temporary tables |
| 0.8 | ⌨ | Materialize a slow view |
| 0.9 | ⌨ | The reopen gotcha, and ANALYZE |

## Chapter 1 — How MySQL Runs Your Query

*You can't fix what you can't see. Learn what happens between pressing Enter
and getting rows back, then build a measured baseline of UrbanCart's pain.*

| # | Type | Title |
|---|------|-------|
| 1.1 | ▶ | Welcome to UrbanCart: the journey of a query |
| 1.2 | ⌨ | Sizing up the database |
| 1.3 | ⌨ | Feel the scan: the customer lookup |
| 1.4 | ▶ | Your first EXPLAIN |
| 1.5 | ⌨ | EXPLAIN the slow lookup |
| 1.6 | ❓ | The access-type ladder |
| 1.7 | ⌨ | Estimates vs reality with EXPLAIN ANALYZE |
| 1.8 | ▶ | Measuring honestly: EXPLAIN ANALYZE and repeatable timing |
| 1.9 | ⌨ | Revenue by country: the monster baseline |
| 1.10 | ▶ | Finding the slow queries in production |
| 1.11 | ⌨ | Reading the slow query log |
| 1.12 | ⌨ | Top offenders with the sys schema |
| 1.13 | ⌨ | Your baseline scorecard |
| 1.14 | ⚙ | Deep dive: watch the optimizer think (trace + buffer pool) |

## Chapter 2 — Indexes That Actually Get Used

*One good index turns 45 ms into 9 µs. One bad WHERE clause turns your good
index back into a table scan. Learn both sides.*

| # | Type | Title |
|---|------|-------|
| 2.1 | ▶ | Inside InnoDB: the clustered index and its satellites |
| 2.2 | ⌨ | The email index: three orders of magnitude for one statement |
| 2.3 | ⌨ | Reading SHOW INDEX: cardinality and selectivity |
| 2.4 | ▶ | Composite indexes and the leftmost-prefix rule |
| 2.5 | ⌨ | A customer's order history, sorted for free |
| 2.6 | ❓ | Which queries can use idx(a, b, c)? |
| 2.7 | ⌨ | Covering indexes: never touch the table |
| 2.8 | ▶ | Five ways to make MySQL ignore your index |
| 2.9 | ⌨ | The DATE() trap |
| 2.10 | ⌨ | The implicit-cast trap: a number that isn't |
| 2.11 | ⌨ | LIKE it or not: wildcards and prefixes |
| 2.12 | ⌨ | Skewed data: when the index is the slow path |
| 2.13 | ⌨ | Histograms: teaching the optimizer about skew |
| 2.14 | ⌨ | Invisible indexes and dropping dead weight |
| 2.15 | ⚙ | Deep dive: catch the optimizer choosing wrong — in writing |
| 2.16 | ⚙ | Deep dive: the prefix-index trade, measured |

## Chapter 3 — Writing SQL the Optimizer Loves

*Same result, tenth of the cost: reshape filters, joins, and subqueries so the
optimizer can do its job.*

| # | Type | Title |
|---|------|-------|
| 3.1 | ▶ | The logical order of operations (what SQL really sees) |
| 3.2 | ❓ | Order-of-operations concept check |
| 3.3 | ⌨ | Project late: the true cost of SELECT * |
| 3.4 | ▶ | Filter shapes: OR, IN, UNION, and friends |
| 3.5 | ⌨ | OR vs IN vs UNION |
| 3.6 | ⌨ | The NOT IN null bomb |
| 3.7 | ⌨ | Customers who never ordered: three anti-join shapes |
| 3.8 | ▶ | Joins under the hood: nested loops and hash joins |
| 3.9 | ⌨ | Watching a hash join happen |
| 3.10 | ⌨ | Filter placement: ON vs WHERE |
| 3.11 | ▶ | Subqueries, derived tables, and CTEs: merge or materialize |
| 3.12 | ⌨ | Aggregate at the right grain: the monster falls |
| 3.13 | ⌨ | Correlated subquery vs GROUP BY vs window |
| 3.14 | ⌨ | One CTE, used twice |
| 3.15 | ⚙ | Deep dive: what IN really compiles to (semijoin) |
| 3.16 | ⚙ | Deep dive: merge vs materialize, made visible |
| 3.17 | ⌨ | GROUP BY discipline, and what DISTINCT really costs |

## Chapter 4 — The Tuning Workflow: From Ticket to Fix

*A ticket lands: "we killed the dashboard query after 20 minutes." Walk the full workflow —
reproduce, measure, read, fix one thing at a time, verify — until it's fast.*

| # | Type | Title |
|---|------|-------|
| 4.1 | ▶ | The tuning loop: reproduce → measure → read → change one thing |
| 4.2 | ⌨ | Reading a big plan: find the expensive node |
| 4.3 | ⌨ | Using temporary, Using filesort |
| 4.4 | ▶ | Beyond rewrites: hints, histograms, and pagination |
| 4.5 | ⌨ | Deep pagination: OFFSET vs keyset |
| 4.6 | ❓ | When do you stop tuning? |
| 4.7 | ▶ | Capstone briefing: the executive dashboard |
| 4.8 | ⌨ | Capstone step 1: reproduce and baseline |
| 4.9 | ⌨ | Capstone step 2: make the dates sargable |
| 4.10 | ⌨ | Capstone step 3: the index the join deserves |
| 4.11 | ⌨ | Capstone step 4: kill the correlated subquery |
| 4.12 | ⌨ | Capstone step 5: NOT IN → NOT EXISTS |
| 4.13 | ⌨ | Capstone step 6: the grain fix, final review |
| 4.14 | ▶ | Wrap-up: your tuning checklist |
| 4.15 | ⚙ | Deep dive: cost anatomy and the index census |
| 4.16 | ⌨ | The PostgreSQL↔MySQL plan-reading card, and when sorts hit disk |

---

## Advanced scenarios — production shapes *(after chapter 4)*

*Extra setup (`advanced/setup_advanced.sql`, +3.2M rows). Each scenario is a
generalized production incident class, fully measured.*

| # | Type | Title |
|---|------|-------|
| A | ⚙⚙ | The ORM that writes 10,000-arm WHERE clauses (11 s → 80 ms; the range-optimizer memory cliff) |
| B | ⚙⚙ | The typed pointer: polymorphic references, and the join that silently lies |
| C | ⚙⚙ | The outbox poller: terminal-state skew, and when the fix is a state machine |
| D | ⚙⚙ | The retention purge: one transaction locks 1.7M rows vs batched deletes |
| E | ⚙⚙ | Big-O for SQL: measured growth curves — which curve is your query on? |

---

**Totals:** 18 lessons (incl. 3 optional foundations) + the course-introduction lesson · 4 concept checks ·
44 hands-on exercises · 6 advanced deep dives ·
capstone woven into Chapter 4.
