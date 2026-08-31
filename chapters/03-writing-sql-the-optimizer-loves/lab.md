# Chapter 3 — Lab
### Writing SQL the Optimizer Loves

Starter SQL: [lab_starter.sql](lab_starter.sql) · Solutions:
[solutions.sql](solutions.sql). Assumes chapter 2's end state
(`idx_customers_email`, `idx_orders_customer_date`,
`idx_orders_date_status_total`, `idx_orders_status`,
`idx_payments_provider_ref`).

---

## 3.2 ❓ Order-of-operations concept check

1. Why does `SELECT total_cents/100 AS eur … WHERE eur > 500` fail, while
   `… ORDER BY eur` works?
2. Two queries: filtering `status = 'completed'` in `WHERE`, vs keeping all
   rows and filtering `HAVING status = 'completed'` after
   `GROUP BY status, …`. Same result — which is cheaper and why?
3. Does `LIMIT 10` make an unindexed `ORDER BY` cheap?

<details><summary>Answers</summary>

1. WHERE runs *before* SELECT, so the alias doesn't exist yet; ORDER BY runs
   *after*, so it does.
2. WHERE — it removes rows before grouping; HAVING carries every row through
   the aggregate first. HAVING is for conditions on *aggregates*.
3. No — the sort still consumes every matching row; LIMIT trims output, not
   work. Only an index that already delivers the order turns LIMIT into an
   early exit.
</details>

---

## 3.3 ⌨ Project late: the true cost of SELECT *

The nightly export pulls "orders since August 1st".

**Instructions**

- `EXPLAIN ANALYZE` the export as `SELECT *`.
- Re-run selecting only `id, order_date, status, total_cents`.
- Compare times and find the word that appears in the second plan only.

**You should observe:** ~69 ms vs ~2.9 ms for the same 33,189 rows — 23×.
The trimmed query says `Covering index range scan`: every requested column
lives in `idx_orders_date_status_total`, so the table is never visited.
`SELECT *` forced 33k row fetches for columns the export throws away.

---

## 3.5 ⌨ OR vs IN vs UNION

**Instructions**

- Count orders for the three customers `137, 42007, 250999` using `IN`.
- Count orders `WHERE customer_id = 137 OR id = 500000`. Compare plans.
- Rewrite the OR as a `UNION` of two seeks and measure again.

**You should observe:** `IN` on one column = multi-range seek, 0.06 ms.
The cross-column OR collapses to a 1.2M-entry index scan, ~90 ms — one
B+tree can't serve two columns. The UNION rewrite runs both seeks + dedup
in 0.14 ms (650×). Bonus: add `OR coupon_code = 'SAVE7'` (unindexed) to see
the whole predicate fall back to a full table scan (~81 ms).

---

## 3.6 ⌨ The NOT IN null bomb

Marketing: "which coupon codes were never used on a cancelled order placed
on 2025-06-15?" (Right answer: 15 codes.)

**Instructions**

- Run the `NOT IN` version as given in the starter. Count the rows.
- Fix it two ways: (a) `IS NOT NULL` inside the subquery, (b) `NOT EXISTS`.
- Explain to your rubber duck *why* version one returned what it did.

**You should observe:** the naive query returns **0 rows** — no error,
no warning. ~92% of orders have `coupon_code NULL`, one NULL reaches the
`NOT IN` list, and `<> NULL` is unknown for every row. Both fixes return
15\. Grep your codebase for `NOT IN (SELECT` — this bug ships constantly.

---

## 3.7 ⌨ Customers who never ordered: three anti-join shapes

**Instructions**

- Count customers with zero orders three ways: `LEFT JOIN … IS NULL`,
  `NOT EXISTS`, `NOT IN`.
- Confirm all three agree, then rank them by measured time and inspect what
  each plan built.

**You should observe:** all return **8,266**. Measured: LEFT JOIN 248 ms
(pure antijoin, probes the composite index per customer); NOT EXISTS 377 ms
and NOT IN 342 ms (both materialize a 292k-row dedup table of customer ids
first). Folklore says "never LEFT JOIN for anti-joins" — your data just
voted otherwise. (NOT IN is only safe here because `customer_id` is NOT
NULL — see 3.6.)

---

## 3.9 ⌨ Watching a hash join happen

**Instructions**

