# Chapter 3 — Writing SQL the Optimizer Loves
### Lesson transcripts

> **Rhythm — learn, then do:** lesson 3.1 (slides 1–2) → labs 3.2–3.3 ·
> lesson 3.4 (slides 3–4) → labs 3.5–3.7 · lesson 3.8 (slides 5–6) →
> labs 3.9–3.10 · lesson 3.11 (slides 7–8) → labs 3.12–3.14 and 3.17 ·
> deep dives 3.15–3.16.

> Animated slide deck: [slides/chapter3-slides.html](../../slides/chapter3-slides.html) — open in a browser, → / ← to navigate.

> Where we stand: chapter 2's indexes fixed the point lookups. What's left is
> the harder art: queries that are slow because of their *shape*. All numbers
> measured live; several will surprise you — that's the point.

---

## Lesson 3.1 — The logical order of operations
*(video script, ~5 min)*

Write a query and it *reads* top-to-bottom: SELECT, FROM, WHERE… But SQL is
declarative — you describe the result, and the engine assembles it in its
own order.

[SLIDE 1: folklore vs measured — three fights this chapter picks]

Three pieces of received wisdom die in this chapter, each killed by a
measurement. Keep them in mind as we go; each gets its moment. First, the
machinery that decides who wins: the *logical* order every SQL engine honors.

[SLIDE 2: the real pipeline]

```
FROM / JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT
```

Why should you care? Three practical consequences.

**One: aliases don't exist yet where you think they do.** `SELECT` runs
sixth. That's why `WHERE revenue > 100` fails when `revenue` is a SELECT
alias — WHERE runs *before* SELECT names it — but `ORDER BY revenue` works,
because ORDER BY runs after. Same reason `HAVING` exists at all: it's just
WHERE, but positioned after GROUP BY so it can see aggregates.

**Two: volume shrinks left to right — help it shrink early.** Every row that
survives FROM/WHERE is carried through grouping, projection, sorting. The
cheapest row is the one eliminated first. Filter conditions belong in WHERE
(or better, an index seek), not in HAVING; work that only decorates output —
formatting, expensive functions — belongs after the volume has collapsed.

A word on the sixth position: `DISTINCT` runs *after* SELECT — it
deduplicates whatever survived projection. It's real work (exercise 3.17
measures 159 ms of temp-table dedup without an index, 0.7 ms with one),
and `SELECT DISTINCT x` compiles to the same plan as `GROUP BY x` — same
operation, different spelling.

**Three: LIMIT is a budget the engine may exploit — if you let it.**
`ORDER BY order_date DESC LIMIT 5` on an index that already delivers that
order reads *five rows* (chapter 2 measured 0.07 ms). The same LIMIT on an
unindexed sort still sorts *everything* first: LIMIT trims the output, not
the work — unless an index makes order and access coincide.

And a word on the most common shape mistake of all: `SELECT *`. It's not
about network bytes (mostly). On our export query — "orders since August" —
`SELECT *` forces MySQL to visit the table for every matching row: 69 ms.
Selecting just the four columns the report uses lets the *covering* index
answer alone: 2.9 ms. Same rows, 23× — because the columns you *didn't* ask
for were the expensive ones. Project late, and project little.

Exercises: a concept check on the pipeline, then measure `SELECT *` yourself.

---

## Lesson 3.4 — Filter shapes: OR, IN, UNION, and friends
*(video script, ~7 min)*

Two WHERE clauses can be logically identical and differ by 600× in cost.
Filters have *shapes*, and the optimizer handles some shapes much better
than others.

[SLIDE 3: IN — the good shape]

**`IN` on one column is a native index shape.** `customer_id IN (137, 42007,
250999)` compiles to three range seeks on the composite index — measured,
0.06 ms for 249 rows. Use it freely (thousands of literals are fine; the
optimizer just sorts and seeks).

[SLIDE 3, continued: OR across columns]

**`OR` across *different* columns is where plans die.** Watch:

```sql
WHERE customer_id = 137 OR id = 500000
```

Both columns are indexed! But one B+tree descent can't serve two different
columns. Measured: MySQL fell back to scanning 1.2M index entries — 90 ms.
When both sides are indexed and *selective*, the rewrite is mechanical:

