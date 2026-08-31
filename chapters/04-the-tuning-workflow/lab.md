# Chapter 4 — Lab
### The Tuning Workflow: From Ticket to Fix

Starter SQL: [lab_starter.sql](lab_starter.sql) · Solutions:
[solutions.sql](solutions.sql) · Capstone files: [../../capstone/](../../capstone/).
Assumes chapter 3's end state (all indexes through `idx_payments_order`).

---

## 4.2 ⌨ Reading a big plan: find the expensive node

Product wants the top 10 cities by completed revenue.

**Instructions**

- `EXPLAIN` (tabular) the city-ranking query from the starter. Read the
  `Extra` column out loud.
- `EXPLAIN ANALYZE` it. For each of the five nodes, compute
  *time × loops* and name the most expensive node.

**You should observe:** tabular Extra says `Using temporary; Using
filesort` — the two flags that mean "an intermediate result is being built
and sorted". The TREE run (~1.35 s) shows where the time really lives: the
nested loop feeding the aggregate — 1.03M index lookups into customers
(~0.7 µs × 1.03M ≈ 0.7 s) on top of the 436 ms status-index read. The
`Sort` at the top costs almost nothing: it sorts **30 city rows**. Lesson:
scary-sounding flags aren't automatically the problem; multiply, then
judge.

---

## 4.3 ⌨ Using temporary, Using filesort

**Instructions**

- Take the same query and answer with evidence: (a) why is a temporary
  table unavoidable here? (b) would `ORDER BY c.city` (instead of by
  revenue) also need a filesort? Test it.