- `EXPLAIN ANALYZE` revenue by product category (items ⨝ products).
  Note the algorithm and total time.
- Force the alternative with `IGNORE INDEX (PRIMARY)` on products and
  re-measure. Find `Inner hash join` in the plan.
- Then the everyday case: payments for orders since Aug 20 — measure, add
  `idx_payments_order`, measure again.

**You should observe:** optimizer's nested loop = 1.74 s (3M PK descents);
forced hash join = 0.74 s (scan 5k + scan 3M, one pass each). The optimizer
won't choose hash while an index exists — knowing better is *your* job.
Payments join: 541 ms driving from all 1.07M payments (no index on the join
key) → 25 ms after `CREATE INDEX idx_payments_order ON payments(order_id)`,
driving from 10k recent orders. Big×big → hash; thin-slice → indexed nested
loop.

---

## 3.10 ⌨ Filter placement: ON vs WHERE

For orders placed Aug 1–7, list them with their Klarna payment if any.

**Instructions**

- Version A: `LEFT JOIN payments p ON p.order_id = o.id AND p.method = 'klarna'`.
- Version B: same join, but `AND p.method = 'klarna'` moved to `WHERE`.
- Count rows from each. Which one still contains every order?

**You should observe:** A → 8,550 rows (all orders that week; payment
columns NULL unless Klarna). B → 1,553 rows — the WHERE filter on the
right table's column discarded the NULL-extended rows, silently turning
LEFT into INNER. On an INNER join, by contrast, ON vs WHERE placement is
free — verify with two EXPLAINs if you don't believe it.

---

## 3.12 ⌨ Aggregate at the right grain: the monster falls

Scorecard Q4 is still ~4 s. Fix it — but first, learn why the textbook fix
fails.

**Instructions**

- Attempt 1: pre-aggregate `order_items` per order in a derived table, join
  that. Measure. (Prepare for disappointment.)
- Attempt 2: realize the answer lives at *order* grain and
  `orders.total_cents` already holds each order's total. Rewrite with no
  items join at all. Verify the results match the original monster
  row-for-row, then measure.
- Update the scorecard.

