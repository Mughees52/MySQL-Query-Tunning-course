# 🎫 TICKET DD-4187 — Country dashboard unusable

**Priority:** HIGH · **Reporter:** Dana (eng manager) · **Assignee:** you

Marketing demoed the country dashboard to the CEO this morning. It sat on
"loading…" for the whole demo. On staging (same data shape) we gave up and
**killed the backing query after 20 minutes**. It must render in **under
two seconds**.

The query is in [dashboard_v0.sql](dashboard_v0.sql). It computes, per
ship-to country, for the **last 90 days** (data-fixed as `>= 2025-05-29` so
everyone's numbers match), **completed** orders that were **not refunded**:

- order count
- revenue
- average order value
- the country's top product category by item revenue (refunds not excluded
  here — product ranking counts what was bought)

**Constraints from Dana:**

1. The result must not change. At all. The baseline never returns, so your
   oracle is the first *provably equivalent* rewrite (step 2 — the date
   rewrite is equivalence by definition); save its output and diff every
   later version against it. A wrong-but-fast dashboard is a new incident.
2. One change per commit, with the measured time in the commit message —
   we want to know which step bought what.
3. Indexes are fine to add; think before adding one that only this query
   will ever use.

Work through exercises 4.8 → 4.13 in [../chapters/04-the-tuning-workflow/lab.md](../chapters/04-the-tuning-workflow/lab.md).
The finished journey with all measurements: [walkthrough.md](walkthrough.md)
(spoilers — attempt it yourself first).
