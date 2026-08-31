# Chapter 1 — Lab
### How MySQL Runs Your Query

Work top to bottom. Starter SQL for every exercise is in
[lab_starter.sql](lab_starter.sql); full answers with measured output are in
[solutions.sql](solutions.sql). Blanks to fill are written `___`.

Connect first:

```bash
docker exec -it mysql-tuning-course mysql -uroot -pcourse urbancart
```

---

## 1.2 ⌨ Sizing up the database

Before touching a single query, know your patient. `information_schema.tables`
holds MySQL's bookkeeping about every table: estimated row count, data size,
index size.

**Instructions**

- Query `information_schema.tables` for the `urbancart` schema.
- Return table name, estimated rows, and data + index size in MB.
- Order by size, biggest first.

```sql
SELECT table_name,
       table_rows,
       ROUND((data_length + index_length) / 1024 / 1024, 1) AS size_mb
FROM information_schema.___
WHERE table_schema = '___'
ORDER BY ___ DESC;
```

**You should observe:** `order_items` ~147 MB, `payments` ~85 MB, `orders`
~77 MB, `customers` ~27 MB. `table_rows` is an *estimate* maintained by
InnoDB — it may be a few percent off the true counts. That's your first
taste of "the optimizer works from estimates, not facts."

> 💡 Hint: the view is `information_schema.tables`; sizes come from
> `data_length + index_length`.

---

## 1.3 ⌨ Feel the scan: the customer lookup

The admin panel looks customers up by email. Run it and feel it.

**Instructions**

- Select `id`, `full_name`, `city` for the customer with email
  `amara.dubois150000@example.com`.
- Run it **twice** (rule 1: warm up) and note the second timing the client
  prints.

```sql
SELECT id, full_name, city
FROM customers
WHERE ___ = '___';
```

**You should observe:** one row, in roughly 40–60 ms warm. For one row.
Write that number down — it becomes line 1 of your scorecard in 1.13.

---

## 1.5 ⌨ EXPLAIN the slow lookup

**Instructions**

- Put `EXPLAIN` in front of the 1.3 query.
- Answer for yourself: what is `type`? What is `key`? How many `rows` does
  MySQL expect to examine? What fraction does `filtered` claim survives?

```sql
___ SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';
```

**You should observe:** `type: ALL`, `key: NULL`, `rows:` ≈ 298,000,
`filtered: 10.00`. Translation: "I will read the whole table and I *guess*
one in ten rows matches." Both the plan and the guess are terrible — and
nothing here tells MySQL otherwise. Fixing this is the opening act of
chapter 2.

---

## 1.6 ❓ The access-type ladder

For each scenario, name the `type` you'd expect **on this database as it
stands today** (primary keys only!):

1. `SELECT * FROM orders WHERE id = 4242;`
2. `SELECT * FROM orders WHERE customer_id = 137;`
3. `SELECT * FROM countries;`
4. `SELECT o.*, c.full_name FROM orders o JOIN customers c ON c.id = o.customer_id WHERE o.id BETWEEN 100 AND 200;`
   (one `type` per table)

<details><summary>Answers</summary>

1. `const` — primary key equality, at most one row.
2. `ALL` — no index on `customer_id`, full scan of 1.2M rows.
3. `ALL` — and that's *fine*: 32 rows. Full scan of a tiny table is optimal.
4. `orders`: `range` (PK range scan over ~101 ids) · `customers`: `eq_ref`
   (for each order, one PK lookup). Joins on primary keys are the one thing
   this schema already does fast.
</details>

---

## 1.7 ⌨ Estimates vs reality with EXPLAIN ANALYZE

`orders.status` has heavy skew: 86% `completed`, 1% `failed`. The optimizer
has no idea (no index, no histogram — yet).

**Instructions**

- `EXPLAIN ANALYZE` a count of **failed** orders.
- Find the two numbers that disagree: the optimizer's `rows=` estimate on the
  Filter node vs the `actual … rows=` it produced.

```sql
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE ___ = 'failed';
```

**You should observe:** the filter's *estimate* claims ~10% of 1.2M rows
(≈120k) will match; *actually* 11,826 do — a 10× overestimate, because
without statistics MySQL falls back on a fixed 10% guess for equality on an
unindexed column. File this away: chapter 2's histogram lesson fixes exactly
this number.

---

## 1.9 ⌨ Revenue by country: the monster baseline

Finance runs this every morning: revenue and order count per region,
completed orders only. It joins all four big tables.

**Instructions**

- Complete the joins (`orders → customers → countries`, `orders → order_items`).
- Run with `EXPLAIN ANALYZE`. Find the total runtime and the *bottom-most*
  node — where does the row flood start?

```sql
EXPLAIN ANALYZE
SELECT co.region,
       COUNT(DISTINCT o.id) AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price_cents) / 100, 2) AS revenue
FROM orders o
JOIN customers c    ON c.id = o.___
JOIN countries co   ON co.country_code = c.___
JOIN order_items oi ON oi.___ = o.id
WHERE o.status = 'completed'
GROUP BY co.region
ORDER BY revenue DESC;
```

