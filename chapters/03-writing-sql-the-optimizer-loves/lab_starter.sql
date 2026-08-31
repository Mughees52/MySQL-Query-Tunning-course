-- ============================================================================
-- Chapter 3 lab starters — fill in the ___ blanks.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 3.3 SELECT * vs projected columns
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT * FROM orders WHERE order_date >= '2025-08-01';
EXPLAIN ANALYZE SELECT ___, ___, ___, ___ FROM orders WHERE order_date >= '2025-08-01';

-- ---------------------------------------------------------------------------
-- 3.5 OR vs IN vs UNION
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE customer_id IN (137, 42007, 250999);

EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE customer_id = 137 OR id = 500000;

EXPLAIN ANALYZE
SELECT COUNT(*) FROM (
  SELECT id FROM orders WHERE ___ = 137
  ___
  SELECT id FROM orders WHERE ___ = 500000
) u;

-- bonus: one unindexed side poisons the whole OR
EXPLAIN ANALYZE SELECT COUNT(*) FROM orders WHERE customer_id = 137 OR coupon_code = 'SAVE7';

-- ---------------------------------------------------------------------------
-- 3.6 The NOT IN null bomb
-- ---------------------------------------------------------------------------
-- naive (count the rows!):
SELECT DISTINCT coupon_code
FROM orders
WHERE coupon_code IS NOT NULL
  AND coupon_code NOT IN (SELECT coupon_code FROM orders
                          WHERE status = 'cancelled'
                            AND order_date >= '2025-06-15' AND order_date < '2025-06-16');

-- fix (a): make the subquery NULL-free
--   ... AND coupon_code IS ___ inside the subquery

-- fix (b): NOT EXISTS
SELECT DISTINCT o.coupon_code
FROM orders o
WHERE o.coupon_code IS NOT NULL
  AND NOT ___ (SELECT 1 FROM orders c
               WHERE c.status = 'cancelled'
                 AND c.order_date >= '2025-06-15' AND c.order_date < '2025-06-16'
                 AND c.coupon_code = o.coupon_code);

-- ---------------------------------------------------------------------------
-- 3.7 Three anti-join shapes (customers with zero orders)
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT COUNT(*) FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
WHERE o.___ IS NULL;

EXPLAIN ANALYZE
SELECT COUNT(*) FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.___ = c.id);

EXPLAIN ANALYZE
SELECT COUNT(*) FROM customers c
WHERE c.id NOT IN (SELECT ___ FROM orders);

-- ---------------------------------------------------------------------------
-- 3.9 Hash join vs nested loop
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT p.category, ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS rev
FROM order_items oi JOIN products p ON p.id = oi.product_id
GROUP BY p.category;

EXPLAIN ANALYZE
SELECT p.category, ROUND(SUM(oi.quantity * oi.unit_price_cents)/100, 2) AS rev
FROM order_items oi JOIN products p ___ ___ (PRIMARY) ON p.id = oi.product_id
GROUP BY p.category;

-- the everyday case: index the join key
EXPLAIN ANALYZE
SELECT o.id, p.method, p.amount_cents
FROM orders o JOIN payments p ON p.order_id = o.id
WHERE o.order_date >= '2025-08-20';

CREATE INDEX idx_payments_order ON payments(___);

EXPLAIN ANALYZE
SELECT o.id, p.method, p.amount_cents
FROM orders o JOIN payments p ON p.order_id = o.id
WHERE o.order_date >= '2025-08-20';

-- ---------------------------------------------------------------------------
-- 3.10 ON vs WHERE on a LEFT JOIN
-- ---------------------------------------------------------------------------
SELECT COUNT(*) FROM orders o
LEFT JOIN payments p ON p.order_id = o.id AND p.method = 'klarna'
WHERE o.order_date >= '2025-08-01' AND o.order_date < '2025-08-08';

SELECT COUNT(*) FROM orders o
LEFT JOIN payments p ON p.order_id = o.id
WHERE o.order_date >= '2025-08-01' AND o.order_date < '2025-08-08'
  AND p.method = 'klarna';

-- ---------------------------------------------------------------------------
-- 3.12 The monster, at the right grain
-- ---------------------------------------------------------------------------
-- attempt 1 (textbook, and slower — measure it anyway):
EXPLAIN ANALYZE
SELECT co.region, COUNT(*) AS orders, ROUND(SUM(t.order_rev)/100, 2) AS revenue
FROM (SELECT oi.order_id, SUM(oi.quantity * oi.unit_price_cents) AS order_rev
      FROM order_items oi GROUP BY oi.order_id) t
JOIN orders o     ON o.id = t.order_id AND o.status = 'completed'
JOIN customers c  ON c.id = o.customer_id
JOIN countries co ON co.country_code = c.country_code
GROUP BY co.region ORDER BY revenue DESC;

-- attempt 2 (right grain — no items join at all):
EXPLAIN ANALYZE
SELECT co.region, COUNT(*) AS orders, ROUND(SUM(o.___)/100, 2) AS revenue
FROM orders o
JOIN customers c  ON c.id = o.customer_id
JOIN countries co ON co.country_code = c.country_code
WHERE o.status = 'completed'
GROUP BY co.region ORDER BY revenue DESC;

-- attempt 2b: dodge the poisonous status index (chapter 2!)
--   FROM orders o ___ ___ (idx_orders_status)

-- ---------------------------------------------------------------------------
-- 3.13 Latest order per customer, three shapes
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT c.id, (SELECT MAX(o.order_date) FROM orders o WHERE o.customer_id = c.id) AS last_order
FROM customers c;

EXPLAIN ANALYZE
SELECT customer_id, MAX(order_date) FROM orders GROUP BY ___;

EXPLAIN ANALYZE
SELECT customer_id, order_date FROM (
  SELECT customer_id, order_date,
         ROW_NUMBER() OVER (PARTITION BY ___ ORDER BY ___ DESC) AS rn
  FROM orders) x
WHERE rn = 1;

-- ---------------------------------------------------------------------------
-- 3.14 One CTE, used twice
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
WITH monthly AS (
  SELECT EXTRACT(YEAR_MONTH FROM order_date) AS ym, SUM(total_cents) AS rev
  FROM orders WHERE status = 'completed' GROUP BY ym)
SELECT a.ym, ROUND(a.rev/100, 2) AS rev,
       ROUND((a.rev - b.rev) / b.rev * 100, 1) AS mom_pct
FROM monthly a
LEFT JOIN monthly b ON b.ym = PERIOD_ADD(a.ym, ___)
ORDER BY a.ym;

-- versus: paste the same aggregation twice as inline derived tables a and b.
