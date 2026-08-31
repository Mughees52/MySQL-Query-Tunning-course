# Instructor notes — Improving Query Performance in MySQL 8

Internal reference. Learners shouldn't need this; instructors and TAs will.

## Reference environment

All printed timings were measured on: MySQL **8.4** (official `mysql:8`
image), Docker on an Apple-silicon laptop, `innodb_buffer_pool_size=1G`
(entire dataset ~350 MB fits in memory), warm cache, second run. Expect
learner numbers to vary ±50% on absolute values; plan *shapes* and speedup
*ratios* reproduce. Anything that depends on 8.0.18+ (EXPLAIN ANALYZE, hash
joins) is flagged in the transcripts.

## The planted traps (don't "fix" the schema!)

| Trap | Where | Used by |
|---|---|---|
| No secondary indexes at seed time | everywhere | ch. 1 baselines, ch. 2 arc |
| No FK constraints (so no auto-indexes) | all tables | keeps the "before" state honest |
| `payments.provider_ref` VARCHAR holding digits | payments | 2.10 implicit-cast trap |
| `status` VARCHAR, 86% 'completed' | orders | 2.12 skew, 2.13 histograms, 3.12 |
| `ship_country` skew (30% US … 0.4% SG), unindexed | orders | 2.13 histogram demo |
| DATETIME columns everywhere | orders, payments | 2.9 / capstone DATE() trap |
| `coupon_code` ~92% NULL | orders | 3.6 NOT IN null bomb |
| `order_items.order_id` unindexed until capstone | order_items | 3.9, capstone step 3 |
| Whale customers (ids ≤ 500 hold ~10% of orders) | orders | skew in ex. with customer 137 |
| `orders.total_cents` denormalized = SUM(items) | orders | 3.12 / capstone grain fix |

Seed is fully deterministic (CRC32-derived); reseeding reproduces identical
data, so printed row counts (e.g. 8,266 never-ordered customers, 1,299
orders on 2025-06-15, 4,845 SG orders) are stable.

## Canonical index state by end of chapter

- **Ch 1:** primary keys only.
- **Ch 2:** + `idx_customers_email`, `idx_orders_customer_date
  (customer_id, order_date DESC)`, `idx_orders_date_status_total`,
  `idx_orders_status`, `idx_payments_provider_ref`; histogram on
  `orders.ship_country`. (`idx_orders_customer` created in 2.5, dropped in
  2.14 — intentional teaching beat.)
- **Ch 3:** + `idx_payments_order`.
- **Ch 4:** + `idx_items_order` (capstone step 3).
- **Advanced scenarios:** + `idx_activity_entity`, `idx_outbox_status`
  (`advanced/setup_advanced.sql`; the reset script drops these too).

`setup/reset_lab_indexes.sql` returns to the ch-1 state from any point.

## Key measured reference numbers

| Demo | Before | After |
|---|---|---|
| Email lookup (2.2) | 45 ms scan | 0.009 ms ref |
| Customer history (2.5) | 110 ms | 0.4 ms |
| LIMIT-5 widget (2.5) | 1.7 ms + Sort | 0.07 ms, no sort |
| Covering revenue (2.7) | 141 ms | 14 ms |
| DATE() trap (2.9) | 78 ms | 0.14 ms |
| Cast trap (2.10) | 90 ms | 0.009 ms |
| Skew: completed via idx vs scan (2.12) | 431 ms | 139 ms (IGNORE INDEX) |
| Histogram estimate SG (2.13) | 119,463 est | ~4,898 est / 4,845 true |
| key_len on composite (2.4) | 8 (customer_id only) | 13 (+order_date range) |
| SELECT * export (3.3) | 69 ms | 2.9 ms |
| OR → UNION (3.5) | 90 ms | 0.14 ms |
| Anti-joins ×3 (3.7) | 248 / 342 / 377 ms | all = 8,266 rows |
| Hash join forced (3.9) | 1.74 s NL | 0.74 s hash |
| Payments join key (3.9) | 541 ms | 25 ms |
| Monster (1.9 → 3.12) | 4.0 s | 1.75 s → 1.47 s |
| Latest-order shapes (3.13) | corr 320 ms / window 901 ms | GROUP BY 97 ms |
| CTE ×2 (3.14) | inline 0.96 s | CTE 0.51 s |
| City ranking temp+filesort (4.2–4.3) | 1.35 s | (reading exercise) |
| DISTINCT: temp dedup vs index skip scan (3.17) | 159 ms | 0.7 ms |
| OFFSET 1M vs keyset (4.5) | 67 ms | 0.045 ms |
| Sort spill counter (4.16) | 32 KB buffer: 195 merge passes | 256 MB: 0 (in memory) |
| Capstone v0→v6 | v0 killed @21 min; v1 >10 min | v2 8.85 s → v3 1.64 s → v4 1.64 s (same plan, safety) → v5 1.34 s → v6 1.14 s |

