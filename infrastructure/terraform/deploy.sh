
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_SRC="${SCRIPT_DIR}/../../../NotificationsLambda/src/NotificationsLambda"
BUILD_DIR="${SCRIPT_DIR}/.build"

ENVIRONMENT="${ENVIRONMENT:-production}"
USERS_API_URL="${USERS_API_URL:-}"
CATALOG_API_URL="${CATALOG_API_URL:-}"
JWT_KEY="${JWT_KEY:-}"
DD_API_KEY="${DD_API_KEY:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DD_SITE="${DD_SITE:-datadoghq.com}"

[ -z "$USERS_API_URL" ]   && { echo "ERROR: USERS_API_URL not set"; exit 1; }
[ -z "$CATALOG_API_URL" ] && { echo "ERROR: CATALOG_API_URL not set"; exit 1; }
[ -z "$JWT_KEY" ]         && { echo "ERROR: JWT_KEY not set"; exit 1; }
[ -z "$DD_API_KEY" ]      && { echo "ERROR: DD_API_KEY not set"; exit 1; }

mkdir -p "${BUILD_DIR}/notifications-lambda"

dotnet publish "${LAMBDA_SRC}/NotificationsLambda.csproj" \
  --configuration Release \
  --runtime linux-arm64 \
  --self-contained false \
  --output "${BUILD_DIR}/notifications-lambda"

(cd "${BUILD_DIR}/notifications-lambda" && zip -r "${BUILD_DIR}/notifications-lambda.zip" .)

cd "${SCRIPT_DIR}"
terraform init
terraform apply \
  -var="environment=${ENVIRONMENT}" \
  -var="aws_region=${AWS_REGION}" \
  -var="users_api_url=${USERS_API_URL}" \
  -var="catalog_api_url=${CATALOG_API_URL}" \
  -var="jwt_key=${JWT_KEY}" \
  -var="jwt_issuer=FiapCloudGames" \
  -var="jwt_audience=FiapCloudGames" \
  -var="dd_api_key=${DD_API_KEY}" \
  -var="dd_site=${DD_SITE}"
