# Quiz — questions

Answers, explanations, and verify-SQL: [answers.md](answers.md). Tags:
lesson · type. Closed-book first; then verify on your container.

---

## Chapter 0 — Foundations

**Q0.1** · 0.1 · [order]
Put these clauses in the order MySQL *executes* them (not writes them):
`SELECT` · `WHERE` · `FROM/JOIN` · `LIMIT` · `GROUP BY` · `ORDER BY` · `HAVING`

**Q0.2** · 0.1 · [MC]
`SELECT ship_country, COUNT(*) AS orders FROM orders GROUP BY ship_country
WHERE orders > 50000;` fails. Why?
- A) `orders` collides with the table name `orders`
- B) WHERE cannot follow GROUP BY, and even placed correctly it runs before the alias exists
- C) COUNT(*) is not allowed in WHERE, but the alias would work
- D) It doesn't fail — MySQL resolves SELECT aliases everywhere

**Q0.3** · 0.1 · [predict]
`customers` has 300,000 rows; 8,266 of them never ordered. Predict both counts:
`SELECT COUNT(*) FROM customers c INNER JOIN orders o ON o.customer_id = c.id;`
`SELECT COUNT(*) FROM customers c LEFT  JOIN orders o ON o.customer_id = c.id;`

**Q0.4** · 0.1 · [MC]
You port a `FULL OUTER JOIN` query from PostgreSQL to MySQL. What happens?
- A) It works — MySQL 8 added FULL OUTER JOIN
- B) Syntax error — you emulate it with a LEFT JOIN + UNION ALL of the right side's exclusives
- C) MySQL silently treats it as INNER JOIN
- D) It works only with `USING (...)` syntax

**Q0.5** · 0.4 · [MC]
`WHERE total_cents > (SELECT AVG(total_cents) FROM orders)` — how many times
does the inner query run against the 1.2M-row table?
- A) Once per outer row — 1.2 million times
- B) Once per matching row — 543,009 times
- C) Once — it references nothing from the outer query, so it collapses to a constant
- D) Twice — once to plan, once to execute

**Q0.6** · 0.7 · [MC]
`SELECT … FROM tmp_de a JOIN tmp_de b ON …` where `tmp_de` is a
`CREATE TEMPORARY TABLE`. What happens?
- A) Works fine, like any self-join
- B) ERROR 1137 "Can't reopen table" — a temp table can't appear twice in one statement
- C) Works but silently reads stale data in `b`
- D) ERROR 1055 — only_full_group_by

---

## Chapter 1 — How MySQL runs your query

**Q1.1** · 1.1 · [order]
Order the round trip: `Executor` · `Parser` · `Optimizer` · `Client/connection` ·
`Buffer pool check` · `Preprocessor (validation)` · `Result streams back`

**Q1.2** · 1.1 · [MC]
A page request "misses" the buffer pool. What happens?
- A) The query errors — the page must be preloaded
- B) MySQL reads the page from the .ibd data file, caches it, and serves it
- C) The row is reconstructed from the redo log
- D) The query silently returns fewer rows

**Q1.3** · 1.4 · [MC]
EXPLAIN shows `type: ALL, rows: 298422, filtered: 10.00` for a one-row email
lookup. What is `filtered: 10.00`?
- A) 10% of the table is cached
- B) MySQL measured that 10% of rows match
- C) A built-in default guess — no index means no statistics for that column
- D) The confidence level of the row estimate

**Q1.4** · 1.4 · [MC]
On the access-type ladder, which is the *best* set?
- A) `range` and `index`
- B) `const`, `eq_ref`, `ref`
- C) `ALL` with a small LIMIT
- D) `fulltext` always beats `ref`

**Q1.5** · 1.4 · [predict]
After `EXPLAIN SELECT id FROM customers WHERE email = 'x'` (index on email,
`VARCHAR(255)` utf8mb4), what does `key_len` show?

**Q1.6** · 1.8 · [MC]
The team wants to `EXPLAIN ANALYZE` the 20-minute dashboard query on the
production primary "to see the real plan". Best response?
- A) Fine — ANALYZE only estimates, it doesn't execute
- B) ANALYZE executes the statement; it will run for 20 minutes. Cap it or use a replica
- C) Fine, but only during business hours
- D) Use EXPLAIN FORMAT=JSON — it also gives actual times

**Q1.7** · 1.8 · [MC]
Your first run of a query takes 210 ms, the second 46 ms, the third 45 ms.
Which number goes on the scorecard, and why?
- A) 210 ms — worst case matters
- B) ~45 ms — the warm-cache number; the first run paid buffer-pool misses
- C) The average, 100 ms
- D) None — EXPLAIN ANALYZE times are the only valid measurement

**Q1.8** · 1.10 · [MC]
The single best "this query is hiding an index" smell in the slow log is:
- A) Lock time > 0
- B) Query length over 1 KB
- C) rows examined ≫ rows sent
- D) More than two joins

