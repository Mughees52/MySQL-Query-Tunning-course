#!/usr/bin/env bash
# ============================================================================
# Improving Query Performance in MySQL 8 - environment setup
# Brings up MySQL 8 in Docker on port 3307 and seeds the UrbanCart dataset.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Starting MySQL 8 container (port 3307)..."
docker compose up -d

echo "==> Waiting for MySQL to accept connections..."
until docker exec mysql-tuning-course mysql -uroot -pcourse -e "SELECT 1" >/dev/null 2>&1; do
  sleep 2
done

echo "==> Creating schema..."
docker exec -i mysql-tuning-course mysql -uroot -pcourse < sql/00_schema.sql

echo "==> Seeding data (this takes a few minutes - ~5.5M rows)..."
docker exec -i mysql-tuning-course mysql -uroot -pcourse < sql/01_seed.sql

echo "==> Row counts:"
docker exec mysql-tuning-course mysql -uroot -pcourse urbancart -e "
  SELECT 'customers'   AS tbl, COUNT(*) AS rows_ FROM customers
  UNION ALL SELECT 'products',    COUNT(*) FROM products
  UNION ALL SELECT 'orders',      COUNT(*) FROM orders
  UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
  UNION ALL SELECT 'payments',    COUNT(*) FROM payments
  UNION ALL SELECT 'countries',   COUNT(*) FROM countries;"

echo
echo "Done. Connect with:"
echo "  docker exec -it mysql-tuning-course mysql -uroot -pcourse urbancart"
echo "or from the host:"
echo "  mysql -h127.0.0.1 -P3307 -uroot -pcourse urbancart"
