# Quiz — answers, evidence, and misconception notes

Every answer traces to a measured fact from the course (chapter.exercise in
brackets). `-- verify:` blocks run on your own container. Distractor notes
name the misconception each wrong option represents — they're the review
material.

---

## Chapter 0

**Q0.1** — FROM/JOIN → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT.
(Full pipeline including DISTINCT: deck 0 slide 2.) The one most people miss:
SELECT runs *fifth*.

**Q0.2** — **B.** Two errors in one: syntactically WHERE precedes GROUP BY;
and even placed correctly, WHERE runs at step 2 while the alias is born at
SELECT (step 5) → ERROR 1054. Distractors: (C) is half-true — COUNT(*)
belongs in HAVING, but the alias *still* wouldn't work in WHERE; (D) is the
ORDER BY behavior misremembered — ORDER BY *can* use aliases because it runs
after SELECT.
```sql
-- verify:
SELECT ship_country, COUNT(*) AS orders FROM orders WHERE orders > 50000 GROUP BY ship_country;
```

**Q0.3** — **1,200,000 and 1,208,266** [lab 0.2]. INNER = one row per order
(matching customers repeat); LEFT adds the 8,266 never-ordered customers once
each, NULL-extended. Joins change row counts — know your grain.
```sql
-- verify:
SELECT COUNT(*) FROM customers c INNER JOIN orders o ON o.customer_id = c.id;
SELECT COUNT(*) FROM customers c LEFT  JOIN orders o ON o.customer_id = c.id;
```

**Q0.4** — **B** [lab 0.3]. MySQL has never had FULL OUTER JOIN. Emulation:
`LEFT JOIN` ∪ `UNION ALL` ∪ right side's exclusives (anti-join arm). UNION
ALL, not UNION — the arms can't overlap.

**Q0.5** — **C** [lab 0.5]. Uncorrelated scalar subquery → computed once
(543,009 rows above the mean; plan prints "run only once"). (A) describes a
*correlated* subquery — the distinction is what the inner query references.

**Q0.6** — **B** [lab 0.9]. ERROR 1137, a MySQL-specific limitation
(PostgreSQL allows it — classic porting trap). Fix: two temp copies, or a CTE.

---

## Chapter 1

**Q1.1** — Client/connection → Parser → Preprocessor → Optimizer → Executor →
Buffer pool check → Result streams back. (Deck 1 slide 2 — the full round trip.)

**Q1.2** — **B.** Miss = read the page from the `.ibd` data file, cache it,
serve it. This is why the *first* run is slower and why we time second runs.
(C) confuses the buffer pool with crash recovery.

**Q1.3** — **C** [1.5]. No index on email → no statistics → flat default
guess. Reality: 1 row. Estimates lie; histograms (2.13) and indexes give the
optimizer real numbers.

**Q1.4** — **B.** `const`/`eq_ref`/`ref` = at-most-a-few-rows via index.
(A) is the middle tier; (C) — LIMIT trims output, not work (3.1);
(D) — fulltext is for contains-search, not a general upgrade.

**Q1.5** — **1022** (verified live). key_len is *bytes*, not columns:
VARCHAR(255) × 4 bytes/char (utf8mb4) + 2 length bytes. The number looks
alarming and is normal — learn to read it before chapter 2 uses it as the
composite lie detector.
```sql
-- verify:
EXPLAIN SELECT id FROM customers WHERE email = 'x';
```

**Q1.6** — **B** [1.8]. EXPLAIN ANALYZE **executes** the statement. Cap with
`/*+ MAX_EXECUTION_TIME(...) */` or use a replica. (D) is false — JSON format
shows estimates and cost, not actuals.

**Q1.7** — **B** [1.8, rule 1]. Warm up first; the first run pays buffer-pool
misses. (Unless cold-cache behavior is what you're studying — then say so on
the scorecard.)

**Q1.8** — **C** [1.11]. A query examining 1.2M rows to send 12 does 100,000×
more work than its output justifies — an index or rewrite hides in that gap.

