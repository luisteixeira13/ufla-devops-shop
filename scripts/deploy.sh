#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="/opt/ufla-shop"
APP_USER="ufla-shop"
ENV_FILE="/etc/ufla-shop.env"
ENV_EXAMPLE="/etc/ufla-shop.env.example"
CERT="/etc/ssl/certs/ufla-shop-selfsigned.pem"
KEY="/etc/ssl/private/ufla-shop-selfsigned.key"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERRO: execute com sudo: sudo $0" >&2
    exit 1
fi

for cmd in python3 runuser systemctl nginx openssl curl psql pg_dump redis-cli; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERRO: comando necessário não encontrado: $cmd" >&2
        exit 1
    fi
done

if [[ ! -f "$ROOT_DIR/systemd/ufla-shop.service" ||
      ! -f "$ROOT_DIR/scripts/backup.sh" ||
      ! -f "$ROOT_DIR/nginx/loja.conf" ]]; then
    echo "ERRO: execute o script a partir da cópia completa do repositório." >&2
    exit 1
fi

# Preserva o arquivo real de configuração entre execuções.
if [[ ! -f "$ENV_EXAMPLE" ]]; then
    install -o root -g root -m 644 \
        "$ROOT_DIR/systemd/ufla-shop.env.example" "$ENV_EXAMPLE"
fi

if [[ ! -f "$ENV_FILE" ]]; then
    install -o root -g root -m 600 "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Foi criado $ENV_FILE a partir do exemplo."
    echo "Configure a senha real e execute o deploy novamente." >&2
    exit 1
fi

chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

if grep -Eiq 'SUBSTITUA_A_SENHA|TROQUE-ESTA-SENHA|CHANGE_ME' "$ENV_FILE"; then
    echo "ERRO: substitua a senha de exemplo em $ENV_FILE antes do deploy." >&2
    exit 1
fi

# Cria o usuário de sistema somente quando ainda não existe.
if ! id "$APP_USER" >/dev/null 2>&1; then
    useradd --system --user-group \
        --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi

install -d -o "$APP_USER" -g "$APP_USER" -m 755 "$APP_DIR"

# Substitui apenas os diretórios gerenciados pelo deploy.
# O ambiente virtual persistente não é apagado.
rm -rf "$APP_DIR/app" "$APP_DIR/static" "$APP_DIR/scripts" \
       "$APP_DIR/systemd" "$APP_DIR/nginx" "$APP_DIR/docs"
rm -f "$APP_DIR/requirements.txt"

cp -a "$ROOT_DIR/app" "$ROOT_DIR/static" "$ROOT_DIR/scripts" \
      "$ROOT_DIR/systemd" "$ROOT_DIR/nginx" "$ROOT_DIR/docs" "$APP_DIR/"
install -m 644 "$ROOT_DIR/requirements.txt" "$APP_DIR/requirements.txt"

chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chmod 755 "$APP_DIR/scripts/backup.sh"

# Cria ou reutiliza o venv e instala as dependências de execução.
runuser -u "$APP_USER" -- python3 -m venv "$APP_DIR/.venv"
runuser -u "$APP_USER" -- \
    "$APP_DIR/.venv/bin/python" -m pip install -r "$APP_DIR/requirements.txt"

# Certificado autoassinado: os arquivos permanecem fora do Git.
install -d -o root -g root -m 755 /etc/ssl/certs
install -d -o root -g ssl-cert -m 710 /etc/ssl/private

if [[ ! -s "$CERT" || ! -s "$KEY" ]]; then
    rm -f "$CERT" "$KEY"
    umask 077
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY" -out "$CERT" \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    chmod 600 "$KEY"
    chmod 644 "$CERT"
fi

# Instala as unidades versionadas no repositório.
install -o root -g root -m 644 "$ROOT_DIR/systemd/ufla-shop.service" \
    /etc/systemd/system/ufla-shop.service
install -o root -g root -m 644 "$ROOT_DIR/systemd/ufla-shop-backup.service" \
    /etc/systemd/system/ufla-shop-backup.service
install -o root -g root -m 644 "$ROOT_DIR/systemd/ufla-shop-backup.timer" \
    /etc/systemd/system/ufla-shop-backup.timer

# Configura o site HTTPS do Nginx.
install -o root -g root -m 644 "$ROOT_DIR/nginx/loja.conf" \
    /etc/nginx/sites-available/loja.conf
ln -sfn /etc/nginx/sites-available/loja.conf /etc/nginx/sites-enabled/loja.conf
rm -f /etc/nginx/sites-enabled/default

install -d -o root -g root -m 750 /var/backups/ufla-shop

# Disponibiliza os serviços necessários e valida a configuração do proxy.
systemctl enable --now postgresql redis-server
nginx -t

systemctl daemon-reload
systemctl enable ufla-shop
systemctl enable --now ufla-shop-backup.timer

if systemctl is-active --quiet ufla-shop; then
    systemctl restart ufla-shop
else
    systemctl start ufla-shop
fi

systemctl enable --now nginx
systemctl reload nginx

# Healthcheck obrigatório: até 10 tentativas, com intervalo de 1 segundo.
READY_BODY="$(mktemp)"
trap 'rm -f "$READY_BODY"' EXIT
HTTP_CODE=""

for attempt in {1..10}; do
    HTTP_CODE="$(curl --silent --show-error --max-time 3 \
        --output "$READY_BODY" --write-out '%{http_code}' \
        http://127.0.0.1:8000/ready 2>/dev/null || true)"

    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "Deploy concluído. Healthcheck HTTP $HTTP_CODE:"
        cat "$READY_BODY"
        echo
        exit 0
    fi

    echo "Healthcheck $attempt/10: HTTP ${HTTP_CODE:-sem resposta}"
    sleep 1
done

echo "ERRO: /ready não retornou HTTP 200 após 10 tentativas." >&2
systemctl status ufla-shop --no-pager || true
journalctl -u ufla-shop -n 40 --no-pager || true
exit 1