```sql
SELECT id FROM orders WHERE customer_id = 137
UNION
SELECT id FROM orders WHERE id = 500000;
```

Two clean seeks plus a dedup: 0.14 ms. 650× for a copy-paste. (MySQL *can*
sometimes do this itself — look for `index_merge` in a plan — but it's
conservative about it; when it doesn't, UNION is your lever. Note `UNION`,
not `UNION ALL`, to preserve OR's dedup semantics if a row can match both
arms.) And if either side of an OR touches an *unindexed* column, the whole
predicate is scan-shaped no matter what else is indexed — measured on
`customer_id = 137 OR coupon_code = 'SAVE7'`: full scan, 81 ms.

[SLIDE 4: the NOT IN null bomb]

**Negation has a landmine.** Marketing asks: "which coupon codes were never
used on a cancelled order on June 15th?" The intuitive query:

```sql
... WHERE coupon_code NOT IN (SELECT coupon_code FROM orders
                              WHERE status = 'cancelled' AND <that day>)
```

returns **zero rows**. Not an error — just silently nothing, though 15 codes
is the right answer. Why: `NOT IN (a, b, NULL)` expands to
`x <> a AND x <> b AND x <> NULL`, and `x <> NULL` is *unknown* — which
poisons every row's predicate to unknown, which WHERE treats as false. One
NULL in the subquery's output and NOT IN returns nothing, forever, quietly.
Two fixes: filter `IS NOT NULL` inside the subquery, or — the shape that can
*never* misfire and usually plans better — `NOT EXISTS` with a correlated
equality. Interviews love this one; production data loves it more.

In the exercises you'll also race the three classic **anti-join** shapes
(find the 8,266 customers who never ordered): `LEFT JOIN … IS NULL`,
`NOT EXISTS`, `NOT IN`. Same answer, three different plans — and on our
data the old-school LEFT JOIN wins. Measure before you believe folklore.

---

## Lesson 3.8 — Joins under the hood: nested loops and hash joins
*(video script, ~7 min)*

Every join MySQL executes is one of two algorithms. Knowing which you're
getting — and which you *should* be getting — is half of join tuning.

[SLIDE 5: nested loop vs hash join]

**Nested loop:** take each row from the *driving* table, look up matches in
the other. Cost ≈ driving rows × cost per lookup. With an index on the far
side, per-lookup is a tree descent — this is the plan you've seen all
course: `Single-row index lookup on … using PRIMARY`. Brilliant when the
driving side is small. Fatal when it isn't: chapter 1's monster did **three
million** PK lookups.

**Hash join** (MySQL 8.0.18+): scan the smaller input once, build a hash
table in memory; scan the bigger input once, probe. Cost ≈ read both sides
once. No index needed — it thrives exactly where nested loop drowns: big ×
big equi-joins.

