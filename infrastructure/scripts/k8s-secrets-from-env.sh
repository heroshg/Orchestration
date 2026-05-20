#!/usr/bin/env bash
# =============================================================================
# Gera todos os Kubernetes Secrets do namespace fcg a partir do .env.
# Substitui a edição manual dos arquivos *-secret.yaml.example.
#
# Uso: task k8s:secrets        (chamado pelo Taskfile.yml)
#      bash infrastructure/scripts/k8s-secrets-from-env.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/../.."
ENV_FILE="$ROOT_DIR/.env"
NS=fcg

[ -f "$ENV_FILE" ] || { echo "[ERROR] $ENV_FILE não existe. Rode 'task init' antes." >&2; exit 1; }

# Carrega .env ignorando comentários e linhas vazias
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

required_vars=(
  POSTGRES_PASSWORD RABBITMQ_USER RABBITMQ_PASSWORD REDIS_PASSWORD
  JWT_RSA_PRIVATE_KEY JWT_RSA_PUBLIC_KEY
)
missing=()
for v in "${required_vars[@]}"; do
  [ -z "${!v:-}" ] && missing+=("$v")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "[ERROR] Variáveis faltando no .env: ${missing[*]}" >&2
  exit 1
fi

DD_API_KEY="${DD_API_KEY:-dummy-key-not-set}"

echo "[INFO] Garantindo namespace $NS..."
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

apply_secret() {
  local name=$1; shift
  kubectl create secret generic "$name" --namespace="$NS" "$@" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "[OK]   secret/$name"
}

apply_secret postgres-secret \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

apply_secret rabbitmq-secret \
  --from-literal=RABBITMQ_USER="$RABBITMQ_USER" \
  --from-literal=RABBITMQ_PASSWORD="$RABBITMQ_PASSWORD"

apply_secret redis-secret \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD"

apply_secret datadog-secret \
  --from-literal=api-key="$DD_API_KEY"

apply_secret users-api-secret \
  --from-literal=JWT_RSA_PRIVATE_KEY="$JWT_RSA_PRIVATE_KEY" \
  --from-literal=JWT_RSA_PUBLIC_KEY="$JWT_RSA_PUBLIC_KEY"

apply_secret catalog-api-secret \
  --from-literal=JWT_RSA_PUBLIC_KEY="$JWT_RSA_PUBLIC_KEY"

apply_secret payments-api-secret \
  --from-literal=JWT_RSA_PUBLIC_KEY="$JWT_RSA_PUBLIC_KEY"

echo ""
echo "[DONE] Todos os secrets aplicados em namespace/$NS"
