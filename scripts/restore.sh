#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Restore a backup created by backup.sh (run from the host).
#
# Usage: ./scripts/restore.sh [-y] [BACKUP_FILE]
#   BACKUP_FILE  path to a .sql.gz file (default: newest file in ./backups)
#   -y           do not ask for confirmation
# ---------------------------------------------------------------------------
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ASSUME_YES=false
while getopts ":yh" opt; do
    case "$opt" in
        y) ASSUME_YES=true ;;
        h) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

require docker gzip
FILE="${1:-$(ls -1t "$PROJECT_ROOT"/backups/*.sql.gz 2>/dev/null | head -n 1 || true)}"
[ -n "$FILE" ] && [ -f "$FILE" ] || die "No backup file found (pass one as argument)"
gzip -t "$FILE" || die "Corrupt archive: $FILE"
[ -n "$(service_container db)" ] || die "db container is not running"

if [ "$ASSUME_YES" != true ]; then
    printf 'This will OVERWRITE the current database with %s. Continue? [y/N] ' "$(basename "$FILE")"
    read -r answer
    case "$answer" in y|Y|yes) ;; *) log "Aborted"; exit 0 ;; esac
fi

log "Restoring $(basename "$FILE") ..."
gzip -dc "$FILE" | compose exec -T db sh -c \
    'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null
ok "Restore complete"
