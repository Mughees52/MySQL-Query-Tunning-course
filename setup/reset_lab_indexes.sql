-- ============================================================================
-- Reset: drop every index the labs create, returning UrbanCart to its
-- pristine "chapter 1" state (primary keys only).
-- Safe to run at any point; errors about missing indexes just mean that lab
-- hasn't been done yet — each DROP is wrapped so the script keeps going.
-- Run with:  docker exec -i mysql-tuning-course mysql -uroot -pcourse urbancart < reset_lab_indexes.sql
-- ============================================================================
USE urbancart;

-- MySQL has no DROP INDEX IF EXISTS, so use a helper procedure.
DROP PROCEDURE IF EXISTS drop_index_if_exists;
DELIMITER //
CREATE PROCEDURE drop_index_if_exists(IN t VARCHAR(64), IN idx VARCHAR(64))
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.statistics
             WHERE table_schema = 'urbancart'
               AND table_name = t AND index_name = idx) THEN
    SET @s = CONCAT('ALTER TABLE `', t, '` DROP INDEX `', idx, '`');
    PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;
  END IF;
END//
DELIMITER ;

-- Chapter 2
CALL drop_index_if_exists('customers',   'idx_customers_email');
CALL drop_index_if_exists('orders',      'idx_orders_customer');        -- created 2.5, dropped 2.14
CALL drop_index_if_exists('orders',      'idx_orders_customer_date');
CALL drop_index_if_exists('orders',      'idx_orders_date_status_total');
CALL drop_index_if_exists('orders',      'idx_orders_status');
CALL drop_index_if_exists('payments',    'idx_payments_provider_ref');

-- Chapter 3
CALL drop_index_if_exists('payments',    'idx_payments_order');

-- Chapter 4 / capstone
CALL drop_index_if_exists('order_items', 'idx_items_order');

-- Advanced scenarios (tables stay; their lab indexes reset)
CALL drop_index_if_exists('activity', 'idx_activity_entity');
CALL drop_index_if_exists('outbox',   'idx_outbox_status');

-- Histogram created in chapter 2 (exercise 2.13)
ANALYZE TABLE orders DROP HISTOGRAM ON ship_country;

DROP PROCEDURE drop_index_if_exists;

ANALYZE TABLE customers, orders, order_items, payments, products;

SELECT table_name, index_name
FROM information_schema.statistics
WHERE table_schema = 'urbancart' AND index_name <> 'PRIMARY'
GROUP BY table_name, index_name;
