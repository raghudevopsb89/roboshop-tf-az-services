#!/usr/bin/env bash
# Seeds the catalogue + ratings schemas from the app repo's SQL files.
set -euo pipefail

cd "$(dirname "$0")/.."

APPS_DIR="${APPS_DIR:-/home/devops/azure-services/apps}"

echo "==> building seed configmap"
kubectl -n roboshop create configmap roboshop-seed-sql \
  --from-file=catalogue-schema.sql="$APPS_DIR/roboshop-catalogue/db/schema.sql" \
  --from-file=catalogue-data.sql="$APPS_DIR/roboshop-catalogue/db/master-data.sql" \
  --from-file=ratings-schema.sql="$APPS_DIR/roboshop-ratings/db/schema.sql" \
  --from-file=cities-schema.sql="$APPS_DIR/roboshop-shipping/src/main/resources/schema.sql" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> running seed job"
kubectl -n roboshop delete job roboshop-db-seed --ignore-not-found
kubectl apply -f k8s/30-seed-job.yaml
kubectl -n roboshop wait --for=condition=complete job/roboshop-db-seed --timeout=5m \
  || { kubectl -n roboshop logs job/roboshop-db-seed; exit 1; }
kubectl -n roboshop logs job/roboshop-db-seed
