#!/usr/bin/env bash
# =============================================================================
# apply-k8s-secrets.sh — aplica todos os Kubernetes Secrets a partir dos
# arquivos *-secret.yaml (git-ignored). Execute antes de 'kubectl apply -f k8s/'
#
# Uso: bash apply-k8s-secrets.sh [namespace]
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-fcg}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

echo "Aplicando Kubernetes Secrets no namespace: $NAMESPACE"

SECRET_FILES=(
  "postgres-secrets.yaml"
  "rabbitmq-secret.yaml"
  "redis-secret.yaml"
  "datadog-secret.yaml"
  "users-api-secret.yaml"
  "catalog-api-secret.yaml"
  "payments-api-secret.yaml"
)

for file in "${SECRET_FILES[@]}"; do
  path="$K8S_DIR/$file"
  if [[ -f "$path" ]]; then
    echo "  Aplicando $file..."
    kubectl apply -f "$path" -n "$NAMESPACE"
  else
    echo "  AVISO: $file não encontrado. Copie o .example e preencha os valores:"
    echo "    cp $path.example $path"
    echo "    # edite $path com os valores reais"
  fi
done

echo ""
echo "Secrets aplicados. Agora aplique os demais manifests:"
echo "  kubectl apply -f k8s/ -n $NAMESPACE"