- Bonus: re-run the ranking with `IGNORE INDEX (idx_orders_status)` on
  orders (chapter 2's lesson). How much do you get back?

**You should observe:** (a) grouping by a column (`city`) that no index
orders means MySQL must bucket rows *somewhere* — that's the temporary
table; (b) sorting by `city` — the GROUP BY key — can reuse the grouping
output but the group step itself still needs the temp table, so the flag
remains. The bonus IGNORE INDEX swap converts the 436 ms driving read to a
~140 ms scan: same lesson, third appearance — it compounds everywhere the
status filter drives a big read.

---

## 4.5 ⌨ Deep pagination: OFFSET vs keyset

The orders admin paginates `ORDER BY id`, 20 per page. A crawler just
requested page 50,001.

**Instructions**

- Measure `LIMIT 20 OFFSET 1000000`.
- Measure the keyset equivalent: `WHERE id > 1000000 … LIMIT 20`.
- Say precisely what the OFFSET version did with the first million rows.

**You should observe:** OFFSET: ~67 ms — the plan shows `Index scan` that
walked **1,000,020** entries and threw away 1,000,000
(`Limit/Offset: 20/1000000`). Keyset: 0.045 ms — a range seek straight to
entry 1,000,001. 1,500× at this depth, and OFFSET keeps degrading linearly
while keyset stays flat. API design is query design.

---

## 4.6 ❓ When do you stop tuning?

A dashboard ticket says "must render < 2 s". Your latest version runs in
1.1 s. You can see two more optimizations worth maybe 0.4 s combined — one
adds a four-column covering index, the other a join hint. Do you take them?

<details><summary>Answer</summary>

No — ship it. The requirement is met with margin; each further change adds
write cost (index maintenance on every INSERT), fragility (a hint frozen
against today's optimizer), and review surface, for latency nobody asked
for. *Write the two ideas in the ticket* for the day the requirement
tightens. Tuning without a stop condition is how databases accumulate 40
indexes and 200 hints nobody dares remove. (If the 1.1 s were p50 with a
4 s p99 — different conversation: requirements are distributions, not
averages.) You'll face exactly this decision, with exactly these numbers,
at the end of the capstone.
</details>

---

# The capstone — ticket DD-4187

Read [capstone/ticket.md](../../capstone/ticket.md), then work 4.8 → 4.13.
The rules from lesson 4.1 are in force: **baseline, save the result, one
change per step, verify identity every time.**

## 4.8 ⌨ Step 1: reproduce and baseline

**Instructions**

- Run `capstone/dashboard_v0.sql` — but *bounded*: add
  `/*+ MAX_EXECUTION_TIME(600000) */` after `SELECT` so MySQL kills it at
  10 minutes for you. (If you forget: find it with
  `SHOW PROCESSLIST` and `KILL <id>` — also a skill.)
- While it "runs", in a second terminal: `EXPLAIN` it and list every sin
  you can see without any measurement.
- Record the baseline honestly: **"did not complete; aborted at 10 min."**

**You should observe:** the query does not finish. We killed ours after
**21 minutes**. That's the baseline — a bound, not a number, and it's still
a measurement. The five sins visible in the EXPLAIN: `DATE()` around every
date column; the 3M-row `order_items` join with no index on `order_id`;
item-grain aggregation forcing `COUNT(DISTINCT)`; a correlated top-category
subquery re-running per country; `NOT IN` over a million payments.

One problem: the identity oracle. You can't save the output of a query
that never returns. The fix: your first steps must be *provably* equivalent
(no diff needed — equivalence holds by definition), and the first version
that actually finishes becomes the oracle for every risky rewrite after it.

## 4.9 ⌨ Step 2: make the dates sargable

**Instructions**

- v0 → v1: replace both `DATE(order_date) >= '2025-05-29'` with a bare-
  column range (chapter 2.9's rewrite). *Nothing else.* This edit is
  equivalent **by definition** — `DATE(x) >= 'd'` ⟺ `x >= 'd 00:00:00'`
  for a date literal — so no diff is needed (or possible yet).
- Run it, still bounded by `MAX_EXECUTION_TIME(600000)`.
- Whatever happens, `EXPLAIN` it and compare access paths against v0's plan.

**You should observe:** humility. v1 **still doesn't finish** — the
10-minute cap kills it. But the plan *did* improve: the outer orders read
is now a range on `idx_orders_date_status_total` instead of a full scan.
The fix was correct and necessary — just not *sufficient*, because the
dominant cost was never the date filter: it's the 3M-row `order_items`
join with no index on `order_id`, re-executed by the correlated subquery
per country. A real tuning session hits this moment constantly; the loop
says: keep the change (the plan is strictly better), read the plan again,
pull the next lever.

## 4.10 ⌨ Step 3: the index the join deserves

**Instructions**

- Create `idx_items_order` on `order_items(order_id)`.
- Re-run v1's text *unchanged* — a pure index effect, measured in
  isolation.
- It finishes now. Save the 17-row output as your **oracle**
  (`/tmp/v2.txt`) and explain why it's trustworthy even though v0 never
  returned. Then read the plan: where do the remaining seconds live?

**You should observe:** **~8.9 s** — from un-finishable to measurable with
one `CREATE INDEX` (~4 s to build). The oracle is sound because every step
so far was *provably* equivalent: an index can't change results, and the
date rewrite is equivalence by definition. In the plan, the outer
aggregation costs ~1 s; the other ~7.8 s is the correlated subquery — 17
executions × ~460 ms. The next lever names itself.

## 4.11 ⌨ Step 4: kill the correlated subquery

**Instructions**

- v1 → v3: compute all countries' top categories in ONE pass — a CTE that
  groups `(ship_country, category)` and takes `ROW_NUMBER() … = 1` per
  country — and join it. (Starter has the skeleton.)
- Run, time, diff against `/tmp/v2.txt`.

**You should observe:** **~1.6 s** — 5.4×, the biggest single win of the
session: seventeen ~460 ms subquery executions became one grouped pass.
Diff clean, including every per-country winner. (Tie-break caveat: on a
revenue *tie*, `LIMIT 1` and `ROW_NUMBER()` could pick different
categories. This data has no ties; production code should add the same
explicit tie-break to both.)

## 4.12 ⌨ Step 5: NOT IN → NOT EXISTS

**Instructions**

- v3 → v4: swap the refund exclusion to `NOT EXISTS` probing
  `idx_payments_order`.
- Run, time, diff. Then compare the two `EXPLAIN ANALYZE` outputs
  line-by-line. What changed?

**You should observe:** **~1.6 s — nothing changed. Same plan, same
time.** MySQL had already transformed the `NOT IN` into the identical
index-probing antijoin, because `payments.order_id` is declared NOT NULL.
Keep the change anyway and say why in the commit: the equivalence is a
courtesy of the *current* schema — on a nullable column (or after
someone's future ALTER), `NOT IN` silently returns zero rows (lab 3.6);
`NOT EXISTS` cannot misfire. Some commits buy speed; this one buys
insurance. A step that "does nothing" is only visible as such because you
changed one thing at a time.

## 4.13 ⌨ Step 6: the grain fix, final review

**Instructions**

- v4 → v5: the outer query's revenue is just `SUM(o.total_cents)` of the
  qualifying orders — delete the outer `order_items` join entirely
  (the top-category CTE keeps its own). Run, time, diff.
- Then earn the last word: `EXPLAIN ANALYZE` v5 and find the two problems
  you already know from chapters 2.12 and 3.12. Fix both (v6 in the steps
  file): `IGNORE INDEX (idx_orders_status)` on both order reads, and
  aggregate the outer orders down to 17 country rows *before* joining the
  17-row CTE.
- Close the loop: verify the ticket's < 2 s requirement, update your
  scorecard, and write the step table (version, change, time) as your
  "commit history". Then — lesson 4.6 — *stop*, and note the un-pulled
  levers in the ticket.

**You should observe:** v5: **~1.3 s**, diff clean — requirement met.
The v5 plan still drives both order reads through the poisonous `status`
index (1.03M entries read, then date-filtered — ~435 ms each) and joins
96,971 order rows to a 17-row CTE. v6 fixes both: **~1.1 s**, diff clean,
comfortable margin. Journey: killed-at-21-minutes → 1.1 s — over 1,000×,
and every single step verified.

Full annotated journey with every measured plan:
[capstone/walkthrough.md](../../capstone/walkthrough.md).

---

## 4.15 ⚙ Deep dive: cost anatomy and the index census *(advanced)*

Two closing instruments for your kit.

**Instructions**

- **Cost anatomy.** Get the JSON plan for the chapter-2 covering query and
  read its `cost_info` blocks:

```sql
EXPLAIN FORMAT=JSON
SELECT SUM(total_cents) FROM orders
WHERE order_date >= '2025-08-01' AND status = 'completed';
```

  Find `query_cost`, and inside the table block: `read_cost`,
  `eval_cost`, `rows_examined_per_scan`. Which component dominates, and
  what does that tell you about where this query's budget goes?

- **The index census.** After a chapter's worth of workload, ask
  performance_schema which indexes have *never* been read:

```sql
SELECT object_name, index_name
FROM sys.schema_unused_indexes
WHERE object_schema = 'urbancart';
```

  Run one query that uses a listed index, re-check, and watch it leave the
  list. What's the caveat before you act on this view in production?

**You should observe:** `query_cost ≈ 14,325` = `read_cost 10,955` (fetch
~67k index entries) + `eval_cost 3,370` (evaluate ~34k surviving rows) —
read dominates, so shrinking what's *read* (covering, tighter range) pays
more than simplifying what's evaluated. The census view is your long-term
weapon against index rot — with the caveat that its counters reset at
server restart: judge over a *representative* window (include the nightly
report, the month-end job), and retire via chapter 2's
invisible-verify-drop ritual, never a blind DROP.

---

## 4.16 ⌨ The PostgreSQL↔MySQL plan-reading card, and when sorts hit disk

Half your team reads PostgreSQL plans. Build the translation card — then
catch a sort spilling to disk, which MySQL (unlike PostgreSQL's
`Sort Method: quicksort Memory: …`) never prints in the plan.

**Instructions**

- Fill in the MySQL side for each PostgreSQL tool, running each one:
  `pg_class`/`pg_stats` (table & column statistics) · `EXPLAIN VERBOSE`
  (output columns) · `cost=startup..total` · `Planning Time` /
  `Execution Time` · `Sort Method … Memory`.
- Then the spill: set `sort_buffer_size` to 32 KB, force a full 1M-row
  filesort (big LIMIT in a derived table — remember, a small LIMIT gets
  the top-N heap and never truly sorts), and read
  `SHOW SESSION STATUS LIKE 'Sort_merge_passes'` before and after.
  Repeat with a 256 MB buffer.

**You should observe (the card):** table stats →
`information_schema.TABLES` + `SHOW INDEX` (cardinality) +
`mysql.innodb_index_stats` (sizes); column stats → histograms in
`information_schema.COLUMN_STATISTICS` (MySQL has no `null_frac`/
`avg_width` catalog — histograms and the JSON plan's
`data_read_per_join` fill that role); VERBOSE → `EXPLAIN FORMAT=JSON`'s
`used_columns`; cost split → JSON `read_cost` + `eval_cost` (4.15);
planning-vs-execution split → not in TREE output — the optimizer trace
(1.14) is where planning cost lives, and scenario A measured it
dominating an 11-second query. And the spill: tiny buffer →
`Sort_merge_passes` jumps **0 → 195** (the sort ran as many small sorted
chunks merged from disk); 256 MB buffer → **+0 passes**. A rising
`Sort_merge_passes` in production is a silent filesort-on-disk signal no
EXPLAIN will show you.
