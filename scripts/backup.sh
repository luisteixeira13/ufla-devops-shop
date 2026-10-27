#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/ufla-shop.env"
BACKUP_DIR="/var/backups/ufla-shop"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERRO: execute o backup como root." >&2
    exit 1
fi

if [[ -r "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1091
    . "$ENV_FILE"
    set +a
fi

: "${DATABASE_URL:?DATABASE_URL não está configurada em /etc/ufla-shop.env}"

install -d -o root -g root -m 750 "$BACKUP_DIR"

STAMP="$(date +%Y-%m-%d-%H%M)"
FINAL_FILE="$BACKUP_DIR/loja-${STAMP}.sql.gz"
TEMP_FILE="$(mktemp "$BACKUP_DIR/.loja-${STAMP}.XXXXXX.tmp")"

cleanup() {
    rm -f -- "$TEMP_FILE"
}
trap cleanup EXIT

# pipefail garante que uma falha do pg_dump não seja escondida pelo gzip.
pg_dump "$DATABASE_URL" | gzip -c > "$TEMP_FILE"
gzip -t "$TEMP_FILE"
chmod 640 "$TEMP_FILE"
mv -f -- "$TEMP_FILE" "$FINAL_FILE"

# Mantém apenas os sete dumps mais recentes, pela data de modificação.
mapfile -t OLD_FILES < <(
    find "$BACKUP_DIR" -maxdepth 1 -type f -name 'loja-*.sql.gz' \
        -printf '%T@ %p\n' |
        sort -rn |
        awk 'NR > 7 { sub(/^[^ ]+ /, ""); print }'
)

for old_file in "${OLD_FILES[@]}"; do
    rm -f -- "$old_file"
done

FILE_SIZE="$(du -h -- "$FINAL_FILE" | cut -f1)"
logger -t backup "backup gerado: $FINAL_FILE (tamanho: $FILE_SIZE)"
echo "Backup concluído: $FINAL_FILE (tamanho: $FILE_SIZE)"