---

## Chapter 2 — Indexes that actually get used

**Q2.1** · 2.1 · [MC]
A secondary index's leaf entry for `INDEX(customer_id)` on `orders` contains:
- A) A pointer to the row's disk page
- B) The customer_id value and a copy of the row's primary key
- C) The full row
- D) The customer_id value and a row offset

**Q2.2** · 2.1 · [predict]
Chapter 1's email lookup scanned 300,000 rows in ~45 ms. After
`CREATE INDEX idx_customers_email ON customers(email)`, roughly what does
`EXPLAIN ANALYZE` report for the same query?

**Q2.3** · 2.4 · [MC]
Index `(customer_id, order_date DESC)`. Which query CANNOT seek it?
- A) `WHERE customer_id = 137`
- B) `WHERE customer_id = 137 AND order_date >= '2025-01-01'`
- C) `WHERE order_date >= '2025-01-01'`
- D) `WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5`

**Q2.4** · 2.4 · [predict]
Same composite — `customer_id` is BIGINT (8 bytes), `order_date` DATETIME
(5 bytes). `EXPLAIN` on `WHERE customer_id = 137` vs
`WHERE customer_id = 137 AND order_date >= '2025-06-01'`: what does `key_len`
show for each, and what does that tell you?

**Q2.5** · 2.4 · [MC]
Composite index design rule for `WHERE a = ? AND b > ?`:
- A) Range column first: `(b, a)` — ranges are more selective
- B) Equality first, range last: `(a, b)` — a range "uses up" the index
- C) Order doesn't matter — B+trees handle both
- D) Two single-column indexes are always merged anyway

**Q2.6** · 2.8 · [MC]
Which WHERE clause can use an index that covers `order_date`?
- A) `WHERE DATE(order_date) = '2025-06-15'`
- B) `WHERE YEAR(order_date) = 2025`
- C) `WHERE order_date >= '2025-06-15' AND order_date < '2025-06-16'`
- D) `WHERE CAST(order_date AS CHAR) LIKE '2025-06-15%'`

**Q2.7** · 2.8 · [predict]
`provider_ref` is a VARCHAR holding digits, indexed.
`WHERE provider_ref = 4000000042` (no quotes) — what plan do you get, and
what does `SHOW WARNINGS` say afterward?

**Q2.8** · 2.8 · [MC]
`status = 'completed'` matches 86% of orders. The optimizer picks the status
index anyway. Measured result?
- A) Index wins — indexes always beat scans
- B) Index path 431 ms vs forced scan 139 ms — a million random two-step lookups lose to one sweep
- C) Identical — the optimizer normalizes both
- D) The index errors on low-cardinality columns

**Q2.9** · 2.8 · [MC]
What does `ANALYZE TABLE orders UPDATE HISTOGRAM ON ship_country` actually make faster?
- A) Lookups on ship_country — histograms act as a lightweight index
- B) Nothing directly — it fixes row *estimates* (119,463 → ~4,898 for 'SG'), which fixes plan choices like join order
- C) Only GROUP BY ship_country
- D) INSERTs, by precomputing statistics

**Q2.10** · 2.8 · [MC]
The safe procedure to remove a redundant index is:
- A) DROP it — restoring is one CREATE INDEX away
- B) ALTER it INVISIBLE, verify plans and timings over a representative window, then DROP
- C) Rename it and wait a week
- D) Truncate the index with OPTIMIZE TABLE

---

## Chapter 3 — Writing SQL the optimizer loves

**Q3.1** · 3.1 · [predict]
`SELECT * FROM orders WHERE order_date >= '2025-08-01'` runs in 69 ms.
Selecting only `id, order_date, status, total_cents` (all in a covering
index): roughly how fast, and why?

**Q3.2** · 3.4 · [MC]
`WHERE customer_id = 137 OR id = 500000` — both columns indexed. Measured 90 ms. Why?
- A) OR always disables all indexes
- B) One B+tree descent can't serve two different columns; it degraded to a 1.2M-entry scan
- C) The optimizer timed out choosing
- D) 500000 is out of the index range

**Q3.3** · 3.4 · [MC]
The mechanical fix for the query above (measured 0.14 ms) is:
- A) `UNION` of the two single-column seeks
- B) Adding a composite index `(customer_id, id)`
- C) Rewriting OR as AND with De Morgan
- D) FORCE INDEX on both

**Q3.4** · 3.4 · [MC]
`x NOT IN (subquery)` returns zero rows though 15 is the right answer.
No error, no warning. The cause:
- A) The subquery exceeded max rows
- B) The subquery's result contains a NULL — `x <> NULL` is UNKNOWN, which poisons every row
- C) NOT IN needs an index on x
- D) Charset mismatch between the two columns

