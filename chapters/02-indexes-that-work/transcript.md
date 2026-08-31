# Chapter 2 — Indexes That Actually Get Used
### Lesson transcripts

> **Rhythm — teach, then do:** lesson 2.1 (slides 1–3) → labs 2.2–2.3 ·
> lesson 2.4 (slides 4–5) → labs 2.5–2.7 · lesson 2.8 (slides 6–8) →
> labs 2.9–2.14 · deep dives 2.15–2.16.

> Animated slide deck: [slides/chapter2-slides.html](../../slides/chapter2-slides.html) — open in a browser, → / ← to navigate.

> All timings measured live on the course container. Chapter 1's baseline:
> email lookup ~45 ms, customer-137 orders ~110 ms, monster report ~4 s.

---

## Lesson 2.1 — Inside InnoDB: the clustered index and its satellites
*(video script, ~6 min)*

Chapter 1 ended with a scorecard full of full table scans. The fix for most
of them is an index — but "add an index" is where most engineers' knowledge
stops, and it's why so many production indexes never get used. So before we
create anything, let's look at what an InnoDB index actually *is*.

[SLIDE 1: 45 ms → 9 µs — one line of SQL, and the four moves of this chapter]

[SLIDE: recall chapter-1 deck, slide 3 — the clustered tree]

Remember from lesson 1.1: **the table is an index.** InnoDB stores all of
`orders` in a B+tree keyed on the primary key. The leaf pages *are* the rows,
in id order. Three levels of tree, then your row. That's why
`WHERE id = 4242` was `const` on our ladder — near-free.

[SLIDE 2: the two-step dance]

A *secondary* index — the kind you create — is a **second, smaller B+tree**.
For `INDEX (customer_id)` on orders, its leaf entries contain just two
things: the `customer_id` value, and **a copy of the row's primary key**.
Not a pointer to a disk page — the PK itself. That has two consequences
you'll use every day:

**Consequence one: the lookup is a two-step dance.** Find `customer_id=137`
entries in the small tree; for each, take the stored `id` and descend the
clustered index to fetch the full row. Each fetched row is a *second* tree
descent. Cheap for 243 rows. But for 500,000 rows? Half a million extra
descents in random id order. Hold that thought — it explains the trap in
lesson 2.8 where a table scan legitimately beats an index.

**Consequence two: every secondary index silently contains the PK.** An index
on `(customer_id, order_date)` really contains `(customer_id, order_date,
id)`. If your query only needs columns that live *in the index*, step two —
the trip to the big tree — vanishes entirely. That's a **covering index**,
the single most powerful trick in this chapter.

[BOARD: selectivity = distinct values ÷ rows]

One more concept and we'll build something. **Selectivity**: how sharply a
column's values slice the table. `email` — 300k distinct values in 300k rows
— is perfectly selective; an equality match isolates one row. `status` — five
values, one of which covers 86% of the table — is terribly selective for
that value. Indexes pay off in proportion to selectivity, and `SHOW INDEX`'s
`Cardinality` column (estimated distinct values) is how you judge it at a
glance.

In the exercises: you'll build your first index and watch a 45-millisecond
query become a 9-**micro**second query. Then check `SHOW INDEX` to see how
MySQL sizes it up.

---

## Lesson 2.4 — Composite indexes and the leftmost-prefix rule
*(video script, ~7 min)*

You've indexed `email` — a single column. Real queries filter on several
things at once: "orders *for this customer*, *newest first*". Enter the
composite index.

```sql
CREATE INDEX idx_orders_customer_date ON orders (customer_id, order_date DESC);
```

[SLIDE 4: a phone book — composite index]

A composite index is sorted by the *first* column, then, *within* equal
values, by the second, and so on — like a phone book sorted by last name,
then first name. This ordering is the whole game, and it gives you three
superpowers and one hard rule.

**Superpower one: multi-column filtering in one descent.**
`WHERE customer_id = 137 AND order_date >= '2025-01-01'` lands directly on
the exact slice of the index. No filtering after the fact.

**Superpower two: free sorting.** Within customer 137, entries are *already*
in `order_date DESC` order (note we declared it `DESC` — MySQL 8 honors
descending index order). So this query:

```sql
SELECT id, order_date, total_cents
FROM orders
WHERE customer_id = 137
ORDER BY order_date DESC
LIMIT 5;
```

reads **exactly five index entries** and stops. Measured: with only a
single-column `(customer_id)` index, MySQL fetched all 243 of the customer's
orders and sorted them — 1.7 ms. With the composite: 0.07 ms, no sort node
in the plan at all. On a whale customer with 100k orders, that difference is
the page loading or timing out.

**Superpower three: it still serves the single-column query.** A query on
`customer_id` alone happily uses `(customer_id, order_date)` — which is why,
at the end of this chapter, you'll *delete* the single-column index as
redundant.

[SLIDE 4, continued: the leftmost-prefix rule]

Now the hard rule. An index on `(a, b, c)` can seek on: `a` · `a,b` ·
`a,b,c` — and that's it. It can range-scan on a prefix plus *one* range:
`a = ? AND b > ?`. What it **cannot** do is seek on `b` alone, or `c` alone,
or skip over `a`. Why? The phone book again: find everyone whose *first*
name is "Maria" — you'd read the whole book. Measured on our data: filtering
`order_date` alone against `(customer_id, order_date)` degrades to scanning
all 1.2 million index entries.

