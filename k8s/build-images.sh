#!/usr/bin/env bash
# Builds the eight roboshop service images and pushes them to the ACR created by
# this stack. App source lives in a separate repo; point APPS_DIR at it.
set -euo pipefail

cd "$(dirname "$0")/.."

APPS_DIR="${APPS_DIR:-/home/devops/azure-services/apps}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

ACR_NAME="$(terraform output -raw acr_login_server)"
ACR_NAME="${ACR_NAME%%.*}"

echo "==> logging in to $ACR_NAME"
az acr login -n "$ACR_NAME"

SERVICES=(catalogue user cart shipping payment ratings orders frontend)

for svc in "${SERVICES[@]}"; do
  src="$APPS_DIR/roboshop-$svc"
  img="$ACR_NAME.azurecr.io/roboshop-$svc:$IMAGE_TAG"
  echo "==> building $img"
  docker build -t "$img" "$src"
  docker push "$img"
done

echo "==> done"
