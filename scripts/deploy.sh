#!/usr/bin/env bash
set -euo pipefail

VERSAO="${1:-}"
if [[ -z "$VERSAO" ]]; then
    echo "Uso: $0 <versao>" >&2
    exit 1
fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
    cp .env.example .env
fi

if grep -q '^APP_VERSION=' .env; then
    sed -i "s/^APP_VERSION=.*/APP_VERSION=${VERSAO}/" .env
else
    echo "APP_VERSION=${VERSAO}" >> .env
fi

export APP_VERSION="${VERSAO}"
export APP_IMAGE="${APP_IMAGE:-ghcr.io/luisteixeira13/ufla-shop}"

echo "===== IMPLANTANDO ${APP_IMAGE}:${APP_VERSION} ====="
docker compose pull api
docker compose up -d --wait

echo "===== STATUS DOS CONTAINERS ====="
docker compose ps

echo "===== VALIDANDO HEALTHCHECKS HTTP ====="
curl -sf http://localhost/health && echo
curl -sf http://localhost/ready && echo
curl -sf http://localhost/api/info && echo
