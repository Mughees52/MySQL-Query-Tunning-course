# Chapter 0 — Foundations: Combining Data in MySQL
### Lesson transcripts

> **Rhythm — teach, then do:** lesson 0.1 (slides 1–7) → labs 0.2–0.3 ·
> lesson 0.4 (slides 8–9) → labs 0.5–0.6 · lesson 0.7 (slides 10–11) →
> labs 0.8–0.9. Watch the matching deck slides with each lesson, then
> practice before moving on.

> Animated slide deck: [slides/chapter0-slides.html](../../slides/chapter0-slides.html) — open in a browser, → / ← to navigate.

> **Optional refresher.** Chapters 1–4 assume you're fluent with joins,
> subqueries, CTEs, and temp tables. If you are, skip ahead to chapter 1 —
> the performance story starts there. If you'd like the constructs
> themselves taught first, MySQL-style, this chapter is for you. Timings
> here are measured on the same live container as the rest of the course.

---

## Lesson 0.1 — All about joins, MySQL edition
*(video script, ~6 min)*

A join combines rows from two tables by matching values in related
columns. You'll write thousands of them; the performance chapters of this
course are largely about what joins *cost*. Here we pin down what they
*mean*.

[SLIDE 1: the chapter map — joins · subqueries · CTEs · temp tables]

Four constructs, one organizing idea — scope: a subquery produces one value,
a CTE lives for one statement, a temp table for one session. Keep that
frame; everything in this chapter hangs off it.

[SLIDE 2: how MySQL reads your SELECT]

One more foundation before joins — the one most developers and quite a few
DBAs never learned: **a SELECT is not executed in the order you write it.**
You write SELECT first; MySQL runs it fifth. The real order is FROM →
WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT, and the
slide walks a real query through every stage with measured survivor counts
— measured on our data, not derivable from the query text: 1.2 million
rows into FROM, 1,032,479 past WHERE, 17 groups out of GROUP BY, 7 past
HAVING, 3 after LIMIT. (And note the greyed DISTINCT stage: writing
`SELECT DISTINCT` on this query would be a no-op — GROUP BY already left
one row per country. `DISTINCT` stacked on `GROUP BY` is a common code
smell; if you group, the groups are already unique.) Two things to internalize. First,
*aliases are born at SELECT*: that's why `WHERE orders > 50000` throws
ERROR 1054 — WHERE runs at step 2, before the alias exists — while
`ORDER BY orders` works, because sorting runs after. Second, *rows that
die early cost nothing later*: everything that survives WHERE is carried
through grouping, projection and sorting, so the cheapest row is the one
eliminated first. Chapter 3 turns this pipeline into a full tuning tool;
for now, just keep the order in your head.

[SLIDE 3: a query inside a query — run once, or run per row]

And the second execution rule, for when a query contains another query.
A subquery is a complete SELECT nested inside another, and the only
question that matters for its cost is *when the inner one runs*. Read
what it references. If the inner query touches nothing from the outer one
— like comparing against `(SELECT AVG(total_cents) FROM orders)` — MySQL
computes it first, once, and it collapses to a constant; the plan says so
in plain text: *"subquery in condition; run only once"*. Measured on our
data: the average is 743.82, and 543,009 orders sit above it. But if the
inner query references an outer column — `WHERE o.customer_id = c.id` —
it can't be pre-computed: it re-runs for every outer row, 300,000 times
here, and the plan shows `loops=300000`. Per-probe cost then decides
everything: about a microsecond each on the index chapter 2 builds
(lab 3.13 measures it), and catastrophic without one — the capstone had
to kill a correlated subquery that couldn't finish. Positions and syntax
come in lesson 0.4; keep only the one-look test: inner references nothing
outer → runs once · references an outer column → runs per row.

[SLIDE 4: two tables that belong together]

Our running example, straight from UrbanCart: a few `customers`, and the
`countries` lookup that maps a country code to a name and region. The
customers table stores only the code — `US`, `GB` — because storing the
name and region on every one of 300,000 customers would repeat the same
facts endlessly. Joins are how normalized data comes back together.

[SLIDE 5: INNER JOIN — only the matches]

