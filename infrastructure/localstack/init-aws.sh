#!/usr/bin/env bash
# =============================================================================
# Bootstrap dos recursos AWS dentro do LocalStack.
# Executado automaticamente pelo LocalStack via /etc/localstack/init/ready.d/.
# Reproduz o que o Terraform cria em produção (SQS, DynamoDB, Lambda, ESM),
# omitindo só os recursos que não fazem sentido localmente (S3 deploy bucket,
# CloudWatch Log Group, Datadog Layer).
# =============================================================================
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
NAME_PREFIX="fcg-local"
USER_CREATED_QUEUE="${NAME_PREFIX}-user-created-events"
USER_CREATED_DLQ="${NAME_PREFIX}-user-created-events-dlq"
PAYMENT_QUEUE="${NAME_PREFIX}-payment-processed-events"
PAYMENT_DLQ="${NAME_PREFIX}-payment-processed-events-dlq"
DYNAMO_TABLE="${NAME_PREFIX}-notifications"
LAMBDA_NAME="${NAME_PREFIX}-notifications"
LAMBDA_ZIP="/opt/code/lambda/notifications-lambda.zip"
API_NAME="${NAME_PREFIX}-api-gateway"

# URLs internas das APIs, conforme ambiente (Compose vs K8s).
# Compose: http://users-api:8080
# K8s:     http://users-api.fcg.svc.cluster.local
USERS_API_INTERNAL_URL="${USERS_API_INTERNAL_URL:-http://users-api:8080}"
CATALOG_API_INTERNAL_URL="${CATALOG_API_INTERNAL_URL:-http://catalog-api:8080}"

# Endpoint que a Lambda usa para falar com o LocalStack.
# Compose: containers Lambda ficam na mesma rede Docker do LocalStack → "localstack:4566" resolve
# K8s:     containers Lambda nascem na bridge do Docker do host → precisam de "host.docker.internal:4566"
LAMBDA_BACKEND_URL="${LAMBDA_BACKEND_URL:-http://localstack:4566}"

echo "[init-aws] Inicializando recursos AWS no LocalStack (região ${REGION})..."

# ── SQS ─────────────────────────────────────────────────────────────────────
awslocal sqs create-queue --queue-name "${USER_CREATED_DLQ}" >/dev/null
awslocal sqs create-queue --queue-name "${PAYMENT_DLQ}" >/dev/null

USER_DLQ_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "http://localhost:4566/000000000000/${USER_CREATED_DLQ}" \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
PAYMENT_DLQ_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "http://localhost:4566/000000000000/${PAYMENT_DLQ}" \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

awslocal sqs create-queue --queue-name "${USER_CREATED_QUEUE}" --attributes "{
  \"VisibilityTimeout\": \"90\",
  \"MessageRetentionPeriod\": \"86400\",
  \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"${USER_DLQ_ARN}\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"
}" >/dev/null

awslocal sqs create-queue --queue-name "${PAYMENT_QUEUE}" --attributes "{
  \"VisibilityTimeout\": \"90\",
  \"MessageRetentionPeriod\": \"86400\",
  \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"${PAYMENT_DLQ_ARN}\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"
}" >/dev/null

USER_QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "http://localhost:4566/000000000000/${USER_CREATED_QUEUE}" \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
PAYMENT_QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "http://localhost:4566/000000000000/${PAYMENT_QUEUE}" \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
echo "[init-aws] Filas SQS criadas."

# ── DynamoDB ────────────────────────────────────────────────────────────────
awslocal dynamodb create-table \
  --table-name "${DYNAMO_TABLE}" \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
      AttributeName=id,AttributeType=S \
      AttributeName=userId,AttributeType=S \
      AttributeName=createdAt,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --global-secondary-indexes "[{
    \"IndexName\": \"userId-createdAt-index\",
    \"KeySchema\": [
      {\"AttributeName\": \"userId\", \"KeyType\": \"HASH\"},
      {\"AttributeName\": \"createdAt\", \"KeyType\": \"RANGE\"}
    ],
    \"Projection\": {\"ProjectionType\": \"ALL\"}
  }]" >/dev/null

awslocal dynamodb update-time-to-live \
  --table-name "${DYNAMO_TABLE}" \
  --time-to-live-specification "Enabled=true, AttributeName=ttl" >/dev/null || true
echo "[init-aws] Tabela DynamoDB criada."

# ── S3 — bucket de deploy da Lambda (espelha aws_s3_bucket.lambda_deploy) ──
LAMBDA_BUCKET="${NAME_PREFIX}-lambda-deploy"
awslocal s3api create-bucket --bucket "${LAMBDA_BUCKET}" >/dev/null
echo "[init-aws] Bucket S3 ${LAMBDA_BUCKET} criado."

# ── CloudWatch Log Group da Lambda (espelha aws_cloudwatch_log_group) ───────
awslocal logs create-log-group --log-group-name "/aws/lambda/${LAMBDA_NAME}" >/dev/null
awslocal logs put-retention-policy \
  --log-group-name "/aws/lambda/${LAMBDA_NAME}" \
  --retention-in-days 14 >/dev/null
echo "[init-aws] Log group /aws/lambda/${LAMBDA_NAME} criado."

# ── Lambda + Event Source Mappings ──────────────────────────────────────────
# Em K8s, a Lambda não é emulada (limitação container-in-container).
# Para pular a criação, defina SKIP_LAMBDA=true no ambiente.
# SQS, DynamoDB, S3 e Logs continuam funcionando normalmente.
if [ "${SKIP_LAMBDA:-false}" = "true" ]; then
  echo "[init-aws] Lambda pulada (SKIP_LAMBDA=true). Use Compose ou 'sam local invoke' para testar."