[SLIDE 5, continued: who picks, and when they're wrong]

Here's the 8.x quirk you must know: **the optimizer only reaches for hash
join when no usable index exists.** Give it an index and it *will* nested-
loop — even when that's slower. Measured, revenue by category, 3M items
joined to 5k products:

- Optimizer's choice (nested loop via product PK): **1.74 s** — 3M descents.
- Hash join, forced with `IGNORE INDEX (PRIMARY)`: **0.74 s** — read 5k,
  read 3M, done.

2.4× faster *against* the optimizer's judgment. The heuristic to carry:
joining a **large fraction** of both tables → hash join territory; joining a
**thin slice** to anything → nested loop with an index. When the optimizer
gets it backwards, hints exist (`IGNORE INDEX`, or `/*+ NO_INDEX() */`,
`HASH_JOIN` hints in newer versions) — chapter 4 covers when hinting is
justified and when it's a time bomb.

But don't over-rotate: for the everyday case — *filtered* driving set,
indexed join key — nested loop is unbeatable. "Payments for orders since
Aug 20": with no index on `payments.order_id`, MySQL had to flip the join
and probe from all 1.07M payments: 541 ms. Add `idx_payments_order` and it
drives from 10k recent orders: **25 ms**. Join keys deserve indexes; that
rule survives the hash-join era.

[SLIDE 6: ON vs WHERE]

Last: a semantics trap that looks like a tuning choice. On an **INNER**
join, a filter in `ON` or in `WHERE` is identical — same plan, same rows;
put it where it reads best. On a **LEFT** join they're different queries:
`ON p.method = 'klarna'` keeps *all* orders (payment columns NULL for
non-klarna) — measured 8,550 rows for one week. Moving it to `WHERE`
silently converts your LEFT join to an INNER one: 1,553 rows. Six thousand
rows vanished, no warning. Filter placement on outer joins is correctness
first, performance second.

---

## Lesson 3.11 — Subqueries, derived tables, and CTEs: merge or materialize
*(video script, ~7 min)*

Chapter 1's monster is still on the scorecard: 4 seconds. This lesson we
finally beat it — and learn why the *obvious* fix makes it worse.

[BOARD: merge vs materialize — you make it visible yourself in deep-dive lab 3.16]

When you nest a query — subquery, derived table (`FROM (SELECT …)`), or CTE
(`WITH …`) — MySQL does one of two things. **Merge** it: fold it into the
outer query as if you'd written one big join (no intermediate result ever
exists). Or **materialize** it: run it, store the result in a temp table,
read that. Merging is usually better; materialization is the tool you reach
for *deliberately* when an expensive intermediate is reused. `EXPLAIN
FORMAT=TREE` shows materialization explicitly — look for `Materialize`.

[SLIDE 7: aggregate at the right grain]

The monster joins `order_items` (3M) up to orders, customers, countries,
then aggregates — carrying item-grain rows through the whole pipeline and
paying `COUNT(DISTINCT o.id)` to undo the fan-out. Textbook advice says
"aggregate before joining", so attempt one: pre-group items per order in a
derived table, then join. Measured: **4.14 s — slower than the original.**
Grouping 3M rows into a 1.2M-row temp table is itself the expensive step;
we shrank nothing. The textbook forgot to say *shrink*.

The real insight is about **grain**: the query's answer lives at order
grain, and orders *already carries* `total_cents` at that grain. The items
join was never needed:

```sql
SELECT co.region, COUNT(*) AS orders, ROUND(SUM(o.total_cents)/100, 2) AS revenue
FROM orders o
JOIN customers c  ON c.id = o.customer_id
JOIN countries co ON co.country_code = c.country_code
WHERE o.status = 'completed'
GROUP BY co.region ORDER BY revenue DESC;
```

**1.75 s**, byte-identical results — and the `COUNT(DISTINCT)` became a
plain `COUNT(*)` because nothing fans out anymore. (Bonus, from chapter 2's
skew lesson: that plan drives through the poisonous `status` index;
`IGNORE INDEX (idx_orders_status)` → **1.47 s**.) 4.0 → 1.5 seconds by
deleting a join. The fastest work is work you don't do.

[SLIDE 8: three shapes race — measure, don't moralize]

"Never use correlated subqueries", says the internet. Measured — latest
order per customer, three shapes:

| shape | plan | time |
|---|---|---|
| correlated `MAX` per customer | 300k index dips, 1 µs each | 320 ms |
| plain `GROUP BY customer_id` | loose index **skip scan** | **97 ms** |
| `ROW_NUMBER()` window | sort all 1.2M, materialize | 901 ms |

The fashionable window function came *last*; the humble GROUP BY rode the
composite index to a 10× win; and the "evil" correlated subquery was fine —
*because chapter 2's index makes each probe a microsecond*. Shapes aren't
good or evil; they're fast or slow **on your indexes, on your data**.

[SLIDE 8, footer: one CTE, used twice]

Finally, the one place CTEs are a *performance* feature, not just pretty:
reference a CTE **twice** and MySQL materializes it **once**. Month-over-
month revenue joins `monthly` to itself: CTE version 0.51 s — and the plan
literally prints `Materialize CTE monthly … (never executed)` on the second
reference. The same query with two inline derived tables aggregates the
orders table twice: 0.96 s. Compute once, read twice.

Exercises, then chapter 4 — where a ticket lands and everything you've
learned runs as one workflow.
