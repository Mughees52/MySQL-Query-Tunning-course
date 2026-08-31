# Chapter 1 — How MySQL Runs Your Query
### Lesson transcripts

> **Rhythm — teach, then do:** lesson 1.1 (slides 1–3) → labs 1.2–1.3 ·
> lesson 1.4 (slides 4–5) → labs 1.5–1.7 · lesson 1.8 (slides 6, 8) →
> lab 1.9 · lesson 1.10 (slide 7) → labs 1.11–1.13 · deep dive 1.14.

> Animated slide deck: [slides/chapter1-slides.html](../../slides/chapter1-slides.html) — open in a browser, → / ← to navigate.

> Timings in this chapter were measured on the course Docker container
> (MySQL 8.4, 1G buffer pool, Apple-silicon laptop). Your absolute numbers
> will differ; the *ratios* — and the plans — will not.

---

## Lesson 1.1 — Welcome to UrbanCart: the journey of a query
*(video script, ~5 min)*

Welcome to Improving Query Performance in MySQL 8. I'm your instructor, and
for the next four hours you're an engineer at UrbanCart — an online retailer
whose database was built in a hurry and has been slowing down ever since.

[SLIDE 1: schema diagram]

Here's what we've inherited: six tables. `customers` — 300 thousand of them.
`orders` — 1.2 million, each pointing at a customer. `order_items` — three
million rows linking orders to `products`. `payments` — about one million.
And a small `countries` lookup that maps a country code to a region and
continent. About 350 MB of data in all. Not big data — and that's the point.
If queries are slow at this size, no amount of hardware will save you at ten
times the size.

And here's the thing nobody noticed when the schema was written: **other than
the primary keys, there is not a single index in this database.** By the end
of chapter 2 you'll know exactly why that matters and exactly which indexes
to add. But first, you need to understand what MySQL does with a query at
all — because every tuning decision you'll ever make is really a prediction
about this machinery.

[SLIDE 2: query lifecycle — the full round trip, client to client]

When you press Enter, your statement makes a round trip. First the plumbing:
the connection — TCP, authentication, a thread that picks your session up.
Pooled and cheap; it's not our story. Then four things happen.

**One: parsing and validation.** The parser checks your syntax and turns the
text into a tree; the preprocessor then validates it — do these tables and
columns actually exist, are you allowed to read them? Cheap, uninteresting,
nothing to tune.

**Two: optimization.** This is the brain. The optimizer looks at your tree
and asks: what are my options? Which table should I read first? For each
table, do I scan it or use an index? Which join algorithm? It weighs the
options using *statistics* — estimates of how many rows each step will touch
— and picks the plan with the lowest estimated cost. Remember that word,
*estimated*. The optimizer never runs your query to find out; it guesses
from statistics. When the guess is wrong, plans go bad — and in chapter 2
we'll teach it to guess better.

**Three: execution.** The executor walks the chosen plan and pulls rows.

[SLIDE 3: tree descent vs table sweep]

**Four: storage.** The executor doesn't read disk itself — it asks the
storage engine, InnoDB. And InnoDB has one property so important it shapes
this entire course: **the table *is* an index.** InnoDB stores every table
physically sorted by primary key, in a B+tree called the *clustered index*.
Ask for `orders` row with `id = 42` and InnoDB descends a tree three levels
deep and lands on the full row — a handful of page reads. Ask for "all orders
where `customer_id = 137`" and, with no index on `customer_id`, InnoDB has no
tree to descend. It must read *every one of the 1.2 million rows* and check
each. That's a **full table scan**, and it's the villain of chapter 1.

One more piece: InnoDB caches data pages in memory, in the **buffer pool**.
Every page request checks RAM first — a **hit** is served from memory; a
**miss** reads the page from the data file on disk (the `.ibd` file), caches
it, and serves it. Then the matching rows stream back to the client over the
same connection, and the round trip is complete. Our container gives the
pool 1 GB, so after a warm-up the entire dataset lives in RAM — a warm cache
just means "the hit path", which is exactly why we time second runs. Keep
that in mind: every slow query you'll see in this course is slow *with all
data already in memory*. Real production adds disk-read misses on top.

[TERMINAL]

