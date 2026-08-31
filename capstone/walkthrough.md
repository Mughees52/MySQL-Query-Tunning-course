# Capstone walkthrough — DD-4187, the executive dashboard

> **Spoilers.** Attempt exercises 4.8–4.13 yourself first. This is the
> reference journey with every measurement, taken on the course container
> (MySQL 8.4, 1G buffer pool, warm cache, `EXPLAIN ANALYZE` actuals).
> One change per step; 17 result rows, diffed at every step from v2 on.

## The scoreboard

| Version | Change | Time | Result identical? |
|---|---|---|---|
| v0 | as found in the app | **killed at 21 min** | — (never returned) |
| v1 | sargable dates | **still > 10 min** (aborted by cap) | ≡ v0 by definition |
| v2 | + `idx_items_order` | **8.85 s** — first finish | oracle saved (≡ v1: index-neutral) |
| v3 | correlated top-category → one-pass CTE | **1.64 s** | ✅ diff clean |
| v4 | `NOT IN` → `NOT EXISTS` | **1.64 s** (same plan!) | ✅ diff clean |
| v5 | order-grain outer query (items join deleted) | **1.34 s** | ✅ diff clean |
| v6 | final polish: aggregate-before-join + `IGNORE INDEX` | **1.14 s** | ✅ diff clean |

Requirement: **< 2 s**. Met at v5, comfortable margin at v6.
From a query we could not finish to **1.14 seconds** — more than 1,000×.

---

## Step 1 — baseline: a bound is also a measurement

`dashboard_v0.sql`, run with `/*+ MAX_EXECUTION_TIME(600000) */`, aborts at
the 10-minute cap; unbounded, we killed it by hand at 21 minutes. Recorded
baseline: **> 21 min**.

Why so catastrophic? The EXPLAIN shows the pile-up: the outer query joins
3M `order_items` rows with no index on the join key, wrapped in
`DATE(order_date)` so no date index can seek — and the top-category
**correlated subquery** re-executes that same unindexed, non-sargable join
**per country group**. Slow × slow × 17.

## Step 2 (v1) — sargable dates: correct, necessary… insufficient

`DATE(o.order_date) >= '2025-05-29'` → `o.order_date >= '2025-05-29'`,
both occurrences, nothing else. Equivalent **by definition** (for a date
literal, `DATE(x) >= 'd'` ⟺ `x >= 'd 00:00:00'`), so no diff is needed —
which is convenient, because v1 *also* blows the 10-minute cap.

This is the moment that separates checklists from understanding: the fix
was right — EXPLAIN confirms the orders access became an index range —
but the dominant cost was never the date filter. The loop's answer: keep
the strictly-better change, read the plan again, pull the next lever.

## Step 3 (v2) — the index the join deserved: first light

```sql
CREATE INDEX idx_items_order ON order_items(order_id);   -- ~4 s to build
```

Query text untouched — a pure index effect, measured in isolation.

**Measured: 8.85 s.** From unmeasurable to measurable. Save the 17-row
output — it is the **oracle** for every remaining step (v2 ≡ v1 because an
index can't change results; v1 ≡ v0 by definition — a chain of provably
safe steps, so the oracle is trustworthy even though v0 never returned).

Reading the new plan: the outer aggregation now costs ~1 s… and the other
~7.8 s is 17 executions of the correlated subquery, each ~460 ms. The next
lever names itself.

## Step 4 (v3) — seventeen queries become one

The set-based rewrite computes every country's category revenues in one
grouped pass and ranks with a window function (full SQL in
`dashboard_steps.sql`):

```sql
WITH top_cat AS (
  SELECT ship_country, category FROM (
    SELECT o2.ship_country, p2.category,
           ROW_NUMBER() OVER (PARTITION BY o2.ship_country
                              ORDER BY SUM(oi2.quantity*oi2.unit_price_cents) DESC) rn
    FROM orders o2
    JOIN order_items oi2 ON oi2.order_id = o2.id
    JOIN products p2     ON p2.id = oi2.product_id
    WHERE o2.order_date >= '2025-05-29' AND o2.status = 'completed'
    GROUP BY o2.ship_country, p2.category) ranked
  WHERE rn = 1)
SELECT ...
```

**Measured: 1.64 s** — a 5.4× cut, the biggest single win of the session.
Diff: clean, including every per-country winner. (If a country ever *tied*
two categories on revenue, `LIMIT 1` and `ROW_NUMBER()` could break the tie
differently; this data has no ties. In production, add the same explicit
tie-break — e.g. `, category` — to both forms.)

## Step 5 (v4) — NOT IN → NOT EXISTS: a step that "did nothing"

```sql
AND NOT EXISTS (SELECT 1 FROM payments p
                WHERE p.order_id = o.id AND p.status = 'refunded')
```

**Measured: 1.64 s — the same. Identical plan.** Surprise with a lesson in
it: `payments.order_id` is declared NOT NULL, so MySQL had *already*
transformed the `NOT IN` into the same index-probing antijoin. So why keep
the change? Because the equivalence is a *courtesy of the current schema*:
the day someone makes that column nullable — or copies this pattern onto a
nullable column — `NOT IN` starts silently returning zero rows (lab 3.6).
`NOT EXISTS` can never misfire that way. Some commits buy speed; this one
buys insurance. Diff: clean.

## Step 6 (v5 → v6) — the grain fix, and reading the final plan

**v5:** the outer query joined `order_items` only to recompute what
`orders.total_cents` already stores. Delete the outer items join;
`COUNT(DISTINCT o.id)` becomes `COUNT(*)`; revenue and AOV read
`o.total_cents`. (The top-category CTE keeps its items join — category
detail genuinely lives at item grain.) **Measured: 1.34 s.** Diff: clean.
Requirement met.

**v6 — the final plan review pays twice more.** `EXPLAIN ANALYZE` on v5
shows two old friends:

1. Both order reads drive through `idx_orders_status (status='completed')`
   — 1.03M index entries read, *then* filtered by date (~435 ms each).
   Chapter 2.12's poisonous low-selectivity index, third appearance.
   `IGNORE INDEX (idx_orders_status)` lets the date range drive instead
   (~165 ms and ~110 ms).
2. The outer query joins 96,971 order rows to the 17-row CTE — aggregate
   the orders down to 17 country rows *first*, then join (chapter 3.12,
   properly applied this time).

**Measured: 1.14 s.** Diff: clean. Under the 2-second requirement with
margin — and per lesson 4.6, this is where we **stop**: the next levers
(covering index on `(order_date, status, ship_country, total_cents)`,
hash-join hints for the products lookup) are real but buy maybe another
~0.4 s that nobody asked for, at the price of another index on the
write path and two more hints frozen against today's optimizer. They're
noted in the ticket for the day the requirement tightens.

## What closed the ticket

| Lever | Chapter | Contribution |
|---|---|---|
| Sargable predicates | 2.9 | necessary groundwork (plan strictly better) |
| Join-key index | 3.9 | un-finishable → 8.85 s |
| Set-based over per-row | 3.13 | 8.85 s → 1.64 s |
| NULL-safe anti-join | 3.6 | 0 s faster, ∞ safer |
| Right grain | 3.12 | 1.64 s → 1.34 s |
| Plan review: skew + agg-before-join | 2.12 + 3.12 | 1.34 s → 1.14 s |

And the meta-lever: **one change per step, measured, diffed**. When v4
"did nothing", we knew precisely which change did nothing — and learned
why it was worth keeping anyway.

*Ticket status: closed. Dana owes you a coffee.*