**Q3.5** · 3.4 · [MC]
The three anti-join shapes (find customers who never ordered) all return
8,266. The measured ranking on UrbanCart was:
- A) NOT IN fastest — simplest plan
- B) NOT EXISTS fastest — folklore says so
- C) LEFT JOIN … IS NULL fastest (248 ms), NOT IN 342 ms, NOT EXISTS 377 ms — measure, don't moralize
- D) All identical — same plan for all three

**Q3.6** · 3.8 · [MC]
When does the MySQL 8 optimizer choose a hash join?
- A) Whenever both tables are large
- B) Only when no usable index exists on the join condition — with an index it nested-loops even when that's slower
- C) Whenever you write INNER JOIN
- D) Never — hash joins need a hint

**Q3.7** · 3.8 · [predict]
`orders LEFT JOIN payments p ON p.order_id = o.id AND p.method = 'klarna'`
returned 8,550 rows for the week. Move `p.method = 'klarna'` to WHERE:
what happens to the row count, and why?

**Q3.8** · 3.11 · [MC]
The 4-second monster was "fixed" by pre-aggregating `order_items` in a derived
table, per the textbook. Measured: 4.14 s — *slower*. The real fix (1.75 s) was:
- A) A bigger sort buffer
- B) Realizing the answer lives at order grain — `orders.total_cents` already has it; delete the items join entirely
- C) STRAIGHT_JOIN to fix the order
- D) Partitioning order_items

**Q3.9** · 3.11 · [MC]
"Latest order per customer" three ways, measured: correlated MAX 320 ms,
GROUP BY 97 ms, ROW_NUMBER() window 901 ms. The lesson:
- A) Window functions are always slowest — avoid them
- B) Correlated subqueries are fine anywhere
- C) Shapes aren't good or evil; they're fast or slow on *your* indexes and data — the "modern" shape lost, the "evil" one was fine because each probe hit an index
- D) GROUP BY wins because it skips the WHERE clause

**Q3.10** · 3.11 · [MC]
A CTE referenced twice in one statement is:
- A) Executed twice — inline it to save one run
- B) Materialized once; the plan even prints "(never executed)" on the second reference — measured 0.51 s vs 0.96 s inlined twice
- C) Illegal in MySQL
- D) Automatically converted to a temp table you must drop

---

## Chapter 4 — The tuning workflow

**Q4.1** · 4.1 · [order]
Order the loop: `Change ONE thing` · `Reproduce` · `Verify identity` ·
`Measure (and save the result)` · `Read the plan` · `Stop on purpose`

**Q4.2** · 4.1 · [MC]
In an EXPLAIN ANALYZE tree, a node reads
`(actual time=0.0007..0.0007 rows=1 loops=1030000)`. Its real cost is:
- A) Negligible — 0.7 µs is nothing
- B) ~0.7 s — time × loops; the innocent-looking line is the bill
- C) Unknown — loops don't affect cost
- D) 1030000 ms

**Q4.3** · 4.1 · [MC]
Your rewrite made the query 3× faster but returns 17 rows instead of 30.
- A) Ship it — fewer rows is often fine
- B) Revert or fix — a query that got fast by getting wrong is a production incident with good latency
- C) Add DISTINCT to compensate
- D) Compare only the totals

**Q4.4** · 4.3 · [MC]
`Using temporary; Using filesort` appears in a plan that groups 1.03M rows
into 30 and sorts them. The expensive part is:
- A) The filesort — sorts are always the bottleneck
- B) The temporary table — always spills to disk
- C) Neither necessarily — both handle 30 rows here; the join feeding them was the bill. Read time × loops, then judge
- D) Both — the flags alone mean the query must be rewritten

**Q4.5** · 4.4 · [predict]
`ORDER BY id LIMIT 20 OFFSET 1000000` measured 67 ms.
`WHERE id > 1000000 ORDER BY id LIMIT 20` measured 0.045 ms.
What does OFFSET actually do, and what's the keyset trade-off?

**Q4.6** · 4.4 · [MC]
Rules of engagement for optimizer hints (`IGNORE INDEX`, `/*+ ... */`):
- A) Never use them — the optimizer is always right
- B) Use freely — they're just suggestions
- C) Hint only what you've measured, comment the dated benchmark next to it, re-test on upgrades — a hint is a bet against the optimizer frozen in time
- D) Only in development, never production

**Q4.7** · 4.7 · [predict]
A query can't finish; you must record a baseline without babysitting a
terminal. What statement pattern do you use, and what exact error confirms
it worked?

**Q4.8** · 4.14 · [MC]
The dashboard hit 1.14 s against a < 2 s requirement. Three more optimization
ideas are on the table. You:
- A) Keep going — faster is always better
- B) Stop on purpose — requirement met; further changes add write cost, fragility, and review surface for no required benefit
- C) Try them but don't measure
- D) Add them as invisible indexes "just in case"
