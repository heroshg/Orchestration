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

# Empacotamento portátil: tenta zip, python, py launcher (Windows), PowerShell, nessa ordem.
ZIP_BASE="${ZIP_PATH%.zip}"
if command -v zip >/dev/null 2>&1; then
  (cd "${PUBLISH_DIR}" && zip -qr "${ZIP_PATH}" .)
elif command -v python >/dev/null 2>&1; then
  python -c "import shutil; shutil.make_archive(r'${ZIP_BASE}', 'zip', r'${PUBLISH_DIR}')"
elif command -v py >/dev/null 2>&1; then
  py -c "import shutil; shutil.make_archive(r'${ZIP_BASE}', 'zip', r'${PUBLISH_DIR}')"
elif command -v powershell.exe >/dev/null 2>&1; then
  to_win() {
    if command -v wslpath >/dev/null 2>&1;  then wslpath -w "$1"
    elif command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"
    else echo "$1"
    fi
  }
  PUB_WIN=$(to_win "${PUBLISH_DIR}")
  ZIP_WIN=$(to_win "${ZIP_PATH}")
  powershell.exe -NoProfile -Command "Compress-Archive -Path '${PUB_WIN}\\*' -DestinationPath '${ZIP_WIN}' -Force"
else
  echo "ERRO: nenhuma ferramenta de zip disponível (zip/python/py/powershell)" >&2
  exit 1
fi

echo "Lambda empacotada em: ${ZIP_PATH}"