```sql
SELECT c.full_name, c.country_code, co.country_name, co.region
FROM customers c
INNER JOIN countries co ON co.country_code = c.country_code;
```

`INNER JOIN` keeps a row only when the `ON` condition finds a match on
*both* sides. Every UrbanCart customer's code exists in `countries`, so
nobody disappears here — but a country with no customers (Argentina, say)
contributes nothing. Two spelling notes: `JOIN` alone means `INNER JOIN`;
and when both columns share a name you may write `USING (country_code)` —
same meaning, and the join column appears once instead of twice in
`SELECT *` output.

[SLIDE 6: LEFT JOIN — keep my side, NULL-extend the gaps]

```sql
SELECT co.country_name, c.full_name
FROM countries co
LEFT JOIN customers c ON c.country_code = co.country_code;
```

`LEFT JOIN` keeps **every** row of the left table; where the right side
has no match, its columns come back `NULL`. That NULL is not dirty data —
it's the join *telling you something*: Argentina has no customers. Lab 3.7
turns exactly this into the anti-join pattern (`WHERE c.id IS NULL`).
`RIGHT JOIN` is the mirror image — every right-side row kept. In practice
most teams write everything as LEFT and put the "keep all of these" table
first; you'll rarely meet a RIGHT JOIN in the wild.