---

## Chapter 2

**Q2.1** — **B** [2.1]. Leaf = (key value, primary key copy) — not a disk
pointer. Two consequences run the whole chapter: the two-step dance (Q2.8's
trap) and covering indexes (every secondary index silently contains the PK).

**Q2.2** — **~0.009 ms (9 µs), type=ref, rows=1** [2.2]. 45 ms → 9 µs,
~5000×, one line of SQL. The biggest per-line speedup in the course.
```sql
-- verify (index exists after lab 2.2):
EXPLAIN ANALYZE SELECT id, full_name, city FROM customers
WHERE email = 'amara.dubois150000@example.com';
```

**Q2.3** — **C** [2.5]. Leftmost-prefix rule: `(a, b)` seeks on `a`, `a,b` —
never `b` alone (measured: full 1.2M-entry index scan). (D) is the free-sort
superpower, not a violation.

**Q2.4** — **key_len 8, then 13** (verified live). 8 = customer_id only;
13 = 8 + 5 when the date range engages. One glance tells you how much of a
composite the query actually used.
```sql
-- verify:
EXPLAIN SELECT id FROM orders WHERE customer_id = 137;
EXPLAIN SELECT id FROM orders WHERE customer_id = 137 AND order_date >= '2025-06-01';
```

**Q2.5** — **B** [2.4]. The range "uses up" the index: with `(b, a)`, every
b in range must be scanned and a becomes a post-filter. Equality first, range
last. (D) — index_merge exists but is conservative; never design around it.

**Q2.6** — **C** [2.9]. Bare column, math on the constant side, half-open
interval: 1,299 rows, 0.14 ms vs 78 ms. A, B, D all wrap the column in a
function — non-sargable, trap #1 in three costumes.

**Q2.7** — **Full scan (~90 ms), and Warning 1739: "Cannot use ref access on
index ... due to type or collation conversion"** [2.10]. Number vs VARCHAR
forces per-row conversion = function on the column in disguise. Quote it:
9 µs. MySQL names the disease — always run SHOW WARNINGS after a surprising
EXPLAIN.
```sql
-- verify:
EXPLAIN SELECT id FROM payments WHERE provider_ref = 4000000042; SHOW WARNINGS;
```

**Q2.8** — **B** [2.12]. 431 ms via index vs 139 ms forced scan — a million
random secondary→clustered hops lose to one sequential sweep, 3×. Also the
optimizer *chose wrong* (estimate 2× low) — hence EXPLAIN ANALYZE is the
referee. Same index is gold for `'failed'` (~1 ms).

**Q2.9** — **B** [2.13]. Histograms fix *estimates* (25× wrong → 1% wrong),
not lookups. Wrong estimates mis-pick join order — that's where the
milliseconds were hiding. Re-ANALYZE after bulk loads; histograms are
snapshots.

**Q2.10** — **B** [2.14]. Invisible-first is the safety pattern: index still
maintained, optimizer can't see it — "would anything break?" answered before
anything can. Measured on our redundant `(customer_id)`: the composite served
every query; dropped with proof.

---

## Chapter 3

**Q3.1** — **~2.9 ms, 23×** [3.3]. Same rows; the columns you *didn't* select
were the expensive part — dropping them let the covering index answer without
touching the table. `SELECT *` isn't mostly a network problem; it's an
access-path problem.

**Q3.2** — **B** [3.5]. One tree per descent, one column per tree. Both
columns being indexed doesn't help a single OR predicate spanning them.

**Q3.3** — **A** [3.5]. `UNION` of two seeks: 0.14 ms, 650×. UNION not UNION
ALL — preserves OR's dedup semantics if a row matches both arms. (B) doesn't
help: a composite still can't serve `a = ? OR pk = ?`.

**Q3.4** — **B** [3.6]. The NULL bomb: `NOT IN (…, NULL)` expands to
`x <> NULL` = UNKNOWN → row dropped, for every row, silently. Fixes: filter
`IS NOT NULL` inside the subquery, or NOT EXISTS (immune by design).

