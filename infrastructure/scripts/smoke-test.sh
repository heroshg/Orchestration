#!/usr/bin/env bash
# =============================================================================
# Smoke test do gateway (local ou AWS). Roda contra a URL passada.
#
# Uso:
#   bash infrastructure/scripts/smoke-test.sh                    # localhost:8080
#   bash infrastructure/scripts/smoke-test.sh http://localhost:8080
#   bash infrastructure/scripts/smoke-test.sh https://abc.execute-api.us-east-1.amazonaws.com/production
# =============================================================================
set -euo pipefail

URL="${1:-http://localhost:8080}"
URL="${URL%/}"   # remove trailing slash

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

check() {
  local name=$1 expected=$2 actual=$3
  if [ "$actual" = "$expected" ]; then
    printf "  ${GREEN}✓${NC} %-50s [%s]\n" "$name" "$actual"
    PASS=$((PASS+1))
  else
    printf "  ${RED}✗${NC} %-50s [%s, esperado %s]\n" "$name" "$actual" "$expected"
    FAIL=$((FAIL+1))
  fi
}

echo "Smoke test contra: $URL"
echo ""
echo "──── Gateway / Auth ────"

check "GET  /.well-known/jwks.json (público)"        200 \
  "$(curl -s -o /dev/null -w '%{http_code}' "$URL/.well-known/jwks.json")"

check "GET  /api/games (sem token)"                  401 \
  "$(curl -s -o /dev/null -w '%{http_code}' "$URL/api/games")"

check "POST /api/games (sem token)"                  401 \
  "$(curl -s -X POST -o /dev/null -w '%{http_code}' "$URL/api/games")"

check "PATCH /api/users/<uuid> (sem token)"          401 \
  "$(curl -s -X PATCH -o /dev/null -w '%{http_code}' "$URL/api/users/00000000-0000-0000-0000-000000000001")"

echo ""
echo "──── Fluxo de autenticação ────"

# Login com seed admin (espera 200)
LOGIN_RESP=$(curl -s -X POST "$URL/api/users/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@fgc.com","password":"Admin@123"}')
LOGIN_CODE=$(curl -s -X POST -o /dev/null -w '%{http_code}' "$URL/api/users/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@fgc.com","password":"Admin@123"}')
check "POST /api/users/login (admin seed)" 200 "$LOGIN_CODE"

TOKEN=$(echo "$LOGIN_RESP" | sed -nE 's/.*"token":"([^"]+)".*/\1/p')
if [ -n "$TOKEN" ]; then
  check "GET  /api/games (com token)" 200 \
    "$(curl -s -o /dev/null -w '%{http_code}' "$URL/api/games" -H "Authorization: Bearer $TOKEN")"
else
  printf "  ${RED}✗${NC} Token não capturado do login response\n"
  FAIL=$((FAIL+1))
fi

echo ""
echo "──── Resultado ────"
printf "  ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
exit $FAIL