**You should observe:** ~4 seconds. The plan drives from a full scan of all
3M `order_items`, then does 3M primary-key lookups into `orders`, keeps 2.58M
rows, sorts them, and only then aggregates to 12 rows. **Rows examined: ~9M.
Rows returned: 12.** Keep this query — it is the "before" photo we revisit at
the end of every chapter.

---

## 1.11 ⌨ Reading the slow query log

Good news: your 4-second monster crossed the 0.5 s threshold, so it's already
in the log.

**Instructions**

- Confirm the log is on and find its location (`SHOW VARIABLES`).
- Read the log from your shell (outside mysql) and find the monster's entry.
- In its header lines, find `Rows_examined` and compare with rows returned.

```sql
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';
```

```bash
docker exec mysql-tuning-course sh -c "tail -40 /var/lib/mysql/slow.log"
```

**You should observe:** `Query_time: ~4`, `Rows_sent: 12`,
`Rows_examined:` in the millions. That ratio — millions examined, a dozen
sent — is the signature of a query that needs help.

---

## 1.12 ⌨ Top offenders with the sys schema

**Instructions**

- Query `sys.x$statement_analysis` for `urbancart` SELECTs.
- Return the normalized query, execution count, average latency in seconds,
  and average rows examined; worst latency first, top 5.

```sql
SELECT query,
       exec_count,
       ROUND(avg_latency / 1e12, 2) AS avg_s,
       rows_examined_avg
FROM sys.___
WHERE db = 'urbancart'
ORDER BY ___ DESC
LIMIT 5;
```

**You should observe:** every query you've run this chapter, ranked —
with the monster and the email lookup near the top. Notice how the
normalized text groups repeated runs (`email = ?`). This view is where real
tuning sessions *start*: measure first, then pick the target with the
largest `exec_count × avg_latency`.

> ⚠️ `avg_latency` in the `x$` views is in **picoseconds** — hence `/1e12`.
> The non-`x$` view `sys.statement_analysis` returns it pre-formatted.

---

## 1.13 ⌨ Your baseline scorecard

Create the "before" photo. Copy `baseline_scorecard.md` (next to this file)
and fill in **your** measured numbers for the four queries below. You'll
update the card at the end of every chapter — it's how you'll *prove* your
tuning worked.

| # | Query | Plan summary today | Warm time today |
|---|-------|--------------------|-----------------|
| Q1 | customer by email | `ALL`, ~298k rows examined | ___ ms |
| Q2 | orders of customer 137 | `ALL`, 1.2M rows examined | ___ ms |
| Q3 | failed orders count | `ALL`, 1.2M rows examined | ___ ms |
| Q4 | revenue by region | `ALL` on order_items + 3M PK lookups | ___ s |

Where we're heading — the same table at the end of the course (measured):

| # | Plan | Time |
|---|------|------|
| Q1 | `ref` on `idx_customers_email`, 1 row | 0.009 ms |
| Q2 | `ref` on `idx_orders_customer_date`, 243 rows | 0.4 ms |
| Q3 | covering `ref` on `idx_orders_status` | ~1 ms |
| Q4 | order-grain join, items table deleted from the query | ~1.5 s |

…and the chapter-4 capstone takes a *different* multi-minute dashboard
query to interactive speed using everything above.

---

## 1.14 ⚙ Deep dive: watch the optimizer think *(advanced)*

Everything so far treated the optimizer as a black box that "estimates".
It isn't a black box — MySQL will show you the exact arithmetic.

**Instructions**

- Enable the optimizer trace, run the customer-137 count, then read the
  trace's `rows_estimation` section:

```sql
SET optimizer_trace = 'enabled=on';
SELECT COUNT(*) FROM orders WHERE customer_id = 137;
SELECT SUBSTRING(trace, LOCATE('rows_estimation', trace), 700) AS cost_math
FROM information_schema.optimizer_trace\G
SET optimizer_trace = 'enabled=off';
```

- Find the cost the optimizer assigned to a full table scan, and the row
  count it based that on.
- Then prove the "everything is warm" claim from lesson 1.1: read the two
  buffer-pool counters and compute the miss rate.

```sql
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read%';
```

**You should observe:** the trace prints the decision sheet in JSON:
`"table_scan": {"rows": 1194627, "cost": 120691}` — the *exact* numbers
behind the `EXPLAIN` you read in 1.5, in cost units (not milliseconds!).
Today the sheet is short: with no secondary indexes, the scan runs
unopposed. **Bookmark this exercise and re-run it after chapter 2** — the
same trace will fill with candidate indexes and their costs, and chapter
2's deep dive catches the optimizer making a measurably wrong choice
there, in writing.
The buffer pool counters: `read_requests` in the billions vs `reads`
(actual disk) in the thousands — a hit rate of ~99.999%. Every slow query
you measured this chapter was slow *with the data already in RAM*.