**Q3.5** — **C** [3.7]. Measured: 248 / 342 / 377 ms. Folklore ranks them the
other way. The lab's refrain: measure, don't moralize.

**Q3.6** — **B** [3.9]. The 8.x quirk: hash join is only *considered* when no
usable index exists. Measured: forced hash 0.74 s beat the optimizer's
nested loop 1.74 s on a 3M × 5k join. Know when to overrule — and document
the hint.

**Q3.7** — **8,550 → 1,553.** [3.10] Moving a right-side filter from ON to
WHERE silently converts LEFT to INNER: NULL-extended rows fail the WHERE and
vanish. On INNER joins the placement is irrelevant; on OUTER joins it's a
different query. Correctness first.
```sql
-- verify:
SELECT COUNT(*) FROM orders o LEFT JOIN payments p
  ON p.order_id = o.id AND p.method = 'klarna'
WHERE o.order_date >= '2025-08-01' AND o.order_date < '2025-08-08';
SELECT COUNT(*) FROM orders o LEFT JOIN payments p ON p.order_id = o.id
WHERE o.order_date >= '2025-08-01' AND o.order_date < '2025-08-08'
  AND p.method = 'klarna';
```

**Q3.8** — **B** [3.12]. The textbook said "aggregate before joining" but
forgot to say *shrink*: grouping 3M rows into 1.2M shrank nothing (4.14 s).
The answer lived at order grain all along — `orders.total_cents` — and
deleting the join made COUNT(DISTINCT) into COUNT(*). 4.0 → 1.75 s
(→ 1.47 s with the skew-index hint). The fastest work is work you don't do.

**Q3.9** — **C** [3.13]. The correlated subquery was fine *because* chapter
2's index made each of 300k probes a microsecond; the window function
sorted and materialized all 1.2M rows. Shapes are fast or slow on your
indexes, on your data.

**Q3.10** — **B** [3.14]. Reference a CTE twice → materialized once — the one
place CTEs are a performance feature, not just readability. Plan literally
prints "(never executed)" on the second reference.

---

## Chapter 4

**Q4.1** — Reproduce → Measure (and save the result) → Read the plan →
Change ONE thing → Verify identity → Stop on purpose. Every disaster skipped
a step; most skipped "save the result".

**Q4.2** — **B** [4.2]. 0.7 µs × 1,030,000 loops ≈ 0.7 s — the single-row PK
lookup was the whole bill while the scary-sounding Sort handled 30 rows.
Node cost ≈ actual-time upper bound × loops. Always.

**Q4.3** — **B** [4.1 rule]. Identity is non-negotiable: baseline the exact
result set and diff after every change (the capstone does this at every one
of its six steps — 17 rows, byte-identical).

**Q4.4** — **C** [4.3]. The flags describe *mechanism*, not cost. Both nodes
touched 30 rows; the 1.03M-row join beneath them was ~1.2 s of the 1.35 s.
Read time × loops before judging any node by its name.

**Q4.5** — **OFFSET walks and discards** — 1,000,020 entries to show 20
(linear in depth); keyset seeks straight to `id > last_seen` (constant at any
depth, 1,500× here). Trade-off: no "jump to page 7,349" — which almost no
product actually needs. [4.5]

**Q4.6** — **C** [4.4]. A hint is a bet against the optimizer frozen at the
moment you wrote it. Data drifts, optimizers improve, the hint stays. Dated
benchmark next to every hint; re-test on upgrades.

**Q4.7** — `SELECT /*+ MAX_EXECUTION_TIME(600000) */ …` — and the
confirmation is **ERROR 3024 (HY000): Query execution was interrupted,
maximum statement execution time exceeded** (verified live). "Killed at N
minutes" is itself a measurement; record it. [4.7/4.8]

**Q4.8** — **B** [4.6, 4.14]. "Fast enough" is a requirement, not a feeling.
Every further change adds write cost, fragility, and review surface. The
underrated senior skill: stopping on purpose.
