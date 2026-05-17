#!/usr/bin/env bash
# =============================================================================
# Empacota a NotificationsLambda em um .zip para o LocalStack carregar.
# Espelha o que o deploy.sh do Terraform faz, mas voltado pro ambiente local.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_SRC="${SCRIPT_DIR}/../../../NotificationsLambda/src/NotificationsLambda"
BUILD_DIR="${SCRIPT_DIR}/.build"
PUBLISH_DIR="${BUILD_DIR}/notifications-lambda"
ZIP_PATH="${BUILD_DIR}/notifications-lambda.zip"

rm -rf "${PUBLISH_DIR}" "${ZIP_PATH}"
mkdir -p "${PUBLISH_DIR}"

dotnet publish "${LAMBDA_SRC}/NotificationsLambda.csproj" \
  --configuration Release \
  --runtime linux-x64 \
  --self-contained false \
  --output "${PUBLISH_DIR}"

(cd "${PUBLISH_DIR}" && zip -qr "${ZIP_PATH}" .)

echo "Lambda empacotada em: ${ZIP_PATH}"
