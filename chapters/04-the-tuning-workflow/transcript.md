# Chapter 4 — The Tuning Workflow: From Ticket to Fix
### Lesson transcripts

> **Rhythm — teach, then do:** lesson 4.1 (slides 2–3) → labs 4.2–4.3 ·
> lesson 4.4 (slide 4) → labs 4.5–4.6 · lesson 4.7 (slide 1) → capstone
> 4.8–4.13 (slide 5 is the journey you produce) · lesson 4.14 (slides 6–7)
> · deep dive 4.15 · lab 4.16 (the dialect card).

> Animated slide deck: [slides/chapter4-slides.html](../../slides/chapter4-slides.html) — open in a browser, → / ← to navigate.

> The finale. Chapters 1–3 gave you tools; this chapter gives you the
> *workflow* — and a capstone where a real dashboard query goes from nearly
> a minute to interactive speed, one verified step at a time.

---

## Lesson 4.1 — The tuning loop: reproduce → measure → read → change one thing
*(video script, ~5 min)*

[SLIDE 2: the loop]

Every successful tuning session I've seen follows the same loop; every
disaster skipped a step.

**1. Reproduce.** Get the exact query — from the slow log, from sys, from
the app's logs. Not "a query like it": parameter values change plans
(remember `status = 'failed'` vs `'completed'`). Run it on data of
production shape. Confirm it's actually slow.

**2. Measure.** One warm-up run, then a timed run, written down. And capture
the *result* — a checksum or the full output. Every optimization you make
must reproduce this result **exactly**. A query that got fast by getting
wrong is a production incident with good latency.

[SLIDE 3: cost of a node ≈ time × loops]

**3. Read the plan.** `EXPLAIN ANALYZE`. Find the most expensive node —
remember, cost of a node ≈ its `actual time` upper bound × `loops`. Ask the
three chapter questions in order: *Is the access path right?* (ch. 2 — scans
that should be seeks, non-sargable predicates, cast traps). *Is the shape
right?* (ch. 3 — wrong grain, needless joins, poisoned ORs, materialization
where merging should happen). *Are the estimates right?* (est vs actual
columns; stale stats, missing histograms).

**4. Change ONE thing. Re-measure. Re-verify.** If it helped, commit the
step and loop again. If it didn't, *revert it* — even if it "should" have
helped. Two simultaneous changes that interact are how folklore gets
written.

[SLIDE 6: when do you stop?]

**5. Stop on purpose.** Fast enough is a requirement, not a feeling —
"dashboard must render in under two seconds" ends the session; "make it
fast" never does. Concept check 4.6 will push on this.

The exercises warm you up on the two plan-reading skills the capstone
needs: finding the expensive node in a deep tree, and reading
`Using temporary; Using filesort` without flinching.

---

## Lesson 4.4 — Beyond rewrites: hints, histograms, and pagination
*(video script, ~6 min)*

Three tools that live outside the query text, for when the rewrite isn't
enough — or isn't allowed.

[BOARD: hints — rules of engagement]

**Hints.** You've already used two: `IGNORE INDEX` beat the status-index
trap (431→139 ms), and it forced the hash join that beat the optimizer by
2.4× in chapter 3. MySQL 8 also has comment-style hints —
`/*+ JOIN_ORDER(a, b) */`, `/*+ NO_INDEX(...) */`, `/*+ MAX_EXECUTION_TIME(ms) */`
— which travel inside the statement. Rules of engagement: a hint is a
**bet against the optimizer frozen at the moment you wrote it**. Data
drifts; upgraded optimizers get smarter; your hint stays. So: hint only
what you've *measured*, comment the measurement next to it, and re-test
hints on every major upgrade. A hint without a dated benchmark next to it
is technical debt.

**Histograms** (chapter 2 refresher, because in this chapter it finally
pays off): join *order* is chosen from row estimates. A 25×-wrong estimate
on a filtered column doesn't just mis-predict — it can put the big table on
the *driving* side of a nested loop. One `ANALYZE TABLE … UPDATE HISTOGRAM`
is often the cheapest join fix in MySQL. Check `information_schema.
column_statistics` to see what you have; re-analyze after bulk loads.

[SLIDE 4: deep pagination — treadmill vs seek]

**Pagination.** Page 50,001 of the orders admin, 20 per page:

```sql
ORDER BY id LIMIT 20 OFFSET 1000000;     -- measured: 67 ms
```

