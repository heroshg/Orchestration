#!/usr/bin/env bash
# Builda as imagens de todos os serviços antes de executar o docker compose.
# Uso: ./build.sh [--no-cache]
#
# Após o build, suba o ambiente com:
#   docker compose up -d

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ARGS=("$@")

services=(
  "users-api:../UsersAPI"
  "catalog-api:../CatalogAPI"
  "payments-api:../PaymentsAPI"
  "notifications-api:../NotificationsAPI"
)

for entry in "${services[@]}"; do
  image="${entry%%:*}"
  context="$SCRIPT_DIR/${entry#*:}"
  echo "Building $image..."
  docker build "${BUILD_ARGS[@]}" -t "$image:latest" "$context"
done

echo ""
echo "Todas as imagens buildadas. Execute: docker compose up -d"
