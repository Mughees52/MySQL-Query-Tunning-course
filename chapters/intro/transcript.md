# Course Introduction — Improving Query Performance in MySQL 8
### Lesson transcript

> **Rhythm — learn, then do:** this intro (slides 1–7) → your one practical:
> run `setup/setup.sh`, connect, and verify the row count. Then straight into
> chapter 0 (constructs refresher) or chapter 1 (the journey of a query).

> Animated slide deck: [slides/intro-slides.html](../../slides/intro-slides.html) —
> open in a browser. Presenter-paced: → reveals the next build, ← undoes it.

---

## Lesson 0.0 — Why this course exists
*(video script, ~5 min)*

[SLIDE 1: title + course facts]

Welcome to Improving Query Performance in MySQL 8. Before we start, one
promise that shapes everything you're about to see: **you will never be shown
a number that wasn't measured.** Every timing, every row count, every plan in
the slides, transcripts and solutions was produced live on the same database
you're about to build. No "this is roughly 10× faster" hand-waving — when a
slide says 45 milliseconds became 9 microseconds, that's a measurement, and
by the end of the course you'll be running the same measurements yourself,
out of habit, before you believe anyone's claim — including mine.

The shape of the course: four chapters plus an optional foundations
refresher, eighteen lessons, fifty-four exercises, one capstone rescue, and
five advanced production scenarios. Four to five hours if you do everything.

[SLIDE 2: welcome to UrbanCart — size, crime, symptoms]

Here's the setting. You've just joined **UrbanCart**, an online retailer.
The database is five and a half million rows, about 350 megabytes. That is
*not* big data — and that's precisely the point. Everything fits in memory;
there is no I/O excuse, no hardware excuse. If queries are slow at this
size, they're slow because of how they're written and what the schema gives
them to work with — and no amount of hardware will save you at ten times
the size.

And they *are* slow. A single customer lookup by email burns 45 milliseconds
of CPU. The morning revenue report takes four seconds, and it gets refreshed
all day long. Why? Because of the thing nobody noticed when the schema was
written in a hurry: **other than the primary keys, there is not a single
index in this database.** That lookup that takes 45 milliseconds? With the
right index it takes nine *microseconds*. That's not an optimization — that's
a five-thousand-fold difference in work, multiplied across every session,
every day. Fixing this — properly, measurably — is your job for the next
four hours.

[SLIDE 3: the dataset — six tables]

The data itself: six tables. A tiny `countries` lookup — thirty-two rows.
Three hundred thousand `customers`. Five thousand `products`. One point two
million `orders`. Three million `order_items`. About a million `payments`.
The seed is **deterministic** — you get byte-identical data to mine. Your
hardware will make your absolute timings differ from the printed ones, but
the ratios and the plans will match, and that's what matters.

One more thing about this schema: it lies to you in the same ways real
production schemas do. There's a column that looks numeric but is stored as
a VARCHAR. There's a status column where one value covers 86% of the table.
There are DATETIME columns that practically beg you to wrap them in `DATE()`
— which, as you'll learn, is exactly how you stop an index from working.
None of these traps is artificial; they're the classics, planted honestly.
You'll step on some of them. That's the plan.

[SLIDE 4: the journey — five chapters, one arc]

The arc of the course is: *see, index, shape, workflow.*

**Chapter 0** is an optional refresher — joins, subqueries, CTEs and
temporary tables, taught MySQL-style, including what MySQL *doesn't* have
(FULL OUTER JOIN) and what bites people porting from PostgreSQL (the
temp-table reopen error). If you're fluent, skip it.

**Chapter 1 — see.** You can't fix what you can't observe. The query
lifecycle, `EXPLAIN` and `EXPLAIN ANALYZE`, the slow query log, the sys
schema — ending with a measured baseline scorecard of UrbanCart's pain.

**Chapter 2 — index.** The largest speedup you'll ever get per line of SQL.
How InnoDB B+trees actually work, selectivity, composite and covering
indexes — and the five classic ways production code throws an index away.

**Chapter 3 — shape.** Same result, a tenth of the cost. Filter shapes,
join algorithms, the NOT IN null bomb, aggregation grain — several
measurements in that chapter contradict popular folklore, and that's good.

**Chapter 4 — workflow.** Everything becomes one repeatable loop, applied to
a dashboard query so slow it couldn't even be measured — killed at 21
minutes, shipped at 1.14 seconds, with the result set proven identical at
every step.

After that, if you want more: five **advanced scenarios** shaped like real
production incidents — the ORM that writes ten-thousand-arm WHERE clauses,
polymorphic typed pointers, the outbox poller, the retention purge that
locks 1.7 million rows, and measured Big-O growth curves for SQL.

[SLIDE 5: the method — learn a section then do it, measure honestly, safety net]

How to work through it: **learn a section, then do it.** Every lesson is followed
immediately by its exercises — read one lesson, do its lab, then move on.
Concepts stick when the practical follows within minutes, not at the end of
the chapter. Each chapter gives you a transcript (what you're reading now),
an animated slide deck, a lab with starter SQL and hints, and annotated
solutions with the measured timings.

Two rules. First, **measure honestly**: warm cache, run twice, write it
down, save the result set — `EXPLAIN ANALYZE` is the referee, never vibes.
Second, do the chapters **in order** — later chapters assume the indexes
and habits built in earlier ones. And you can't break anything: one script,
`setup/reset_lab_indexes.sql`, returns the database to its chapter-1 state,
and the deterministic seed means you can always rebuild from scratch.

[SLIDE 6: setup — one command]

Your only prerequisite is Docker. Two commands:

```bash
cd setup
./setup.sh
```

That builds a MySQL 8 container on port **3307** — chosen so it won't
collide with any MySQL you already run — and seeds the dataset. It takes a
few minutes, once. Then connect:

```bash
docker exec -it mysql-tuning-course mysql -uroot -pcourse urbancart
```

Sanity check: `SELECT COUNT(*) FROM orders;` should say 1,200,000. If it
does, you're ready. Everything in this course runs inside that one
container — there is nothing else to install.

[SLIDE 7: outcomes]

Where you'll land, concretely: you'll read plans honestly — time times
loops, estimates versus reality, which node is actually the bill. You'll
design indexes that get *used*, and retire the ones that don't,
invisible-first. You'll recognize slow shapes on sight and rewrite them
without changing results. You'll run the ticket-to-fix loop: reproduce,
measure, read the plan, change one thing, verify identity, and — the
underrated skill — **stop on purpose** when the requirement is met.

That's the course. Run the setup now, while the next video loads. If you
want the constructs refresher, start with chapter 0. If you're ready, go
straight to chapter 1 — and I'll see you at UrbanCart.

---

*Practical for this lesson: run `setup/setup.sh`, connect, and verify
`SELECT COUNT(*) FROM orders;` returns 1,200,000. That's it — the real
exercises start in the next chapter.*
