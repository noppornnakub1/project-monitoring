#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PostgreSQL backup: pg_dump -> gzip -> verify -> rotate old backups.
#
# Works from both sides of the container boundary:
#   host:       ./scripts/backup.sh               (runs pg_dump via `docker compose exec`)
#   container:  docker compose exec db bash /scripts/backup.sh
# Either way the file lands in ./backups on the host (bind-mounted to /backups).
#
# Options:
#   -k DAYS   keep backups for DAYS days (default: $RETENTION_DAYS or 7)
#   -o DIR    output directory (default: ./backups on host, /backups in container)
#   -h        help
#
# Cron example (daily 02:00):
#   0 2 * * * /path/to/project-monitoring/scripts/backup.sh >> /var/log/pm-backup.log 2>&1
# ---------------------------------------------------------------------------
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

RETENTION_DAYS="${RETENTION_DAYS:-7}"
BACKUP_DIR=""

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":k:o:h" opt; do
    case "$opt" in
        k) RETENTION_DAYS="$OPTARG" ;;
        o) BACKUP_DIR="$OPTARG" ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done
case "$RETENTION_DAYS" in ''|*[!0-9]*) die "Retention must be a whole number of days" ;; esac

if in_container; then
    MODE="container"
    require pg_dump gzip
    BACKUP_DIR="${BACKUP_DIR:-/backups}"
    DB_NAME="${POSTGRES_DB:?POSTGRES_DB not set}"
    # Unix socket inside the db container; POSTGRES_USER comes from the container env
    run_dump() { pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists; }
else
    MODE="host"
    require docker gzip
    BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
    [ -n "$(service_container db)" ] || die "db container is not running (start it with: docker compose up -d)"
    DB_NAME="$(compose exec -T db printenv POSTGRES_DB | tr -d '\r')"
    # Variables are expanded inside the container, so credentials never touch the host shell
    run_dump() { compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists'; }
fi

mkdir -p "$BACKUP_DIR"
[ -w "$BACKUP_DIR" ] || die "Backup directory is not writable: $BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
TARGET="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql.gz"
# Two runs in the same second (e.g. host + container) must not overwrite each other
N=1
while [ -e "$TARGET" ] || [ -e "$TARGET.partial" ]; do
    TARGET="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}_${N}.sql.gz"
    N=$((N + 1))
done
TMP="$TARGET.partial"

# Never leave a half-written file behind
trap 'rm -f "$TMP"; error "Backup failed (line $LINENO)"' ERR
trap 'rm -f "$TMP"' EXIT

log "Starting backup of '$DB_NAME' ($MODE mode) -> $TARGET"
START=$(date +%s)

run_dump | gzip -9 > "$TMP"          # pipefail: a pg_dump failure fails the pipeline

gzip -t "$TMP" || die "Integrity check failed for $TMP"
# A valid dump always ends with this marker
gzip -dc "$TMP" | tail -n 5 | grep -q "PostgreSQL database dump complete" \
    || die "Dump looks truncated: completion marker missing"

mv "$TMP" "$TARGET"
chmod 640 "$TARGET"
ok "Backup complete: $(basename "$TARGET") ($(human_size "$(file_size "$TARGET")"), $(( $(date +%s) - START ))s)"

# Rotation: delete compressed dumps older than the retention window
log "Removing backups older than $RETENTION_DAYS day(s)"
DELETED=0
while IFS= read -r old; do
    rm -f "$old" && DELETED=$((DELETED + 1)) && log "  deleted $(basename "$old")"
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.sql.gz' -mtime +"$RETENTION_DAYS")

COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.sql.gz' | wc -l | tr -d ' ')
TOTAL=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
ok "Rotation done: $DELETED deleted, $COUNT backup(s) kept, $TOTAL used in $BACKUP_DIR"
