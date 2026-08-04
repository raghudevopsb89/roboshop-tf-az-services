#!/usr/bin/env bash
set -e

: "${DB_HOST:?DB_HOST is required}"
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

MYSQL_HOST="${DB_HOST}"

echo "Waiting for MySQL at ${MYSQL_HOST}..."
until mysqladmin ping -h "$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do
    sleep 2
done

echo "Running shipping database setup..."
mysql -h "$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" < /db/app-user.sql
mysql -h "$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" < /db/schema.sql
echo "Shipping database setup complete"

