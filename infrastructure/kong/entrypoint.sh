#!/usr/bin/env sh
# =============================================================================
# Entrypoint do Kong. Resolve a chave pública RSA usada pelo plugin JWT em
# runtime e gera o arquivo declarativo final.
#
# Lê JWT_RSA_PUBLIC_KEY_PEM (PEM bruto) — se vazio, decodifica
# JWT_RSA_PUBLIC_KEY (base64 do PEM, padrão usado pelas APIs).
# =============================================================================
set -eu

if [ -z "${JWT_RSA_PUBLIC_KEY_PEM:-}" ] && [ -n "${JWT_RSA_PUBLIC_KEY:-}" ]; then
  JWT_RSA_PUBLIC_KEY_PEM="$(printf '%s' "$JWT_RSA_PUBLIC_KEY" | base64 -d)"
fi

if [ -z "${JWT_RSA_PUBLIC_KEY_PEM:-}" ]; then
  echo "[kong] ERROR: defina JWT_RSA_PUBLIC_KEY_PEM (PEM) ou JWT_RSA_PUBLIC_KEY (base64 do PEM)" >&2
  exit 1
fi

SOURCE_CONFIG="${KONG_DECLARATIVE_CONFIG:-/etc/kong/kong.yml}"
TARGET_CONFIG="/tmp/kong.resolved.yml"

cp "$SOURCE_CONFIG" "$TARGET_CONFIG"

# Append do bloco 'consumers' com a chave PEM indentada (10 espaços para
# alinhar dentro de `rsa_public_key: |`).
{
  printf '\nconsumers:\n'
  printf '  - username: fcg-clients\n'
  printf '    jwt_secrets:\n'
  printf '      - key: FiapCloudGames\n'
  printf '        algorithm: RS256\n'
  printf '        rsa_public_key: |\n'
  printf '%s\n' "$JWT_RSA_PUBLIC_KEY_PEM" | sed 's/^/          /'
} >> "$TARGET_CONFIG"

export KONG_DECLARATIVE_CONFIG="$TARGET_CONFIG"
exec /docker-entrypoint.sh "$@"
