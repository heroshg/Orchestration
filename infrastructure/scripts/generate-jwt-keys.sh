#!/usr/bin/env bash
# =============================================================================
# Gera o par RSA usado pela assinatura/validação dos JWTs.
#
# Flags:
#   --force        Regenera mesmo se .keys/ já existir
#   --inject-env   Após gerar, escreve JWT_RSA_PRIVATE_KEY/JWT_RSA_PUBLIC_KEY no
#                  .env (cria/atualiza as linhas in-place). Idempotente.
#
# Sem flags: gera (ou pula se já existe) e imprime as linhas para você colar
# manualmente no .env.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/../.."
KEYS_DIR="$ROOT_DIR/.keys"
ENV_FILE="$ROOT_DIR/.env"

FORCE=false
INJECT_ENV=false
for arg in "$@"; do
  case "$arg" in
    --force)      FORCE=true ;;
    --inject-env) INJECT_ENV=true ;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# //'
      exit 0
      ;;
  esac
done

mkdir -p "$KEYS_DIR"
PRIVATE_PEM="$KEYS_DIR/private.pem"
PUBLIC_PEM="$KEYS_DIR/public.pem"

if [ -f "$PRIVATE_PEM" ] && [ -f "$PUBLIC_PEM" ] && [ "$FORCE" = false ]; then
  echo "[INFO] Chaves já existem em $KEYS_DIR (use --force para regenerar)"
else
  echo "[INFO] Gerando par RSA 2048..."
  openssl genrsa -out "$PRIVATE_PEM" 2048 2>/dev/null
  openssl rsa   -in "$PRIVATE_PEM" -pubout -out "$PUBLIC_PEM" 2>/dev/null
  echo "[OK]   Chaves em $KEYS_DIR"
fi

PRIVATE_B64=$(base64 -w0 "$PRIVATE_PEM")
PUBLIC_B64=$(base64 -w0 "$PUBLIC_PEM")

if [ "$INJECT_ENV" = true ]; then
  if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] .env não existe. Rode 'cp .env.example .env' antes." >&2
    exit 1
  fi
  # Atualiza in-place (sed: substitui linha existente, append se ausente)
  if grep -q '^JWT_RSA_PRIVATE_KEY=' "$ENV_FILE"; then
    sed -i.bak "s|^JWT_RSA_PRIVATE_KEY=.*|JWT_RSA_PRIVATE_KEY=${PRIVATE_B64}|" "$ENV_FILE"
  else
    printf '\nJWT_RSA_PRIVATE_KEY=%s\n' "$PRIVATE_B64" >> "$ENV_FILE"
  fi
  if grep -q '^JWT_RSA_PUBLIC_KEY=' "$ENV_FILE"; then
    sed -i.bak "s|^JWT_RSA_PUBLIC_KEY=.*|JWT_RSA_PUBLIC_KEY=${PUBLIC_B64}|" "$ENV_FILE"
  else
    printf 'JWT_RSA_PUBLIC_KEY=%s\n' "$PUBLIC_B64" >> "$ENV_FILE"
  fi
  rm -f "$ENV_FILE.bak"
  echo "[OK]   .env atualizado com as chaves"
else
  echo ""
  echo "Adicione (ou substitua) ao seu .env:"
  echo ""
  echo "JWT_RSA_PRIVATE_KEY=$PRIVATE_B64"
  echo "JWT_RSA_PUBLIC_KEY=$PUBLIC_B64"
  echo ""
  echo "(ou rode com --inject-env para atualizar o .env automaticamente)"
fi
