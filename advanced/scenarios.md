# Advanced scenarios — production shapes
### Five scenarios the four chapters didn't prepare you for (on purpose)

These are the shapes that actually page people: not "a query is slow" but
*a pattern in the architecture generates queries that degrade*. Each is a
genericized version of a real production incident class. Prerequisite: the
full course, including the deep dives. Setup:

```bash
docker exec -i mysql-tuning-course mysql -uroot -pcourse < advanced/setup_advanced.sql
```

This adds two tables in the styles you'll meet in real systems:
`activity` (1.5M rows — a **polymorphic audit trail** with a typed pointer
`entity_type + entity_id`) and `outbox` (1.7M rows — a **transactional
outbox** queue with 2.6 years of history and terminal-state skew:
99.3% `SENT`, 3,000 live `PENDING`, 9,466 `FAILED` residue).

Solutions with all measured output: [solutions.sql](solutions.sql).

---

## A ⚙⚙ The ORM that writes 10,000-arm WHERE clauses

**The incident shape.** An ORM "refreshes" entities after a bulk operation
by selecting them back — and builds the WHERE clause mechanically:
`(order_id=? AND product_id=?) OR (order_id=? AND product_id=?) OR …`,
one arm per entity. At 50 pairs nobody notices. At 10,000 the endpoint
times out, but only sometimes. You can't hand-type this query — generate
it, like the ORM does:

```bash
docker exec mysql-tuning-course mysql -uroot -pcourse urbancart -N -e \
  "SELECT order_id, product_id FROM order_items WHERE id % 300 = 7 LIMIT 10000;" > pairs.tsv

awk 'BEGIN{printf "SELECT COUNT(*) c, SUM(quantity*unit_price_cents) s FROM order_items WHERE "}
     NR>1{printf " OR "} {printf "(order_id=%s AND product_id=%s)", $1, $2} END{print ";"}' \
  pairs.tsv > orchain.sql
```

**Instructions**

1. Time the 10,000-arm OR-chain (build a 1,000-arm one too, for the curve).
2. Rewrite as a row-constructor IN — `(order_id, product_id) IN ((a,b),…)`
   — and time it.
3. Rewrite as a join against a filled temporary table and time it.
4. Now find the cliff: re-run the OR-chain with
   `SET SESSION range_optimizer_max_mem_size = 1048576;` (1 MB, vs the
   8 MB default). Have `SHOW PROCESSLIST` + `KILL` ready in a second
   terminal — you will need them.

**You should observe (measured):**

| shape (10,000 pairs) | time |
|---|---|
| OR-chain | **11 s** (1,000 pairs: 70 ms — the cost is superlinear) |
| row-constructor IN | **80 ms** |
| temp-table join | **76 ms** |
| OR-chain, 1 MB range-optimizer memory | **killed at 5 min, still running** |

All four return the identical 10,000-row aggregate. The OR-chain's cost is
optimizer *planning* plus a filter with 10,000 residual arms; and when the
range optimizer exceeds its memory cap it silently abandons range access —
full scan × 10,000-arm evaluation per row. That's why the endpoint "only
sometimes" dies: the cliff is data- and settings-dependent. **Fixes, in
order:** make the ORM emit row-constructor IN or chunk (500–1,000 per
statement); a temp-table join for the biggest batches; and know
`range_optimizer_max_mem_size` exists before you meet its default.

---

## B ⚙⚙ The typed pointer: one column pair, three parent tables

**The incident shape.** An audit trail (or notification, tag, comment
table) references *any* entity via `(entity_type, entity_id)` — flexible,
and invisible to foreign keys, join graphs, and sometimes indexes.

**Instructions**