**You should observe:** attempt 1: **4.14 s — worse**. Grouping 3M rows
into a 1.2M-row temp table *is* the cost; nothing shrank. Attempt 2:
**1.75 s**, identical output, and `COUNT(DISTINCT o.id)` became `COUNT(*)`
because the fan-out is gone. Add `IGNORE INDEX (idx_orders_status)`
(chapter 2's skew lesson) → **1.47 s**. From 4.0 s by deleting a join:
the fastest work is work you don't do. Chapter 4 pushes this further.

---

## 3.13 ⌨ Correlated subquery vs GROUP BY vs window

Latest order date per customer — three ways.

**Instructions**

- Shape A: correlated `(SELECT MAX(order_date) … WHERE o.customer_id = c.id)`
  projected per customer.
- Shape B: `SELECT customer_id, MAX(order_date) FROM orders GROUP BY customer_id`.
- Shape C: `ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC)`
  filtered to `rn = 1`.
- Measure all three; in B's plan find the phrase `skip scan for grouping`.

**You should observe:** A ≈ 320 ms (300k subqueries — each a 1 µs covering-
index dip; only viable *because* of `idx_orders_customer_date`). B ≈
**97 ms** — a loose index scan that jumps between customers reading ~1 entry
each. C ≈ 900 ms — sorts and materializes all 1.2M rows. The trendy shape
lost; the indexed boring shape won. Also note A returns 300k rows (NULL for
never-ordered customers), B and C return 291,734 — *shapes can differ in
semantics, not just speed*.

---

## 3.14 ⌨ One CTE, used twice

Month-over-month revenue growth needs monthly revenue joined to itself
shifted by one month.

**Instructions**

- Build `WITH monthly AS (…GROUP BY EXTRACT(YEAR_MONTH FROM order_date)…)`
  and self-join `monthly a LEFT JOIN monthly b ON b.ym = PERIOD_ADD(a.ym, -1)`.
- Compare against the same query written with two identical inline derived
  tables.
- In the CTE plan, find the second `Materialize CTE` node and read the two
  words after it.

**You should observe:** CTE 0.51 s, inline 0.96 s. The CTE's second
reference says `(never executed)` — materialized once, read twice. The
inline version aggregated 1.03M orders twice. When an expensive
intermediate is used more than once, a CTE is a *performance* tool, not
just style.

**Scorecard after chapter 3 (measured):**

| # | Query | Plan | Time |
|---|---|---|---|
| Q1–Q3 | unchanged from ch. 2 | | 0.009 / 0.4 / ~1 ms |
| Q4 | revenue by region | order-grain join, no items | **1.47 s** (was 4.0 s) |

---

## 3.15 ⚙ Deep dive: what IN really compiles to *(advanced)*

You've been told "IN-subqueries become semijoins". Stop being told —
toggle the transform off and watch the plan change shape.

**Instructions**

- Plan a count of customers with a refunded order using an IN-subquery:

```sql
EXPLAIN FORMAT=TREE
SELECT COUNT(*) FROM customers c
WHERE c.id IN (SELECT o.customer_id FROM orders o WHERE o.status = 'refunded');
```

- Identify the strategy in the plan. Then disable the transform and re-plan:

```sql
SET optimizer_switch = 'semijoin=off';
-- same EXPLAIN
SET optimizer_switch = 'semijoin=on';
```

- Name the two shapes, and say which side "drives" in each.

**You should observe:** with semijoin ON, the plan reads
`Materialize with deduplication` — MySQL builds the distinct set of
refunding customers (~70k estimated) once, then joins it to `customers`
via PK: the subquery became a **join**, free to be reordered and
optimized like any join. With semijoin OFF you get the pre-5.6 shape:
scan all 298k customers and, per row, probe an `<in_optimizer>`
materialized subquery. Same answer, different algebra — and now you know
what the optimizer is allowed to do to your subqueries, and what it looked
like when it couldn't.

---

## 3.16 ⚙ Deep dive: merge vs materialize, made visible *(advanced)*

Lesson 3.11 said derived tables are either *merged* into the outer query
or *materialized* into a temp table. Prove both happen, and see the cost
of the wrong one.

**Instructions**

- Plan this (deliberately silly) derived-table query, then disable merging
  and plan it again:

```sql
EXPLAIN SELECT * FROM (SELECT id, status FROM orders WHERE customer_id = 137) d
WHERE d.status = 'completed';

SET optimizer_switch = 'derived_merge=off';
-- same EXPLAIN
SET optimizer_switch = 'derived_merge=on';
```

- In each output: how many plan rows? Where did `d` go in the first one?

**You should observe:** merged (default): **one** plan row — `d` has
vanished; MySQL rewrote your query to
`WHERE customer_id = 137 AND status = 'completed'` and served both filters
from the composite index (`ref`, 243 rows). Unmerged: **two** plan rows —
a `<derived2>` temp table is built (243 rows), then scanned with the
status filter applied after. On this toy query the tax is small; on the
capstone's CTE it's the difference between one pass and re-running an
aggregation. Merging is why "I'll clean it up with a derived table" is
usually free — and `EXPLAIN` is how you check the optimizer agreed.

---

## 3.17 ⌨ GROUP BY discipline, and what DISTINCT really costs

**Instructions**

- Run `SELECT ship_country, status, COUNT(*) FROM orders GROUP BY
  ship_country;` — read the full error aloud.
- Explain why MySQL refuses (which status would each group even show?),
  and what `ONLY_FULL_GROUP_BY` is.
- Compare `SELECT DISTINCT status FROM orders` with
  `SELECT status FROM orders GROUP BY status` — plans and times.
- Then measure DISTINCT with every index ignored. Where did the time go?

**You should observe:** **error 1055** — `status` is neither grouped nor
aggregated, so each `ship_country` group has *many* statuses and MySQL
(under the default `ONLY_FULL_GROUP_BY` mode, 5.7+) refuses to pick one
arbitrarily. It used to! Pre-5.7 MySQL silently returned an
*indeterminate* value — a legendary bug factory; never disable the mode
to "fix" the error. DISTINCT and bare GROUP BY compile to the **same plan
node**: `Covering index skip scan for deduplication`, ~0.7 ms. Without an
index: `Temporary table with deduplication` over 1.2M rows, **159 ms**
(240×) — DISTINCT is real work (pipeline position 6, after SELECT), not a
magic word; indexes are what make it cheap.
