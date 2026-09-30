#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Log collection + rotation (a small logrotate written in bash).
#
# Container stdout is already capped by Docker (json-file, 10m x 3, see docker-compose.yml).
# This script covers the "file logs on disk" case: it exports container logs into
# ./logs/<service>.log and rotates any *.log file that grows beyond MAX_SIZE:
#
#   app.log  ->  app.log.1.gz -> app.log.2.gz -> ... -> app.log.KEEP.gz -> deleted
#
# It uses copy-then-truncate, so a process holding the file open keeps writing
# to the same inode (same as logrotate's `copytruncate`).
#
# Usage: ./scripts/log-rotate.sh [-d DIR] [-s MAX_SIZE] [-k KEEP] [-c] [-g SIZE]
#   -d DIR       log directory              (default ./logs)
#   -s MAX_SIZE  rotate when larger than     (default 5M; accepts K/M/G)
#   -k KEEP      rotated files to keep       (default 5)
#   -c           collect new container logs into DIR first
#   -g SIZE      generate a dummy DIR/demo.log of SIZE to simulate a runaway log
#
# Demo:  ./scripts/log-rotate.sh -g 12M -s 5M      (creates a 12 MB log, then rotates it)
# Cron:  */15 * * * * /path/to/scripts/log-rotate.sh -c
# ---------------------------------------------------------------------------
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LOG_DIR="$PROJECT_ROOT/logs"; MAX_SIZE="5M"; KEEP=5; COLLECT=false; GENERATE=""
while getopts ":d:s:k:cg:h" opt; do
    case "$opt" in
        d) LOG_DIR="$OPTARG" ;;
        s) MAX_SIZE="$OPTARG" ;;
        k) KEEP="$OPTARG" ;;
        c) COLLECT=true ;;
        g) GENERATE="$OPTARG" ;;
        h) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown option -$OPTARG" ;;
    esac
done
MAX_BYTES="$(to_bytes "$MAX_SIZE")"
case "$KEEP" in ''|*[!0-9]*|0) die "KEEP must be a positive integer" ;; esac
mkdir -p "$LOG_DIR"

# Prevent two rotations running at once (e.g. overlapping cron runs).
# mkdir is atomic on every filesystem, unlike checking-then-creating a file.
LOCK="$LOG_DIR/.rotate.lock"
mkdir "$LOCK" 2>/dev/null || die "Another rotation is running (remove $LOCK if stale)"
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# --- 1. optional: export container logs -------------------------------------
collect_logs() {
    require docker
    local svc id since_file since now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for svc in api db; do
        id="$(service_container "$svc")"
        [ -n "$id" ] || { warn "$svc not running, skipped"; continue; }
        # Remember where we stopped so each run only appends new lines
        since_file="$LOG_DIR/.${svc}.since"
        since="$(cat "$since_file" 2>/dev/null || echo 1970-01-01T00:00:00Z)"
        docker logs --timestamps --since "$since" --until "$now" "$id" >> "$LOG_DIR/$svc.log" 2>&1
        echo "$now" > "$since_file"
        log "Collected $svc logs -> $svc.log ($(human_size "$(file_size "$LOG_DIR/$svc.log")"))"
    done
}

# --- 2. optional: create a fat log to demonstrate rotation ------------------
generate_log() {
    local target="$LOG_DIR/demo.log" bytes
    bytes="$(to_bytes "$1")"
    log "Generating $(human_size "$bytes") of fake log lines in $target"
    # awk is much faster than a bash loop for this
    awk -v max="$bytes" 'BEGIN {
        srand(); split("INFO WARN ERROR DEBUG", lv); n = 0; i = 0
        while (n < max) {
            line = sprintf("2026-01-01T00:00:%02d [%s] request id=%d path=/api/tasks status=200 duration_ms=%d", i % 60, lv[int(rand()*4)+1], i, int(rand()*500))
            print line; n += length(line) + 1; i++
        }
    }' >> "$target"
}

# --- 3. rotation ---------------------------------------------------------------
rotate_file() {
    local file="$1" size i
    size="$(file_size "$file")"
    if [ "$size" -le "$MAX_BYTES" ]; then
        printf '  %-28s %10s  ok\n' "$(basename "$file")" "$(human_size "$size")"
        return
    fi

    # Drop the oldest, shift the rest up by one: .4.gz -> .5.gz, ..., .1.gz -> .2.gz
    rm -f "$file.$KEEP.gz"
    for (( i = KEEP - 1; i >= 1; i-- )); do
        if [ -f "$file.$i.gz" ]; then mv "$file.$i.gz" "$file.$((i + 1)).gz"; fi
    done

    cp -p "$file" "$file.1"   # copy ...
    : > "$file"               # ... then truncate in place (writers keep their file descriptor)
    gzip -9 "$file.1"

    printf '  %-28s %10s  %srotated%s -> %s (%s)\n' "$(basename "$file")" "$(human_size "$size")" \
        "$C_YELLOW" "$C_RESET" "$(basename "$file").1.gz" "$(human_size "$(file_size "$file.1.gz")")"
}

[ "$COLLECT" = true ] && collect_logs
[ -n "$GENERATE" ] && generate_log "$GENERATE"

log "Rotating *.log in $LOG_DIR (max $MAX_SIZE, keep $KEEP)"
shopt -s nullglob
files=("$LOG_DIR"/*.log)
[ "${#files[@]}" -gt 0 ] || { log "No log files found"; exit 0; }
for f in "${files[@]}"; do rotate_file "$f"; done

ok "Done. Disk used by $LOG_DIR: $(du -sh "$LOG_DIR" | cut -f1)"
