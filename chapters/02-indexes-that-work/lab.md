# Chapter 2 — Lab
### Indexes That Actually Get Used

Starter SQL: [lab_starter.sql](lab_starter.sql) · Solutions with measured
output: [solutions.sql](solutions.sql). Blanks are `___`. Remember the
rules: warm cache, run twice, change one thing at a time.

---

## 2.2 ⌨ The email index: three orders of magnitude for one statement

Chapter 1, Q1: the email lookup scans 298k rows in ~45 ms. Fix it.

**Instructions**

- Re-measure the baseline (warm) one last time.
- Create `idx_customers_email` on the obvious column.
- Re-run the lookup with `EXPLAIN ANALYZE`. Compare `type`, rows examined,
  and actual time. Update your scorecard.

```sql
CREATE INDEX idx_customers_email ON ___(___);

EXPLAIN ANALYZE
SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';
```

**You should observe:** index build ~1 s. The plan becomes a single
`Index lookup … (actual time≈0.009 ms, rows=1)`. From 45 ms scanning 300k
rows to **9 microseconds** touching 1. That's a ~5000× speedup — the largest
you will ever get per line of SQL, which is why indexing is always step one.

---

## 2.3 ⌨ Reading SHOW INDEX: cardinality and selectivity

**Instructions**

- Run `SHOW INDEX FROM customers` and find `Cardinality` for your new index.
- Divide by the table's row count. What does a ratio ≈ 1 mean?

**You should observe:** cardinality ≈ 298,422 ≈ the row count: every email
distinct — perfect selectivity, the ideal index candidate. Contrast with what
`status` on orders would show (5 distinct / 1.2M ≈ 0). Cardinality is an
estimate from sampling, so don't be alarmed if it's a few percent off.

---

## 2.5 ⌨ A customer's order history, sorted for free

Q2 from your scorecard: customer 137's orders, and the profile page's
"latest 5 orders" widget.

**Instructions**

- First create the *single-column* index and measure both queries.
- Then create the *composite* with `order_date DESC` and re-measure.
- In the second plan, find what disappeared.

```sql
CREATE INDEX idx_orders_customer ON orders(customer_id);

EXPLAIN ANALYZE
SELECT id, status, order_date, total_cents FROM orders WHERE customer_id = 137;

EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5;

CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date ___);

EXPLAIN ANALYZE
SELECT id, order_date, total_cents FROM orders
WHERE customer_id = 137 ORDER BY order_date DESC LIMIT 5;
```

**You should observe:** single-column: history 110 ms → 0.4 ms (ref, 243
rows). But the LIMIT-5 widget still shows a `Sort:` node — it fetches all
243, sorts, keeps 5 (~1.7 ms). Composite: the Sort node is *gone*; the plan
reads 5 index entries and stops (~0.07 ms). The index returns rows already
in the requested order.

---

## 2.6 ❓ Which queries can use idx(a, b, c)?

Given `INDEX (customer_id, order_date, total_cents)` on orders, which
predicates can *seek* (not just scan)?

1. `WHERE customer_id = 137`
2. `WHERE order_date > '2025-01-01'`
3. `WHERE customer_id = 137 AND order_date > '2025-01-01'`
4. `WHERE customer_id = 137 AND total_cents > 50000`
5. `WHERE customer_id = 137 AND order_date > '2025-01-01' AND total_cents > 50000`
6. `WHERE total_cents > 50000`

<details><summary>Answers</summary>

1. ✅ leftmost prefix.
2. ❌ skips the leading column — at best a full *index* scan.
3. ✅ equality on prefix + range on next column: the ideal shape.
4. ⚠️ Seeks on `customer_id` only; `total_cents` is filtered *inside* the
   index entries (index condition), because `order_date` was skipped.
   Better than nothing, worse than shape 3.
5. ⚠️ Seeks on `customer_id = ` + `order_date >` range; the range "uses up"
   the index, `total_cents` is a residual filter. Column order matters:
   equality columns first, the one range last.
6. ❌ no prefix at all.
</details>

---

## 2.7 ⌨ Covering indexes: never touch the table

Finance asks hourly: "total completed revenue since June 1st". No index we
have covers `status` and `total_cents` behind `order_date`… yet.

**Instructions**

- Measure the query as-is.
- Build `idx_orders_date_status_total` on `(order_date, status, total_cents)`.
- Re-measure and find the words `Covering index range scan` in the plan.

```sql
EXPLAIN ANALYZE
SELECT ROUND(SUM(total_cents) / 100, 2) AS revenue
FROM orders
WHERE status = 'completed' AND order_date >= '2025-06-01';

CREATE INDEX idx_orders_date_status_total ON orders(___, ___, ___);
```