elif [ -f "${LAMBDA_ZIP}" ]; then
  # Upload do zip pro S3 (paridade com o aws_s3_object do Terraform)
  awslocal s3 cp "${LAMBDA_ZIP}" "s3://${LAMBDA_BUCKET}/notifications-lambda.zip" >/dev/null

  awslocal lambda create-function \
    --function-name "${LAMBDA_NAME}" \
    --runtime dotnet8 \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --handler "NotificationsLambda::NotificationsLambda.Function::FunctionHandler" \
    --code "S3Bucket=${LAMBDA_BUCKET},S3Key=notifications-lambda.zip" \
    --timeout 30 \
    --memory-size 512 \
    --environment "Variables={
      ASPNETCORE_ENVIRONMENT=Development,
      DynamoDB__TableName=${DYNAMO_TABLE},
      DynamoDB__Region=${REGION},
      AWS_ENDPOINT_URL=${LAMBDA_BACKEND_URL},
      AWS_ENDPOINT_URL_DYNAMODB=${LAMBDA_BACKEND_URL},
      DD_TRACE_ENABLED=false,
      CORECLR_ENABLE_PROFILING=0
    }" >/dev/null

  awslocal lambda wait function-active --function-name "${LAMBDA_NAME}"

  awslocal lambda create-event-source-mapping \
    --function-name "${LAMBDA_NAME}" \
    --event-source-arn "${USER_QUEUE_ARN}" \
    --batch-size 10 \
    --maximum-batching-window-in-seconds 5 \
    --function-response-types ReportBatchItemFailures >/dev/null

  awslocal lambda create-event-source-mapping \
    --function-name "${LAMBDA_NAME}" \
    --event-source-arn "${PAYMENT_QUEUE_ARN}" \
    --batch-size 10 \
    --maximum-batching-window-in-seconds 5 \
    --function-response-types ReportBatchItemFailures >/dev/null

  echo "[init-aws] Lambda ${LAMBDA_NAME} + event source mappings configurados."
else
  echo "[init-aws] AVISO: ${LAMBDA_ZIP} não encontrado."
  echo "[init-aws] Rode antes: bash infrastructure/localstack/build-lambda.sh"
  echo "[init-aws] As filas e a tabela estão prontas, mas a Lambda não foi criada."
fi

# ── API Gateway v2 (HTTP API) — best effort ────────────────────────────────
# Limitação conhecida: HTTP API (apigatewayv2) é LocalStack Pro. Community
# só suporta REST API (apigateway v1). Tentamos criar mesmo assim — se
# falhar, seguimos sem o gateway emulado e o cliente acessa as APIs direto
# (users-api:5001 / catalog-api:5002 no Compose).
# Ref: https://docs.localstack.cloud/references/coverage/coverage_apigatewayv2/
set +e
API_ID=$(awslocal apigatewayv2 create-api \
  --name "${API_NAME}" \
  --protocol-type HTTP \
  --cors-configuration "AllowOrigins=*,AllowMethods=GET,POST,PUT,DELETE,OPTIONS,AllowHeaders=Content-Type,Authorization,MaxAge=300" \
  --query 'ApiId' --output text 2>/dev/null)
GATEWAY_RC=$?
set -e

if [ ${GATEWAY_RC} -eq 0 ] && [ -n "${API_ID}" ]; then
  create_integration() {
    awslocal apigatewayv2 create-integration \
      --api-id "${API_ID}" \
      --integration-type HTTP_PROXY \
      --integration-method ANY \
      --integration-uri "$1" \
      --payload-format-version 1.0 \
      --query 'IntegrationId' --output text
  }

  create_route() {
    awslocal apigatewayv2 create-route \
      --api-id "${API_ID}" \
      --route-key "$1" \
      --target "integrations/$2" >/dev/null
  }

  USERS_BASE_INTEG=$(create_integration   "${USERS_API_INTERNAL_URL}/api/users")
  USERS_PROXY_INTEG=$(create_integration  "${USERS_API_INTERNAL_URL}/api/users/{proxy}")
  CATALOG_BASE_INTEG=$(create_integration "${CATALOG_API_INTERNAL_URL}/api/games")
  CATALOG_PROXY_INTEG=$(create_integration "${CATALOG_API_INTERNAL_URL}/api/games/{proxy}")

  create_route "POST /api/users"            "${USERS_BASE_INTEG}"
  create_route "ANY /api/users/{proxy+}"    "${USERS_PROXY_INTEG}"
  create_route "GET /api/games"             "${CATALOG_BASE_INTEG}"
  create_route "POST /api/games"            "${CATALOG_BASE_INTEG}"
  create_route "ANY /api/games/{proxy+}"    "${CATALOG_PROXY_INTEG}"

  awslocal apigatewayv2 create-stage \
    --api-id "${API_ID}" \
    --stage-name local \
    --auto-deploy >/dev/null

  echo "[init-aws] API Gateway criado — id=${API_ID}"
  echo "[init-aws] Endpoint: http://localhost:4566/_aws/execute-api/${API_ID}/local"
  echo "${API_ID}" > /tmp/fcg-api-id.txt
else
  echo "[init-aws] API Gateway v2 não criado (Pro-only no LocalStack)."
  echo "[init-aws] Em dev local, acesse as APIs direto:"
  echo "[init-aws]   UsersAPI   → http://localhost:5001"
  echo "[init-aws]   CatalogAPI → http://localhost:5002"
fi

echo "[init-aws] Concluído."
