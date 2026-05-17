#!/usr/bin/env bash
# =============================================================================
# Gera o par de chaves RSA usado pela assinatura/validação dos JWTs.
#
# - private.pem → fica apenas com a UsersAPI (serviço que emite o token)
# - public.pem  → distribuído para CatalogAPI, PaymentsAPI e exposto via
#                 endpoint /.well-known/jwks.json para o AWS API Gateway
#                 validar os tokens (JWT Authorizer nativo, algoritmo RS256).
#
# As chaves são geradas em ./.keys/ (gitignored) e codificadas em base64
# single-line para uso direto em variáveis de ambiente / Secrets do K8s.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/../../.keys"
mkdir -p "${KEYS_DIR}"

PRIVATE_PEM="${KEYS_DIR}/private.pem"
PUBLIC_PEM="${KEYS_DIR}/public.pem"

if [ -f "${PRIVATE_PEM}" ] && [ -f "${PUBLIC_PEM}" ]; then
  echo "Chaves já existem em ${KEYS_DIR}. Use --force para regenerar."
  if [ "${1:-}" != "--force" ]; then
    exit 0
  fi
fi

echo "Gerando par RSA 2048..."
openssl genrsa -out "${PRIVATE_PEM}" 2048 2>/dev/null
openssl rsa   -in "${PRIVATE_PEM}" -pubout -out "${PUBLIC_PEM}" 2>/dev/null

PRIVATE_B64=$(base64 -w0 "${PRIVATE_PEM}")
PUBLIC_B64=$(base64 -w0 "${PUBLIC_PEM}")

echo ""
echo "Chaves geradas em: ${KEYS_DIR}"
echo ""
echo "Adicione as linhas abaixo ao seu .env (substituindo as antigas JWT_KEY_*):"
echo ""
echo "JWT_RSA_PRIVATE_KEY=${PRIVATE_B64}"
echo "JWT_RSA_PUBLIC_KEY=${PUBLIC_B64}"
