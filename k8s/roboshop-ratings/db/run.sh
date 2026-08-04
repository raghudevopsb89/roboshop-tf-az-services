#!/usr/bin/env bash
set -e

: "${MYSQL_HOST:?MYSQL_HOST is required}"
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

echo "Waiting for MySQL at ${MYSQL_HOST}..."
until mysqladmin ping -h "$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do
    sleep 2
done

echo "Running ratings database setup..."
mysql -h "$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" < /db/schema.sql
mysql -h "$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" < /db/app-user.sql
echo "Ratings database setup complete"