## Gotchas we hit building this (so you don't re-hit them)

- **Unsigned arithmetic:** `price_cents - CRC32(...)%300` errors out of
  range on UNSIGNED; both operands must be CAST AS SIGNED. Already fixed in
  the seed.
- **8.4 optimizer chooses ref even at 50% selectivity** (2.12): older 8.0.x
  may choose the table scan outright, making the "optimizer picked wrong"
  beat weaker — the IGNORE INDEX comparison still works either way.
- **`sys.x$statement_analysis` latencies are picoseconds**; the non-`x$`
  view is pre-formatted. The lab uses `/1e12`.
- **EXPLAIN ANALYZE instrumentations** add ~10–15% overhead; never compare
  an ANALYZE time against a bare wall-clock time.
- **The DATE() trap query still shows an index name** in its plan (it scans
  a covering index) — learners often think "it says index, so it's fine".
  That's addressed explicitly in 2.9's expected-observation text.
- **mysql CLI in scripts:** `docker exec -i` (no `-t`), and remember a bare
  `grep -v` that filters everything returns exit code 1 and kills `&&`
  chains.

## Chapter 0 (foundations)

Optional refresher: joins / subqueries+CTEs / temp tables, MySQL-native.
Measured anchors: SELECT pipeline (slide 2) 1,200,000 → 1,032,479 completed
→ 17 ship countries → 7 past HAVING(>50k) → top-3 US 309,882 / GB 154,855 /
DE 102,838; subquery slide (slide 3) avg order value 743.82, 543,009
above mean, plan text "subquery in condition; run only once";
inner vs left join 1,200,000 vs 1,208,266 (+8,266
never-ordered); 5 countries with zero customers (AR BE GR PK SA); 543,009
orders above mean; CTE regional (SHIP-country grain — deliberately not the
monster's customer grain); tmp_de 119,605 rows 0.33 s create, 27 ms vs
659 ms query; view 1.6 s/query vs materialize 2.5 s + 0.2 s/query;
ERROR 1137 on temp self-join. Deck: slides/chapter0-slides.html.

## Slides

`slides/intro-slides.html` (course introduction — scene, dataset, arc,
method, setup, outcomes; transcript in `chapters/intro/transcript.md`) plus
`slides/chapterN-slides.html` — self-contained animated decks. Builds are
**presenter-paced**: elements tagged as build steps stay hidden until you
press → / space (click right half works too) — one press per reveal, and the
same key moves to the next slide once the current one is fully built. ←
undoes the last reveal, then steps back a slide (fully revealed). Home
restarts fresh; End jumps to the final slide fully built. The HUD counter
reads `slide · build j/m`. Talk as long as you like between presses — no
animation runs ahead of you. Theme follows diesta.co.uk (off-white
`#F2F1EF`, charcoal `#212121` panels, link-blue `#0000EE` accent, IBM Plex
Sans/Mono). All numbers on the slides are the measured reference numbers
above. Decks respect `prefers-reduced-motion`. Fonts load from Google Fonts
when online; system fallbacks otherwise.

## Deep dives and advanced scenarios

Each chapter lab ends with ⚙ deep-dive exercises (optimizer trace, cost
internals, semijoin/derived_merge switches, JSON plans, index census) — all
measured. `advanced/` adds two extra tables (`activity` 1.5M, `outbox` 1.7M
— deterministic, `setup_advanced.sql`, ~15 s) and five production-shaped
scenarios; measured reference numbers live in `advanced/solutions.sql`
(OR-chain 11 s → 80 ms; typed-pointer 180 ms → 0.01 ms + 12,462-vs-7,819
wrong-join trap; outbox poll 188 ms → 0.099 ms; purge: naive txn locks 1,710,969 rows
+ blocks inserts, batched 16×50k = 3.7 s; Big-O curves: scan 0.72/8/80 ms
at 10k/100k/1M, non-equi join 1.0 s → 4.0 s on 5k → 10k). The 1 MB
range-optimizer demo genuinely runs away — teach SHOW PROCESSLIST / KILL
alongside it. Scenario D is destructive: re-run setup_advanced.sql after.

## Rebuild from scratch

```bash
cd setup
docker compose down -v   # nuke data volume
./setup.sh               # ~3–5 min
```