OFFSET is a treadmill: MySQL walks and discards a million index entries to
reach page 50,001 — measured right here on our PK, 67 ms, and it grows
linearly with depth. **Keyset pagination** remembers where the last page
ended and seeks straight there:

```sql
WHERE id > 1000000 ORDER BY id LIMIT 20;  -- measured: 0.045 ms
```

1,500× at this depth, constant at *any* depth. Works on any unique-ish
ordered key (composite keysets: `(order_date, id)` with row-value
comparison). The trade: no "jump to page 7,349" — which almost no product
actually needs. Every infinite-scroll feed you've ever used is keyset
pagination in a trench coat.

Exercise 4.5 measures the treadmill yourself. Then — the capstone.

---

## Lesson 4.7 — Capstone briefing: the executive dashboard
*(video script, ~4 min)*

[SLIDE 1: the ticket]

> **PRIORITY: HIGH.** The country dashboard has been "loading…" since the
> data grew. Marketing demoed it to the CEO this morning; it never finished
> loading. On staging we gave up and killed the query after 20 minutes.
> Fix it by Friday. — *Dana, engineering manager*

A baseline you can't even finish measuring is itself a measurement — record
it as "killed at 20 min". The professional tool for this is a bounded run:
`SELECT /*+ MAX_EXECUTION_TIME(600000) */ …` lets MySQL abort the statement
at 10 minutes so nobody babysits a terminal. And when the whole query won't
complete, your identity oracle comes from the first *provably* equivalent
rewrite — which is exactly what step 2 gives us.

The query behind it (full text in `capstone/dashboard_v0.sql`): for each
ship-to country over the last 90 days, completed orders that weren't
refunded — order count, revenue, average order value, and the country's
top product category. One query, five sins, all of them yours to find:

1. Every date filter wraps the column: `DATE(order_date) >= …` (ch. 2).
2. `order_items` is joined by `order_id` — a column no index covers (ch. 3).
3. Revenue is computed at *item* grain, forcing `COUNT(DISTINCT)` (ch. 3).
4. Top category runs as a **correlated subquery per country**, each
   execution re-scanning 90 days of items (ch. 3).
5. Refunds are excluded with `NOT IN (SELECT …)` over a million payments
   (ch. 3).

Your contract, from lesson 4.1: baseline first, **save the exact result**,
then one fix per step, re-measuring and re-verifying identity after each.
The exercises walk the steps in the order a real session would find them —
biggest, safest lever first. By 4.13 the ticket is closed — and slide 5 of the deck is the measured
journey you will have produced. Go.

---

## Lesson 4.14 — Wrap-up: your tuning checklist
*(video script, ~4 min)*

Four chapters ago, a customer lookup took 45 milliseconds and nobody knew
why. Here's everything you now do differently, on one slide.

[SLIDE 7: the checklist]

**Find the target** — slow log + `sys.statement_analysis`; pick by
`frequency × duration`; the smell is rows examined ≫ rows sent.

**Measure honestly** — warm cache, run twice, write it down, capture the
result set. `EXPLAIN ANALYZE`, not vibes.

**Access paths first** — seeks not scans for selective predicates; bare
columns in predicates (no functions, no cross-type comparisons); prefix
LIKE only; composite indexes: equality columns → then the range; covering
indexes for the hot few queries; retire redundant indexes
invisible-first.

**Then shape** — filter early, project late; right grain before
aggregating (delete joins you don't need); IN not cross-column OR; NOT
EXISTS not NOT IN; LEFT-join filters in ON, not WHERE; CTE when reused,
merged when not; correlated is fine *if* indexed and thin.

**Then the optimizer's worldview** — est vs actual gaps; histograms on
skewed filter columns; hints as documented, dated, last-resort bets.

**Then architecture** — keyset pagination; and when a query is as good as
it gets but still too slow, the answer stops being a query: summary
tables, denormalized totals (you *used* one — `orders.total_cents`),
read replicas, caches. Know when you've left query-tuning country.

**And always** — one change at a time; identical results, proven; stop at
the requirement.

The scorecard tells the story: 45 ms → 9 µs. 110 ms → 0.4 ms. 4 s → 1.5 s.
And a dashboard we had to *kill after 20 minutes* → interactive. Same data,
same hardware, same MySQL — different engineer. Go make something slow embarrassingly fast, and write the numbers
down when you do.

*— end of course —*
