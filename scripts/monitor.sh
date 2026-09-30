#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Resource usage of the running containers (CPU / memory / network / disk I/O),
# with threshold alerts and optional CSV logging.
#
# Usage: ./scripts/monitor.sh [-w SECONDS] [-c CPU%] [-m MEM%] [-l]
#   -w SECONDS  watch mode: refresh every SECONDS (Ctrl+C to stop)
#   -c CPU%     CPU alert threshold  (default 80)
#   -m MEM%     memory alert threshold, % of the container limit (default 80)
#   -l          append samples to logs/monitor.csv
# Exit code 2 if any threshold was exceeded in single-shot mode.
# ---------------------------------------------------------------------------
set -Euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INTERVAL=0; CPU_LIMIT=80; MEM_LIMIT=80; LOG_CSV=false
while getopts ":w:c:m:lh" opt; do
    case "$opt" in
        w) INTERVAL="$OPTARG" ;;
        c) CPU_LIMIT="$OPTARG" ;;
        m) MEM_LIMIT="$OPTARG" ;;
        l) LOG_CSV=true ;;
        h) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown option -$OPTARG" ;;
    esac
done
require docker awk

CSV="$PROJECT_ROOT/logs/monitor.csv"
if [ "$LOG_CSV" = true ] && [ ! -f "$CSV" ]; then
    mkdir -p "$(dirname "$CSV")"
    echo "timestamp,container,cpu_pct,mem_usage,mem_pct,net_io,block_io,pids" > "$CSV"
fi

sample() {
    local ids stats alerts=0 ts
    ids="$(compose ps -q 2>/dev/null)"
    [ -n "$ids" ] || die "No running containers for this project"
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    # One docker stats call for all containers; fields separated by '|'
    stats="$(docker stats --no-stream --format \
        '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}' $ids)"

    printf '\n%s  Container resource usage  %s\n' "$C_BLUE" "$ts$C_RESET"
    printf '%-10s %8s %22s %8s %20s %20s %5s\n' CONTAINER CPU MEM_USAGE MEM% NET_IO BLOCK_IO PIDS
    while IFS='|' read -r name cpu mem memp net blk pids; do
        printf '%-10s %8s %22s %8s %20s %20s %5s\n' "$name" "$cpu" "$mem" "$memp" "$net" "$blk" "$pids"
        # strip the % sign and compare as floats with awk (bash has no float math)
        if awk -v v="${cpu%\%}" -v t="$CPU_LIMIT" 'BEGIN { exit !(v > t) }'; then
            warn "$name CPU ${cpu} exceeds ${CPU_LIMIT}%"; alerts=$((alerts + 1))
        fi
        if awk -v v="${memp%\%}" -v t="$MEM_LIMIT" 'BEGIN { exit !(v > t) }'; then
            warn "$name memory ${memp} exceeds ${MEM_LIMIT}% of its limit"; alerts=$((alerts + 1))
        fi
        if [ "$LOG_CSV" = true ]; then
            printf '%s,%s,%s,"%s",%s,"%s","%s",%s\n' "$ts" "$name" "${cpu%\%}" "$mem" "${memp%\%}" "$net" "$blk" "$pids" >> "$CSV"
        fi
    done <<<"$stats"

    # Storage: database volume size and backup directory usage
    local dbsize
    dbsize="$(compose exec -T db du -sh /var/lib/postgresql/data 2>/dev/null | cut -f1)"
    printf '\nStorage: pgdata volume=%s  backups=%s  host disk free=%s\n' \
        "${dbsize:-n/a}" \
        "$(du -sh "$PROJECT_ROOT/backups" 2>/dev/null | cut -f1)" \
        "$(df -h "$PROJECT_ROOT" | awk 'NR==2 { print $4 " (" $5 " used)" }')"
    return "$alerts"
}

if [ "$INTERVAL" -gt 0 ]; then
    trap 'echo; log "Stopped"; exit 0' INT TERM
    while :; do
        [ -t 1 ] && clear
        sample || true
        sleep "$INTERVAL"
    done
else
    sample; alerts=$?
    [ "$alerts" -eq 0 ] && ok "All containers within thresholds" || exit 2
fi
