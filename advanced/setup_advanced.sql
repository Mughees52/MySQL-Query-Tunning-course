-- ============================================================================
-- Advanced scenarios — extra tables (run once, after the main seed)
--   activity: a polymorphic "audit trail" (typed pointer, no FKs possible)
--   outbox:   a transactional-outbox event queue with terminal-state skew
-- Deterministic like the main seed. ~3.2M extra rows, ~1-2 min.
-- ============================================================================
USE urbancart;

DROP TABLE IF EXISTS activity, outbox, adv_digits, adv_seq;

CREATE TABLE adv_digits (d TINYINT UNSIGNED NOT NULL PRIMARY KEY);
INSERT INTO adv_digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);
CREATE TABLE adv_seq (n INT UNSIGNED NOT NULL PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO adv_seq
SELECT a.d + b.d*10 + c.d*100 + d.d*1000 + e.d*10000 + f.d*100000 + g.g*1000000 + 1
FROM adv_digits a, adv_digits b, adv_digits c, adv_digits d, adv_digits e, adv_digits f,
     (SELECT 0 AS g UNION ALL SELECT 1) g;

-- ---------------------------------------------------------------------------
-- activity: 1,500,000 rows. entity_type + entity_id is a "typed pointer":
-- one column pair referencing three different tables. No FK is possible.
-- Deliberately NO secondary index at seed time.
-- ---------------------------------------------------------------------------
CREATE TABLE activity (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  entity_type VARCHAR(20)     NOT NULL,   -- 'order' | 'customer' | 'payment'
  entity_id   BIGINT UNSIGNED NOT NULL,
  action      VARCHAR(40)     NOT NULL,
  actor       VARCHAR(60)     NOT NULL,
  created_at  DATETIME        NOT NULL
) ENGINE=InnoDB;

INSERT INTO activity (entity_type, entity_id, action, actor, created_at)
SELECT
  CASE WHEN (CRC32(CONCAT('aty', n)) % 100) < 62 THEN 'order'
       WHEN (CRC32(CONCAT('aty', n)) % 100) < 82 THEN 'customer'
       ELSE 'payment' END,
  CASE WHEN (CRC32(CONCAT('aty', n)) % 100) < 62
         THEN 1 + (CRC32(CONCAT('aid', n)) % 1200000)
       WHEN (CRC32(CONCAT('aty', n)) % 100) < 82
         THEN 1 + (CRC32(CONCAT('aid', n)) % 300000)
       ELSE 1 + (CRC32(CONCAT('aid', n)) % 1068536) END,
  ELT(1 + (CRC32(CONCAT('act', n)) % 8),
      'created','status_changed','note_added','email_sent',
      'flagged','exported','edited','viewed_by_support'),
  CONCAT('agent', 1 + (CRC32(CONCAT('agt', n)) % 200)),
  TIMESTAMP('2023-01-01')
    + INTERVAL (CRC32(CONCAT('ad', n)) % 970) DAY
    + INTERVAL (CRC32(CONCAT('as', n)) % 86400) SECOND
FROM adv_seq WHERE n <= 1500000;

-- ---------------------------------------------------------------------------
-- outbox: 1,700,000 rows. The transactional-outbox pattern: rows are written
-- with status PENDING, a poller publishes them and stamps SENT; failures get
-- FAILED. After two years: 99.4% SENT, a thin live head, and a slowly
-- growing FAILED residue nobody cleans up. NO secondary index at seed time.
-- ---------------------------------------------------------------------------
CREATE TABLE outbox (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  aggregate    VARCHAR(20)     NOT NULL,   -- 'order' | 'payment'
  aggregate_id BIGINT UNSIGNED NOT NULL,
  event_type   VARCHAR(40)     NOT NULL,
  status       VARCHAR(12)     NOT NULL,   -- SENT | PENDING | FAILED
  payload      VARCHAR(255)    NOT NULL,
  created_at   DATETIME        NOT NULL,
  sent_at      DATETIME        NULL
) ENGINE=InnoDB;

INSERT INTO outbox (aggregate, aggregate_id, event_type, status, payload, created_at, sent_at)
SELECT
  IF((CRC32(CONCAT('oag', n)) % 100) < 70, 'order', 'payment'),
  1 + (CRC32(CONCAT('oai', n)) % 1200000),
  ELT(1 + (CRC32(CONCAT('oev', n)) % 6),
      'order.created','order.completed','order.cancelled',
      'payment.captured','payment.refunded','payment.failed'),
  CASE
    -- newest 3000 rows: the live PENDING head
    WHEN n > 1697000 THEN 'PENDING'
    -- 0.55% failed residue scattered through history
    WHEN (CRC32(CONCAT('ost', n)) % 10000) < 55 THEN 'FAILED'
    ELSE 'SENT'
  END,
  CONCAT('{"v":1,"ref":', 4000000000 + n, '}'),
  -- ~49 s between events -> 1.7M rows span ~2.6 years, arrival order = id order
  TIMESTAMP('2023-01-01')
    + INTERVAL (n * 49) SECOND
    + INTERVAL (CRC32(CONCAT('oc', n)) % 40) SECOND,
  IF(n > 1697000, NULL,
     TIMESTAMP('2023-01-01') + INTERVAL (n * 49 + 90) SECOND)
FROM adv_seq WHERE n <= 1700000;

DROP TABLE adv_digits, adv_seq;
ANALYZE TABLE activity, outbox;

SELECT 'activity' t, COUNT(*) c FROM activity
UNION ALL SELECT 'outbox', COUNT(*) FROM outbox;
SELECT status, COUNT(*) FROM outbox GROUP BY status;
