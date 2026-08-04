#!/usr/bin/env bash
# Renders the roboshop manifests against the live Terraform outputs and applies
# them. Run from the repo root after `terraform apply`.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "==> reading terraform outputs"
TF_JSON="$(terraform output -json)"

get() { jq -r "$1" <<<"$TF_JSON"; }

ACR_LOGIN_SERVER="$(get '.acr_login_server.value')"
export ACR_LOGIN_SERVER IMAGE_TAG

MYSQL_HOST="$(get '.mysql_host.value')"
MYSQL_USER="$(get '.mysql_admin_username.value')"
MYSQL_PASSWORD="$(get '.mysql_admin_password.value')"
REDIS_HOST="$(get '.redis_host.value')"
REDIS_PORT="$(get '.redis_port.value')"
REDIS_PASSWORD="$(get '.redis_primary_access_key.value')"
MONGO_URL_USERS="$(get '.mongo_urls.value.users')"
MONGO_URL_ORDERS="$(get '.mongo_urls.value.orders')"
SERVICEBUS_CONNECTION_STRING="$(get '.servicebus_connection_string.value')"

echo "==> namespace + config"
envsubst < k8s/00-namespace.yaml | kubectl apply -f -

# Keep an existing JWT secret so re-deploys don't invalidate issued tokens.
JWT_SECRET="$(kubectl -n roboshop get secret roboshop-secrets \
  -o jsonpath='{.data.JWT_SECRET}' 2>/dev/null | base64 -d || true)"
[ -n "$JWT_SECRET" ] || JWT_SECRET="$(openssl rand -hex 32)"

echo "==> secrets"
kubectl -n roboshop create secret generic roboshop-secrets \
  --from-literal=MYSQL_HOST="$MYSQL_HOST" \
  --from-literal=MYSQL_USER="$MYSQL_USER" \
  --from-literal=MYSQL_PASSWORD="$MYSQL_PASSWORD" \
  --from-literal=REDIS_HOST="$REDIS_HOST" \
  --from-literal=REDIS_PORT="$REDIS_PORT" \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  --from-literal=MONGO_URL_USERS="$MONGO_URL_USERS" \
  --from-literal=MONGO_URL_ORDERS="$MONGO_URL_ORDERS" \
  --from-literal=SERVICEBUS_CONNECTION_STRING="$SERVICEBUS_CONNECTION_STRING" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> workloads"
for f in k8s/1*.yaml k8s/20-ingress.yaml; do
  envsubst '${ACR_LOGIN_SERVER} ${IMAGE_TAG}' < "$f" | kubectl apply -f -
done

echo "==> waiting for rollouts"
for d in $(kubectl -n roboshop get deploy -o name); do
  kubectl -n roboshop rollout status "$d" --timeout=5m
done
kubectl -n roboshop get pods -o wide
