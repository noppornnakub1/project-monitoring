#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Health check for the whole stack. Exit code 0 = healthy, 1 = something is wrong,
# so it can be used by cron / CI / other monitoring.
#
# Checks per service: container running, Docker HEALTHCHECK status, restart count,
# plus application-level probes: pg_isready (db) and GET /health (api).
#
# Usage: ./scripts/healthcheck.sh [-w SECONDS] [-u API_URL]
#   -w SECONDS  keep retrying until healthy or the timeout expires (e.g. right after `up`)
#   -u API_URL  base URL of the API (default: http://localhost:${API_PORT:-8080})
# ---------------------------------------------------------------------------
set -Euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WAIT=0
API_URL="http://localhost:${API_PORT:-8080}"
while getopts ":w:u:h" opt; do
    case "$opt" in
        w) WAIT="$OPTARG" ;;
        u) API_URL="$OPTARG" ;;
        h) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown option -$OPTARG" ;;
    esac
done
require docker curl

FAILURES=0
fail() { error "$*"; FAILURES=$((FAILURES + 1)); }

check_container() {
    local svc="$1" id state health restarts
    id="$(compose ps -a -q "$svc" 2>/dev/null)"   # -a: also report stopped/crashed containers
    if [ -z "$id" ]; then fail "$svc: container not found (is the stack up?)"; return; fi

    read -r state health restarts <<<"$(docker inspect -f \
        '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} {{.RestartCount}}' "$id")"

    printf '  %-6s state=%-8s health=%-10s restarts=%s\n' "$svc" "$state" "$health" "$restarts"
    [ "$state" = "running" ] || fail "$svc: container is $state"
    case "$health" in
        healthy|none) ;;
        starting) fail "$svc: still starting" ;;
        *) fail "$svc: health=$health"
           docker inspect -f '{{range .State.Health.Log}}    {{.Output}}{{end}}' "$id" | tail -n 3 >&2 ;;
    esac
    [ "$restarts" -lt 3 ] || warn "$svc: restarted $restarts times - check logs: docker compose logs $svc"
}

check_db() {
    if compose exec -T db sh -c 'pg_isready -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
        printf '  %-6s pg_isready: accepting connections\n' db
    else
        fail "db: pg_isready failed"
    fi
}

check_api() {
    local body code
    body="$(curl -s -m 5 -w $'\n%{http_code}' "$API_URL/health" 2>/dev/null)" || true
    code="${body##*$'\n'}"; body="${body%$'\n'*}"
    if [ "$code" = "200" ]; then
        printf '  %-6s GET /health -> %s %s\n' api "$code" "$body"
    else
        fail "api: GET $API_URL/health -> ${code:-no response} ${body}"
    fi
}

run_checks() {
    FAILURES=0
    log "Checking containers"
    check_container db
    check_container api
    log "Checking services"
    check_db
    check_api
}

DEADLINE=$(( $(date +%s) + WAIT ))
while :; do
    run_checks
    [ "$FAILURES" -eq 0 ] && { ok "All checks passed"; exit 0; }
    [ "$(date +%s)" -lt "$DEADLINE" ] || break
    warn "$FAILURES check(s) failing, retrying in 3s ..."
    sleep 3
done
error "$FAILURES check(s) failed"
exit 1