Let's meet the patient. In the exercises you'll size up every table using
`information_schema` and take your first timings. See you in the next lesson,
where we x-ray a query with `EXPLAIN`.

---

## Lesson 1.4 — Your first EXPLAIN
*(video script, ~5 min)*

Support says customer lookups feel sluggish. Here's the query the app runs
when someone types an email into the admin search box:

```sql
SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';
```

It returns one row. How hard can that be? Put `EXPLAIN` in front and MySQL
will show you the plan it *would* use, without running the query:

```sql
EXPLAIN SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';
```

```
type: ALL   possible_keys: NULL   key: NULL   rows: 298422   filtered: 10.00
Extra: Using where
```

[SLIDE 4: the EXPLAIN columns that matter]

Five columns tell you almost everything:

- **type** — the *access method*. `ALL` means full table scan: read
  everything, keep what matches. This is the value you're usually trying to
  get rid of.
- **possible_keys / key** — which indexes *could* serve this query, and which
  one the optimizer picked. `NULL` and `NULL`: there's nothing to pick. The
  only index on `customers` is the primary key, and we're not filtering by id.
- **key_len** — how many *bytes* of the chosen index are actually used.
  Useless today (NULL), priceless in chapter 2: on a composite index it's
  the lie detector that tells you how many of its columns your query really
  engaged. Bookmark it.
- **rows** — the optimizer's *estimate* of rows it must examine: ~298
  thousand. To return one.
- **filtered** — what percentage of examined rows it *guesses* will survive
  the WHERE. It guessed 10%, so ~30 thousand rows. Reality: exactly one row.
  Without an index on `email`, the optimizer has no statistics about that
  column, so it falls back to a built-in default guess. Estimates lie —
  remember this for lesson 1.8.
- **Extra** — plan annotations. `Using where` just means rows get filtered
  after being read. Later you'll hunt scarier residents of this column:
  `Using temporary` and `Using filesort`.

Two habits to attach to every EXPLAIN. Run `SHOW WARNINGS` right after it —
MySQL leaves a Note containing the query *as the optimizer rewrote it*
(expanded columns, merged subqueries; you'll watch a derived table vanish
into the outer query in deep-dive 3.16). And know EXPLAIN's blind spots:
it says nothing about triggers, stored functions, or UDFs your statement
may fire — a clean plan is not a promise about *their* cost.

[SLIDE 5: the access-type ladder]

`type` values form a ladder, best to worst — learn to read it at a glance:

| type | meaning | typical cost |
|---|---|---|
| `const` / `eq_ref` | at most one row, via PK or unique index | ~free |
| `ref` | index lookup, several rows | cheap |
| `range` | index scan of a bounded range | scales with range size |
| `index` | scan a whole index end to end | full scan, but smaller |
| `ALL` | scan the whole table | the bill scales with the table |

Nothing on the ladder is *always* wrong — chapter 2 shows cases where `ALL`
is genuinely the right plan. But `ALL` on a 300k-row table to fetch one
customer? That's the wrong plan, and by lesson 2.2 it'll be a 9-microsecond
`ref` lookup.

In the exercises: EXPLAIN the lookup yourself and climb the ladder.

---

## Lesson 1.8 — Measuring honestly: EXPLAIN ANALYZE and repeatable timing
*(video script, ~6 min)*

`EXPLAIN` shows the *plan* — the forecast. `EXPLAIN ANALYZE`, available since
MySQL 8.0.18, actually **runs the query** and annotates the plan with what
really happened. Let that sink in before you ever point it at production:
ANALYZE *executes* the statement — a 20-minute query takes 20 minutes to
ANALYZE. When in doubt, cap it (`/*+ MAX_EXECUTION_TIME(…) */` — the
capstone makes this a habit) or ANALYZE on a replica. Here, on our
container, fire away:

```sql
EXPLAIN ANALYZE
SELECT id, full_name, city
FROM customers
WHERE email = 'amara.dubois150000@example.com';
```

```
-> Filter: (customers.email = '...')   (cost=30267 rows=29842)
                                       (actual time=24..46.3 rows=1 loops=1)
    -> Table scan on customers        (cost=30267 rows=298422)
                                       (actual time=0.085..37 rows=300000 loops=1)
```

[SLIDE 6: reading a TREE plan]