Corollary worth memorizing: **equality columns first, range column last.**
`(customer_id, order_date)` works because customer is `=` and date is a
range. Flip the order and the range on `order_date` "uses up" the index —
`customer_id` becomes an after-the-fact filter across every date in range.

[SLIDE 5: covering — never touch the table]

And the covering payoff from lesson 2.1: because leaf entries are
`(customer_id, order_date, id)`, our LIMIT-5 query above never touched the
table — the plan reads `Using index` — er, actually, check the exercise:
this one *does* fetch `total_cents` from the table, five times. In exercise
2.7 you'll build an index where even that trip disappears, and the plan
proudly says **covering**.

Exercises: build the composite, race it against the single-column index,
then take the leftmost-prefix quiz — it's the most-asked MySQL interview
question for a reason.

---

## Lesson 2.8 — Five ways to make MySQL ignore your index
*(video script, ~8 min)*

You now know how to build good indexes. This lesson is about the five ways
production code quietly refuses to use them. Every one of these came from a
real outage somewhere. All five are running in UrbanCart's codebase right
now — you'll fix each one in the exercises.

[SLIDE 6, trap 1: a function on the column]

**One: wrapping the column in a function.**

```sql
WHERE DATE(order_date) = '2025-06-15'      -- scans 1.2M index entries, 78 ms
WHERE order_date >= '2025-06-15'
  AND order_date <  '2025-06-16'           -- range scan, 1299 entries, 0.14 ms
```

An index stores `order_date` values in order. `DATE(order_date)` values are
a *different* set of values — the index knows nothing about them, so every
row must be computed and checked. The predicate is called *non-sargable*
(not **s**earch-**arg**ument-**able**). The fix is always the same: leave
the column alone, move the math to the constant side. Same 1,299 rows,
550× faster.

[SLIDE 6, trap 2: comparing across types]

**Two: implicit type conversion.** UrbanCart stores payment gateway
references as strings. Someone's script does:

```sql
WHERE provider_ref = 4000000042       -- number vs VARCHAR column
```

MySQL can't compare a string column to a number directly — its coercion
rules convert **every row's provider_ref to a number** first. Which is a
function on the column. Which is trap #1 in disguise: full scan, 90 ms.
MySQL even confesses — `SHOW WARNINGS` after the EXPLAIN prints:
*"Cannot use ref access on index … due to type or collation conversion."*
Quote the literal — `= '4000000042'` — and it's a 9-microsecond lookup.
The same trap fires on joins where the two sides' column types or
**collations** differ — utf8mb4 joined to latin1 is a silent scan factory.

[SLIDE 6, trap 3: leading wildcard]

**Three: `LIKE '%thing'`.** A B+tree can seek to a *prefix* —
`LIKE 'amara.%'` is really a range scan, fast. But a leading wildcard has no
prefix to seek to; every entry must be checked. If you genuinely need
contains-search at scale, that's what `FULLTEXT` indexes (or a search
engine) are for — not B+trees.

[SLIDE 3 + SLIDE 6, trap 4: low selectivity — the optimizer's coin flip]

**Four: the value matches too much of the table.** Here's the one that
surprises people. We indexed `status`. For `status = 'failed'` (1% of rows)
the index is glorious. For `status = 'completed'` — 86% of the table —
you'd *hope* the optimizer says "pointless, I'll scan". On our container it
actually chooses the index… and that's the **wrong** call: measured, the
index path takes 431 ms (a million random two-step lookups — consequence
one from lesson 2.1!) while a forced scan takes 139 ms. Three times faster.
Two lessons in one: an index lookup that fetches most of the table is
*slower* than reading the table straight through — and the optimizer,
working from an estimate that was off by 2× (597k predicted vs 1.03M
actual), can pick wrong. Which sets up trap five.

[SLIDE 7 + SLIDE 6, trap 5: stale or missing statistics]

**Five: the statistics are wrong.** Every choice above is made from
estimates. Indexes give the optimizer decent per-value statistics via
"index dives". But *unindexed* columns? Chapter 1 showed you the fallback:
a flat 10% guess. For skewed columns you filter on but don't want to pay an
index for, MySQL 8 has **histograms**:

```sql
ANALYZE TABLE orders UPDATE HISTOGRAM ON ship_country WITH 32 BUCKETS;
```

Measured: the row estimate for `ship_country = 'SG'` goes from 119,463
(10% guess) to ~4,898 — against a true count of 4,845. From 25× wrong to 1%
wrong, for the cost of one statement and zero write overhead. Histograms
don't make lookups fast — they make *plans right*, which in joins is often
worth more.

[SLIDE 8: safety tools — invisible indexes, redundant cleanup]

Two housekeeping tools before the exercises. **Invisible indexes**:
`ALTER TABLE … ALTER INDEX … INVISIBLE` keeps an index maintained but hides
it from the optimizer — the safe way to test "would anything break if I
dropped this?" And `sys.schema_redundant_indexes`, which right now is
pointing out that our single-column `(customer_id)` index is fully covered
by the composite. You'll retire it properly — invisible first, verify,
then drop. Indexes aren't free: every write updates every index, and dead
weight slows every INSERT for nothing.