1. Baseline: fetch the activity for order 4242. Read the plan.
2. Build the composite index the pointer deserves —
   `(entity_type, entity_id)` — and re-measure. Why this column order?
   (2.6's leftmost rule: which column is always an equality?)
3. The trap that ships to prod: "activity for orders placed since Aug 20",
   joined `ON a.entity_id = o.id` — **without pinning `entity_type`**.
   Count rows with and without the pin. Explain the difference before
   looking at the answer.

**You should observe (measured):** baseline 180 ms full scan → **0.01 ms**
after the index (18,000×). The unpinned join returns **12,462** rows; the
pinned one **7,819**. The extra 4,643 rows are *customer* and *payment*
activities whose `entity_id` happens to collide with an order id — silent
result corruption, no error, plausible-looking numbers. Typed pointers
demand: the type column leads the index, and **every** join and WHERE pins
it. (Corollary: navigating the other direction — "resolve each activity's
target" — requires one `UNION ALL` branch per type. There is no
polymorphic join in SQL; budget for it in the schema review.)

---

## C ⚙⚙ The outbox poller: a queue wearing a table costume

**The incident shape.** The transactional-outbox pattern: events written
`PENDING` in the same transaction as the data, a poller publishes and
stamps them `SENT`. Two years later the table *is* the history of the
company — 1.69M `SENT`, a 3,000-row live head, and a `FAILED` residue
nobody owns. The poller runs every 5 seconds.

**Instructions**

1. Time the poll as the poller runs it:
   `WHERE status='PENDING' ORDER BY id LIMIT 100` — no index. Read the
   plan carefully: *which* rows did it walk, and why did the optimizer
   think this was cheap (cost≈9)?
2. Design the index. (Think before peeking: what serves both the filter
   *and* the ORDER BY … LIMIT with zero sorting?)
3. The residue: time the retry sweep `WHERE status='FAILED' ORDER BY id
   LIMIT 200`, then do the arithmetic of running it every 5 s forever
   against a residue that only grows.

**You should observe (measured):** the unindexed poll takes **188 ms** and
its plan is the whole pathology in one line: `Index scan on PRIMARY …
rows=1.7e6` — it walks *the entire company history in id order* to reach
the live head at the end, every 5 seconds. (Bonus estimate lesson: the
optimizer priced it at cost≈9 because it assumed PENDING rows are spread
evenly — chapter 2's skew blindness, wearing a queue costume.)
`(status, id)` fixes both filter and order: **0.099 ms**, no sort node —
within one status, a secondary index is already id-ordered. The FAILED
sweep is 0.3 ms — cheap per run, but 9,466 rows retried every 5 s is
~163M wasted row-touches a day *plus side effects*, growing forever.
The fix isn't a query: it's a state machine — a terminal
`FAILED_PERMANENT` after N attempts, moved to an archive table, and
`SENT` rows batch-purged on a retention schedule. Some tuning problems
are schema-lifecycle problems in disguise; recognizing which is which is
the real senior skill.

---

## D ⚙⚙ The retention purge: one transaction vs. the whole table

> ⚠️ **Destructive on purpose** — this scenario really deletes rows. When
> you're done, restore with `advanced/setup_advanced.sql` (~15 s). That's
> part of the design: practice on data you can regenerate.

**The incident shape.** Compliance says: outbox rows older than 14 months
must go. Someone writes the obvious one-liner. It "works" — and the
service's writes flat-line for the duration, replication lags, and if
anyone kills it, the rollback outlasts the delete.

**Instructions**

1. Count the target: `WHERE created_at < '2024-03-01'` (unindexed column).
2. In terminal A, run the naive purge **inside an explicit transaction and
   don't commit** — hold it open with `SELECT SLEEP(25)` so you can
   observe:

```sql
START TRANSACTION;
DELETE FROM outbox WHERE created_at < '2024-03-01';
SELECT SLEEP(25);   -- observation window
ROLLBACK;           -- and time this too
```

3. In terminal B, during the window:
   - `SELECT trx_rows_locked, trx_rows_modified FROM information_schema.innodb_trx;`
   - `SET SESSION innodb_lock_wait_timeout = 2;` then INSERT one new
     `PENDING` row — a row the delete has nothing to do with.
4. Now the fix: batched deletes, one `LIMIT 50000` per statement
   (autocommit — each batch releases its locks). Loop until zero. Insert a
   row *mid-loop* to prove writes stay live.

**You should observe (measured):** target 749,387 rows. The naive delete
takes 1.6 s — but `trx_rows_locked` reads **1,710,969**: under REPEATABLE
READ, an unindexed DELETE locks every row it *scans*, matching or not —
the entire table. Your innocent PENDING insert dies with
`ERROR 1205 Lock wait timeout`. The ROLLBACK costs another **1.2 s** —
undo is real work; killing a half-done purge in production means paying
the whole bill again in reverse. Batched: 16 statements, **3.7 s total**,
and the mid-loop insert lands instantly. Slightly slower end-to-end,
infinitely kinder to everything else — and each batch is a checkpoint, so
a kill loses only the current batch. (Production extras: order batches by
PK for a tight scan, sleep between batches to let replicas breathe, and
archive-then-delete inside the same loop.)

---

## E ⚙⚙ Big-O for SQL: which curve is your query on?

**The idea.** Engineers reason about code in complexity classes but read
query plans as vibes. Plans *are* algorithms — so measure the same
operations at 10k, 100k and 1M rows and watch the curves separate.
(Build `t10k/t100k/t1m` as PK'd slices of `orders` — SQL in the
solutions; drop them when done.)

**Instructions**

1. PK point lookup at all three sizes. 2. Full-scan `SUM` at all three.
3. `ORDER BY total_cents DESC LIMIT 10` at all three — before running,
   predict: is a sort with LIMIT n·log n?
4. Two joins at 5k and 10k rows: equi-join on `customer_id`, and the
   villain — `ON b.total_cents > a.total_cents` (non-equi). Predict both
   growth rates first.

**You should observe (measured):**

| operation | 10k | 100k | 1M | curve |
|---|---|---|---|---|
| PK lookup | 0.002 ms | 0.0001 ms | 0.0002 ms | **O(log n)** ≈ flat — tree depth barely grows |
| full-scan SUM | 0.72 ms | 8.0 ms | 80 ms | **O(n)** — clean 10× steps |
| top-10 sort | 0.75 ms | 6.9 ms | 69 ms | **O(n log k)** — LIMIT keeps a 10-row heap; k is constant, so it *tracks the scan* |

| join (n rows ⨝ n rows) | n = 5k | n = 10k | curve |
|---|---|---|---|
| equi, hash join | 1.3 ms | 2.7 ms | **O(n + m)** — doubles |
| non-equi `>` | **1,007 ms** | **3,968 ms** | **O(n·m)** — quadruples |

Same tables, same sizes: the equi-join and the non-equi join differ
**770×** at 5k rows — and the gap doubles every time the data does,
because hash join needs an *equality* to bucket on; `>` forces comparing
every row with every row (the plan admits it: `Inner hash join (no
condition)` producing n² rows, then filtering). The complexity map to
memorize: `const/eq_ref` ≈ O(log n) · `ref/range` O(log n + k) ·
`index/ALL` O(n) · filesort O(n log n), top-N O(n log k) · indexed nested
loop O(n log m) · hash join O(n + m) · non-equi/unindexed nested loop
O(n·m). **EXPLAIN doesn't just tell you today's cost — it tells you which
curve you're on when the data is 10× bigger.** That's the difference
between a query that ages well and one that pages you next year.