This is the *tree format*: each `->` is a plan node; children are indented
below the parent that consumes their rows; execution flows bottom-up.
Each node carries two pairs of numbers:

- `(cost=… rows=…)` — the forecast. Estimated cost units and row count.
- `(actual time=A..B rows=N loops=L)` — the reality. A is milliseconds to the
  *first* row, B to the *last*, N is rows actually produced, L is how many
  times the node ran. **Total node time ≈ B × loops** — that product is how
  you find where a big plan actually spends its life.

Read ours bottom-up: the table scan produced 300,000 rows in 37 ms. The
filter above it threw away all but **1**, finishing at 46 ms. Now compare
forecast to fact — MySQL predicted ~29,842 surviving rows, and got 1. The
plan "worked", but the forecast was off by four orders of magnitude. Today
that gap is harmless; in a join, a mis-estimate like that picks the wrong
join order and turns seconds into minutes. Reading estimate-vs-actual gaps
is a core tuning skill, and `EXPLAIN ANALYZE` puts both on one line.

[SLIDE 8: three rules before you trust a number]

**A warning before you trust any measurement — including this one.**
Three rules, or your numbers are noise:

1. **Warm up first.** The first run of a query may be paying to pull pages
   from disk into the buffer pool. Run everything at least twice; time the
   later runs. (Unless cold-cache performance is what you're studying.)
2. **Change one thing at a time.** Add an index *or* rewrite the WHERE —
   never both between measurements. Otherwise which one helped?
3. **Keep a scorecard.** Write timings down — query, plan summary,
   milliseconds, date. "It feels faster" has shipped a lot of regressions.
   The last exercise of this chapter starts yours.

And a small honesty note about `EXPLAIN ANALYZE` itself: instrumenting every
node isn't free. A 46 ms query might run in 40 ms without the
instrumentation. The *shape* — which node dominates — is what you trust.

In the exercises you'll run ANALYZE on progressively bigger queries — ending
on the four-second monster that the rest of this course exists to fix.

---

## Lesson 1.10 — Finding the slow queries in production
*(video script, ~5 min)*

So far we've tuned queries someone handed us. In real life the first
question is: *which* queries deserve attention? Two built-in answers.

[SLIDE 7: rows examined ≫ rows sent — the slow query log]

**The slow query log.** MySQL can write every statement that takes longer
than `long_query_time` seconds to a log file. Our container ships with it on:

```sql
SHOW VARIABLES LIKE 'slow_query%';       -- ON, /var/lib/mysql/slow.log
SHOW VARIABLES LIKE 'long_query_time';   -- 0.5
```

Every entry records the statement, its duration, lock time, rows sent and
rows examined. That last pair is the single best smell test in MySQL:
**rows examined vs rows sent**. A query that examines 1.2 million rows to
send back 12 is doing 100,000× more work than its output justifies — an
index or a rewrite is hiding in that gap.

In production you'd set `long_query_time` to something like 1 second, let it
run for a day, and aggregate the log (tools like `pt-query-digest` rank
queries by total time). Rule of thumb: fix the query with the biggest
**total** cost — `frequency × duration` — not the single slowest one. A 50 ms
query fired 100 times a second burns more database than a 40-second report
run nightly.

[SLIDE 7, continued: the sys schema]

**The sys schema.** Since 5.7, MySQL aggregates statistics about *every*
statement in `performance_schema`, and the friendlier `sys` views sit on
top. No log files, no waiting — it's already been collecting while you
worked:

```sql
SELECT query, exec_count,
       ROUND(avg_latency/1e12, 2) AS avg_s,
       rows_examined_avg
FROM sys.x$statement_analysis
WHERE db = 'urbancart'
ORDER BY avg_latency DESC
LIMIT 5;
```

This shows each *normalized* statement (literals replaced by `?` so a
thousand different email lookups group as one), how often it ran, its
average latency, and — there it is again — average rows examined.

Between the two: the slow log is your flight recorder, sys is your live
dashboard. Both answer the question that starts every real tuning session:
*what is actually hurting?*

In the exercises you'll read both, then close the chapter by writing down
UrbanCart's baseline scorecard — the "before" photo for everything we fix in
chapters 2 through 4.
