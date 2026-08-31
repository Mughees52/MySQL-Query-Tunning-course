# Chapter 0 — Lab
### Foundations: Combining Data in MySQL

Optional refresher — skip to chapter 1 if joins, subqueries, CTEs and temp
tables are already second nature. Starter SQL:
[lab_starter.sql](lab_starter.sql) · solutions with measured output:
[solutions.sql](solutions.sql). Blanks are `___`.

---

## 0.2 ⌨ Join-type arithmetic

Joins change row counts. Prove you can predict how.

**Instructions**

- Count the rows of `customers INNER JOIN orders` on the customer key.
- Count the rows of `customers LEFT JOIN orders`.
- Before running the second one: predict the difference, and say what each
  extra row *is*.
- Then flip the lens: list the countries that have **no customers at all**
  (LEFT JOIN from `countries`, filter the NULL side).

**You should observe:** inner = **1,200,000** (one row per order — a
customer with 243 orders appears 243 times: joins multiply). Left =
**1,208,266**; the 8,266 extras are the never-ordered customers, each
NULL-extended. The country list returns **5 rows** — Argentina, Belgium,
Greece, Pakistan, Saudi Arabia — real answers made of NULLs. That
`WHERE … IS NULL` move is the anti-join you'll race three ways in lab 3.7.

---

## 0.3 ⌨ The FULL OUTER JOIN MySQL doesn't have

Compare every country in the lookup against every ship-to country
actually used in `orders` — keeping *both* sides' exclusives.

**Instructions**

- Build `ship_stats` inline (a derived table): distinct `ship_country` +
  order count from `orders`.
- Write the FULL OUTER emulation: `countries LEFT JOIN ship_stats`,
  `UNION ALL`, then `ship_stats`'s exclusives via a right-side anti-join.
- Say why `UNION ALL` (not `UNION`) is correct here.

**You should observe:** 32 rows total — 17 countries with shipments
matched, 15 lookup countries never shipped to (NULL stats side), and 0
right-side exclusives (every ship code exists in the lookup — on this
data). The arms cannot overlap by construction, so `UNION` would pay a
deduplication sort for nothing. If a rogue ship code ever appeared, it
would surface in arm two — which is exactly why analysts run this shape
as a data-quality check.

---

## 0.5 ⌨ Subqueries in three positions

**Instructions**

- SELECT position: per ship-to country, show the country's average order
  value *and* the global average beside it (scalar subquery).
- WHERE position: count orders above the global average — no hard-coded
  threshold.
- In both plans (`EXPLAIN FORMAT=TREE`), find the line that tells you how
  many times the subquery ran.

**You should observe:** both plans print
`Select #2 (subquery … run only once)` — uncorrelated scalar subqueries
execute once, not per row. The WHERE version returns **543,009** orders
above the mean. Rule of thumb: uncorrelated = one execution, cheap;
correlated = per-row execution — fine only when each probe is an indexed
microsecond (3.13), lethal otherwise (the capstone's step 4).

---

## 0.6 ⌨ Your first CTE

Revenue by *ship-to* region: aggregate orders per ship country first,
then join the 17-row result to `countries` and roll up to regions.

**Instructions**

- Write it with `WITH country_rev AS (…)` — completed orders only,
  grouped by `ship_country`.
- Main query: join `country_rev` to `countries`, group by region, order
  by revenue.
- Compare readability against writing the same thing as a FROM-position
  derived table. (Same plan — check if you don't believe it.)

**You should observe:** ~0.5 s, Western Europe on top at ~£2.88M. The CTE
and the derived table produce identical plans here — `WITH` is free; its
job is letting the query read top-to-bottom. (Same-statement *reuse* is
where CTEs also become a performance tool — lab 3.14 measured
materialize-once at 0.51 s vs compute-twice at 0.96 s.)

---

## 0.8 ⌨ Materialize a slow view

`v_order_geo` (created in the starter) is a view over the three-table
orders→customers→countries join. The Germany team hits it all day.

**Instructions**

- Run the regional aggregate through the view twice, timing both — what
  do you notice?
- `CREATE TEMPORARY TABLE tmp_geo AS SELECT … FROM v_order_geo WHERE
  status = 'completed'`, then `ANALYZE TABLE tmp_geo`.
- Run two *different* aggregates against `tmp_geo`, timing each.
- Drop the view when done (the temp table drops itself at session end).

**You should observe:** through the view: **~1.6 s per query, every
query** — a view is a stored *query*, not stored *data*; each reference
re-runs the join. Materializing costs 2.5 s once; the two follow-up
aggregates run in **0.18 s and 0.21 s**. Break-even on the second query,
~8× on every query after. This is the move for slow views, expensive
joins queried repeatedly, and "let me explore this slice" sessions.

---

## 0.9 ⌨ The reopen gotcha, and ANALYZE

**Instructions**

- Create `tmp_de` (German orders, as in the lesson) and `ANALYZE` it.
- Query it once — confirm the speedup over the base table.
- Now try to self-join it (`tmp_de a JOIN tmp_de b ON b.id = a.id`).
  Read the error aloud.
- Fix it the CTE way: put the double reference in a `WITH` block over the
  temp table? No — over the *base* slice, so the CTE materializes
  internally and can be read twice.

**You should observe:** the temp-table report runs in **27 ms** vs 659 ms
on the base table. The self-join fails with
**`ERROR 1137: Can't reopen table`** — MySQL forbids referencing a
`CREATE TEMPORARY TABLE` table twice in one statement (PostgreSQL
doesn't; porting code hits this constantly). Workarounds: two temp
copies, or a CTE (its *internal* materialization has no such limit).
And the habit to keep: **ANALYZE after every meaningful temp-table
fill** — the optimizer plans your next query from those statistics.