The row arithmetic is worth internalizing, measured on our data:
`customers INNER JOIN orders` → **1,200,000** rows (one per order).
`customers LEFT JOIN orders` → **1,208,266** — the extra 8,266 are
customers with zero orders, each appearing once with NULL order columns.
An inner join can also *multiply* rows: one customer × 243 orders = 243
result rows. Joins change row counts; always know which grain you're at
(chapter 3 shows what happens when you don't).

[SLIDE 7: FULL OUTER JOIN — the one MySQL doesn't have]

PostgreSQL and SQL Server offer `FULL OUTER JOIN`: keep everything from
*both* sides, NULL-extending each. **MySQL has no FULL OUTER JOIN** — a
genuine dialect gap you should know before porting queries. The standard
emulation is a union of a LEFT join with the RIGHT side's exclusives:

```sql
SELECT co.country_code, co.country_name, s.ship_country
FROM countries co LEFT JOIN ship_stats s ON s.ship_country = co.country_code
UNION ALL
SELECT NULL, NULL, s.ship_country
FROM ship_stats s LEFT JOIN countries co ON co.country_code = s.ship_country
WHERE co.country_code IS NULL;
```

First arm: everything from the left, matches attached. Second arm: only
the right-side rows that found no partner (the anti-join again). `UNION
ALL`, not `UNION` — the arms can't overlap, so paying for deduplication
buys nothing. You'll measure this in lab 0.3.

---

## Lesson 0.4 — Subqueries and CTEs
*(video script, ~7 min)*

A subquery is a query nested inside another. It can sit in three places —
SELECT, WHERE, or FROM — and each placement means something different.
MySQL 8 also gives us common table expressions. Let's take them in turn,
with the plans that chapter 1 taught you to read.

[SLIDE 8, card 1: subquery in SELECT — one value per row]

```sql
SELECT ship_country,
       ROUND(AVG(total_cents)/100, 2) AS country_avg,
       (SELECT ROUND(AVG(total_cents)/100, 2) FROM orders) AS global_avg
FROM orders
GROUP BY ship_country;
```

A SELECT-position subquery must return a **single value** — here, the
global average order value placed next to each country's average, no join
required. Is that one subquery per output row? Check the plan: MySQL
prints `Select #2 (subquery in projection; run only once)` — it's
uncorrelated (references nothing from the outer query), so it runs once
and the value is reused. A *correlated* subquery — one that mentions outer
columns — runs per row instead: fine on an indexed micro-probe (lab 3.13
measured 300k of them at 1 µs each), catastrophic otherwise (the capstone
killed a per-group one that couldn't finish).

[SLIDE 8, card 2: subquery in WHERE — a dynamic filter]

```sql
SELECT COUNT(*) FROM orders
WHERE total_cents > (SELECT AVG(total_cents) FROM orders);
```

A WHERE-position subquery is a filter whose threshold is *computed at run
time* — no hard-coded magic number that goes stale. Measured: 543,009
orders sit above the mean, and the plan again says `run only once`. With
`IN (SELECT …)` instead of a comparison, you're in semijoin territory —
deep-dive 3.15 toggles that transform off and on so you can watch it.

[SLIDE 8, card 3 + SLIDE 9: subquery in FROM, and CTEs]

A FROM-position subquery — a *derived table* — makes query results act as
a table. MySQL either **merges** it into the outer query or
**materializes** it into a hidden temp table (deep-dive 3.16 makes both
happen on command). Readable, but nesting more than one level deep turns
queries inside-out. Enter the CTE:

```sql
WITH country_rev AS (
  SELECT ship_country, COUNT(*) AS orders, SUM(total_cents) AS rev
  FROM orders WHERE status = 'completed'
  GROUP BY ship_country)
SELECT co.region, SUM(cr.orders), ROUND(SUM(cr.rev)/100, 2) AS revenue
FROM country_rev cr
JOIN countries co ON co.country_code = cr.ship_country
GROUP BY co.region ORDER BY revenue DESC;
```

`WITH` states the building block first, names it, then the main query
reads like a sentence. Measured: ~0.5 s, all of it in the aggregation —
the CTE costs nothing extra over the equivalent derived table. Two
performance facts you already met and will meet again: a CTE referenced
**twice** is materialized **once** (lab 3.14 measured the plan printing
"never executed" on the second reference — 0.51 s vs 0.96 s inline), and
the capstone's step 4 used exactly this shape to replace seventeen
correlated subqueries with one pass.

---

## Lesson 0.7 — Temporary tables
*(video script, ~6 min)*

Subqueries and CTEs live for one statement. Sometimes you want a result
to *stick around* — for the next query, and the one after that. That's a
temporary table.

[SLIDE 10: the temp table lifecycle]

```sql
CREATE TEMPORARY TABLE tmp_de AS
SELECT id, customer_id, status, order_date, total_cents
FROM orders WHERE ship_country = 'DE';

ANALYZE TABLE tmp_de;
```

`CREATE TEMPORARY TABLE … AS SELECT` materializes the query's rows into
real storage with three properties: it's **session-private** (invisible
to every other connection — no name collisions, no permissions dance),
it's **transient** (dropped automatically when your session ends), and
it's **real** (you can index it, ANALYZE it, and query it repeatedly).
Measured: materializing the 119,605 German orders took **0.33 s**; the
grouped report that took 659 ms against the base table takes **27 ms**
against the temp table — and *every further query this session* gets that
discount. One statement's cost, a session's worth of benefit.

Always `ANALYZE TABLE` after filling a temp table you'll query more than
trivially: it refreshes the statistics the optimizer plans from — the
same statistics machinery from chapters 1 and 2, and MySQL's counterpart
to the `ANALYZE` habit PostgreSQL folks know.

[SLIDE 11: materializing a view, and the reopen gotcha]

Temp tables truly shine against **views**. A view stores no data — it
stores a *query*, re-run at every reference. Our `v_order_geo` view joins
orders → customers → countries; measured, each aggregate against it costs
**1.6 s**, every single time. Materialize the slice you need once
(2.5 s), and each subsequent query drops to **~0.2 s** — the view's join
runs once instead of N times. Break-even at two uses; everything after is
profit.

One MySQL-specific landmine before the lab — try to use a temp table
twice in the same query:

```sql
SELECT … FROM tmp_de a JOIN tmp_de b ON …;
-- ERROR 1137 (HY000): Can't reopen table: 'a'
```

**A `CREATE TEMPORARY TABLE` table cannot be referenced twice in one
statement.** PostgreSQL allows it; MySQL never has. The workarounds:
create two temp copies, or use a CTE for the double reference (CTEs
materialize into *internal* temp tables, which don't carry the
limitation). Error 1137 has ruined many a porting afternoon — now it
won't ruin yours.

Where does this leave the toolbox? Subquery for a one-shot value or
filter. CTE for readable building blocks and same-statement reuse. Temp
table for cross-statement reuse and materializing expensive views. And
all three obey the same optimizer economics you'll spend chapters 1–4
learning to read. Let's practice.
