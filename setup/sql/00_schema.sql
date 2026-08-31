-- ============================================================================
-- Improving Query Performance in MySQL 8
-- Schema: the "UrbanCart" e-commerce database
-- ============================================================================
-- Design notes (for instructors):
--   * There are NO secondary indexes on purpose. The whole point of the course
--     is to watch queries suffer, understand why, and fix them. Chapter 2 labs
--     create the indexes.
--   * There are NO foreign key constraints. MySQL silently creates an index
--     for every FK, which would spoil the "before" state. It also mirrors
--     plenty of real production schemas.
--   * A few traps are planted deliberately:
--       - payments.provider_ref is a VARCHAR that stores numeric-looking
--         values (implicit-cast trap, Chapter 2).
--       - orders.status is a low-cardinality VARCHAR with heavy skew
--         (selectivity + histogram lessons, Chapters 2 and 4).
--       - Dates are DATETIME, inviting the WHERE DATE(col) = ... mistake.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS urbancart CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE urbancart;

DROP TABLE IF EXISTS order_items, payments, orders, customers, products, countries;

-- Small lookup table: which region/continent each country belongs to.
CREATE TABLE countries (
  country_code CHAR(2)     NOT NULL PRIMARY KEY,
  country_name VARCHAR(60) NOT NULL,
  region       VARCHAR(40) NOT NULL,
  continent    VARCHAR(20) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE customers (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  email            VARCHAR(255)    NOT NULL,
  full_name        VARCHAR(120)    NOT NULL,
  country_code     CHAR(2)         NOT NULL,
  city             VARCHAR(80)     NOT NULL,
  marketing_opt_in TINYINT(1)      NOT NULL DEFAULT 0,
  created_at       DATETIME        NOT NULL
) ENGINE=InnoDB;

CREATE TABLE products (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  sku         VARCHAR(20)     NOT NULL,
  name        VARCHAR(120)    NOT NULL,
  category    VARCHAR(40)     NOT NULL,
  price_cents INT UNSIGNED    NOT NULL,
  active      TINYINT(1)      NOT NULL DEFAULT 1,
  created_at  DATETIME        NOT NULL
) ENGINE=InnoDB;

CREATE TABLE orders (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  customer_id  BIGINT UNSIGNED NOT NULL,
  status       VARCHAR(20)     NOT NULL,  -- completed | pending | cancelled | refunded | failed
  order_date   DATETIME        NOT NULL,
  total_cents  BIGINT UNSIGNED NOT NULL DEFAULT 0,
  ship_country CHAR(2)         NOT NULL,
  coupon_code  VARCHAR(20)     NULL
) ENGINE=InnoDB;

CREATE TABLE order_items (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  order_id         BIGINT UNSIGNED NOT NULL,
  product_id       BIGINT UNSIGNED NOT NULL,
  quantity         TINYINT UNSIGNED NOT NULL,
  unit_price_cents INT UNSIGNED    NOT NULL
) ENGINE=InnoDB;

CREATE TABLE payments (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  order_id     BIGINT UNSIGNED NOT NULL,
  method       VARCHAR(20)     NOT NULL,  -- card | paypal | apple_pay | klarna | bank_transfer
  status       VARCHAR(20)     NOT NULL,  -- succeeded | refunded | pending
  amount_cents BIGINT UNSIGNED NOT NULL,
  provider_ref VARCHAR(32)     NOT NULL,  -- looks numeric, stored as text. On purpose.
  paid_at      DATETIME        NULL
) ENGINE=InnoDB;