**You should observe:** 141 ms full table scan → **14 ms** covering range
scan. Every column the query needs (`order_date` to seek, `status` to
filter, `total_cents` to sum) lives in the index leaf — the 77 MB table is
never opened. Note the column order: the range column first *here* because
it's the only seekable predicate; `status` can't lead since it's the
low-selectivity one (and check: could `(status, order_date, total_cents)`
have been even better for this exact query? Try it later — equality first!
— then decide which serves *more* of UrbanCart's queries).

---

## 2.9 ⌨ The DATE() trap

Ops dashboards count "orders placed on day X" like this:

```sql
SELECT COUNT(*) FROM orders WHERE DATE(order_date) = '2025-06-15';
```

**Instructions**

- `EXPLAIN ANALYZE` it. Note rows scanned and time, and *which* index it
  reads (surprise: it still says an index name — why is it slow anyway?).
- Rewrite as a half-open range on the bare column. Re-measure.

```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders
WHERE order_date >= '___' AND order_date < '___';
```

**You should observe:** the original scans **all 1.2M entries** of a
covering index (a scan is still a scan — `Covering index scan`, 78 ms). The
range version does a `Covering index range scan` over exactly 1,299 entries:
0.14 ms, 550× faster, identical count. Always a half-open interval
(`>= day, < day+1`) — `BETWEEN` with `23:59:59` silently drops the last
second's orders.

---

## 2.10 ⌨ The implicit-cast trap: a number that isn't

A refund script looks up payments by gateway reference:
`WHERE provider_ref = 4000000042`. The column is `VARCHAR`.

**Instructions**

- Index `payments.provider_ref`.
- `EXPLAIN` the unquoted version, then immediately run `SHOW WARNINGS`.
- `EXPLAIN ANALYZE` both versions; compare.

**You should observe:** unquoted: `type: ALL`, ~90 ms, and warning 1739
*"Cannot use ref access on index … due to type or collation conversion"* —
MySQL telling you exactly what went wrong. Quoted `'4000000042'`: 0.009 ms
index lookup. 10,000× for two quote characters. Audit your ORMs: this
happens whenever application types drift from column types.

---

## 2.11 ⌨ LIKE it or not: wildcards and prefixes

**Instructions**

- Count customers whose email starts with `amara.dubois15`.
- Count customers whose email *ends* with `@example.com`.
- Compare the two plans: which one seeks? What does the other do instead?

**You should observe:** the prefix search is a `Covering index range scan`
(141 rows, ~0.05 ms) — MySQL turned `LIKE 'amara.dubois15%'` into a range.
The suffix search cannot seek; it falls back to scanning all 298k index
entries (`type: index`). Note it *still* prefers the index over the table —
the index is smaller and covers the query. A leading wildcard on a
non-covered query would be a full table scan.

---

## 2.12 ⌨ Skewed data: when the index is the slow path

**Instructions**

- Create `idx_orders_status` on orders(status).
- `EXPLAIN` (don't run) `SELECT * … WHERE status = 'completed'` and
  `… WHERE status = 'failed'`. Compare estimated rows.
- Now measure a non-covered aggregate both ways:
  with the index, and with `IGNORE INDEX (idx_orders_status)`.

```sql
EXPLAIN ANALYZE SELECT SUM(total_cents) FROM orders WHERE status = 'completed';
EXPLAIN ANALYZE SELECT SUM(total_cents) FROM orders IGNORE INDEX (idx_orders_status)
WHERE status = 'completed';
```

**You should observe:** the optimizer picks the index for *both* statuses —
and for `'completed'` that's wrong: 431 ms through the index vs 139 ms
forced scan. A million matches means a million random clustered-index
lookups; sequential beats random. Also note the estimate said 597k rows;
reality was 1.03M. For `'failed'` (11.8k rows) the index is a huge win
(~1 ms). Moral: indexes on low-cardinality columns help *rare* values, hurt
*common* ones, and `EXPLAIN ANALYZE` is the referee. (Keep the index —
UrbanCart's alerting queries hunt rare `failed` orders.)

---

## 2.13 ⌨ Histograms: teaching the optimizer about skew

`ship_country` is heavily skewed (30% US … 0.4% SG) and unindexed.

**Instructions**

- `EXPLAIN` a count of Singapore orders; note `filtered` and the row estimate.
- Build a 32-bucket histogram on `ship_country`.
- Re-`EXPLAIN` and compare the estimate to the true count.

```sql
ANALYZE TABLE orders UPDATE ___ ON ship_country WITH ___ BUCKETS;
```

**You should observe:** estimate before: 119,463 rows (`filtered: 10.00` —
the blind default). After: `filtered: 0.41` → ~4,898 rows, vs 4,845 actual.
The query is no faster (still a scan — histograms are not indexes!) but the
*estimate* went from 25× wrong to 1% wrong. In chapter 4 you'll see why
that matters: join order is chosen from exactly these numbers. Use
histograms on skewed, rarely-updated, filter-only columns; re-run ANALYZE
after big data loads (histograms don't auto-update).

---

## 2.14 ⌨ Invisible indexes and dropping dead weight

Exercise 2.5 left `idx_orders_customer` fully shadowed by the composite.
Every INSERT into orders now pays to maintain both.

**Instructions**

- Ask `sys.schema_redundant_indexes` what it thinks of urbancart.
- Make the redundant index `INVISIBLE`; verify customer queries still get a
  good plan (which index serves them now?).
- Drop it. Update your scorecard with chapter-2 numbers for Q1–Q3.

```sql
SELECT table_name, redundant_index_name, dominant_index_name
FROM sys.schema_redundant_indexes WHERE table_schema = 'urbancart';

ALTER TABLE orders ALTER INDEX idx_orders_customer ___;
EXPLAIN SELECT id, status FROM orders WHERE customer_id = 137;
ALTER TABLE orders DROP INDEX idx_orders_customer;
```

**You should observe:** sys names `idx_orders_customer` redundant,
dominated by `idx_orders_customer_date`. Invisible → the EXPLAIN
seamlessly switches to the composite (`ref`, 243 rows) — proof the drop is
safe, gathered *without* the risk of actually dropping. This
invisible-verify-drop ritual is how you retire indexes in production.

**Scorecard after chapter 2 (measured reference):**

| # | Query | Plan | Time |
|---|---|---|---|
| Q1 | customer by email | ref, 1 row | 0.009 ms |
| Q2 | orders of customer 137 | ref, 243 rows | 0.4 ms |
| Q3 | failed orders count | covering ref, 11.8k entries | ~1 ms |
| Q4 | revenue by region | unchanged | ~4 s ← chapter 3's problem |

---

## 2.15 ⚙ Deep dive: catch the optimizer choosing wrong — in writing *(advanced)*

Exercise 2.12 proved the index path for `status='completed'` is 3× slower
than the scan, yet the optimizer picks it. Don't take that on faith — read
its decision sheet.

**Instructions**

- Trace the choice:

```sql
SET optimizer_trace = 'enabled=on', optimizer_trace_max_mem_size = 262144;
EXPLAIN SELECT SUM(total_cents) FROM orders WHERE status = 'completed';
SELECT SUBSTRING(trace, LOCATE('considered_execution_plans', trace), 600) AS decision
FROM information_schema.optimizer_trace\G
SET optimizer_trace = 'enabled=off';
```

- Find: the cost assigned to `ref` on `idx_orders_status`, the cost of the
  rejected covering scan, and the row estimate the ref cost was built on.
- Reconcile with your stopwatch from 2.12. Which input was wrong?

**You should observe:** `ref … rows: 597313, cost: 63409 → chosen: true`,
covering scan `cost: 134392 → "cause": "cost"` (rejected). Two failures
compound: the row estimate is 2× low (truth: 1.03M), and the cost model
prices a million *random* secondary→clustered hops too cheaply relative to
one sequential read. Costs are model units, not milliseconds — when the
trace and the stopwatch disagree, **the stopwatch wins**, and that's
precisely the legitimate use of `IGNORE INDEX`.

---

## 2.16 ⚙ Deep dive: the prefix-index trade, measured *(advanced)*

Standard advice says "index a prefix of long strings to save space". Test
it on `email` before trusting it.

**Instructions**

- First measure what a 12-character prefix is worth:
  `SELECT COUNT(DISTINCT LEFT(email,12)), COUNT(*) FROM customers;`
- Build `idx_customers_email_pfx` on `email(12)`. Compare its
  `SHOW INDEX` cardinality and its size
  (`mysql.innodb_index_stats`, `stat_name='size'`) against the full index.
- `EXPLAIN ANALYZE` the standard lookup forced through the prefix index
  (`USE INDEX`). Then drop it.

**You should observe:** 16,152 distinct 12-char prefixes across 300,000
emails — our emails are `firstname.lastname…`, so prefixes collide badly.
Cardinality ~14k vs ~298k; size 9.5 MB vs 14.6 MB (only 35% saved); and
the lookup fetches **2,754 candidate rows** to deliver 1 — 2.49 ms vs
9 µs, ~275× slower. Verdict for UrbanCart: not worth it. The advice isn't
wrong — it depends on *where the entropy lives* in the string, and now
you know how to measure that before building.
