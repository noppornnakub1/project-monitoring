#!/usr/bin/env bash
# Shared helpers for the ops scripts. Source it, don't run it.
# Written for bash 3.2+ so it works on macOS as well as Linux.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_RESET=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi

log()   { printf '%s %s[INFO]%s  %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s %s[OK]%s    %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s %s[WARN]%s  %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$C_YELLOW" "$C_RESET" "$*" >&2; }
error() { printf '%s %s[ERROR]%s %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$C_RED"    "$C_RESET" "$*" >&2; }
die()   { error "$*"; exit 1; }

# True when this script is executing inside a container (e.g. `docker compose exec db bash /scripts/...`)
in_container() { [ -f /.dockerenv ] || grep -qE '(docker|containerd|kubepods)' /proc/1/cgroup 2>/dev/null; }

require() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
    done
}

# `docker compose` (v2) with fallback to legacy `docker-compose`, always pointed at this project
compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose -f "$PROJECT_ROOT/docker-compose.yml" --project-directory "$PROJECT_ROOT" "$@"
    else
        docker-compose -f "$PROJECT_ROOT/docker-compose.yml" --project-directory "$PROJECT_ROOT" "$@"
    fi
}

# Container id of a compose service ("" if not running)
service_container() { compose ps -q "$1" 2>/dev/null; }

# "10K" / "5M" / "1G" / "2048" -> bytes
to_bytes() {
    local v="$1" n unit
    n="${v%[KkMmGg]}"; unit="${v#"$n"}"
    case "$n" in ''|*[!0-9]*) die "Invalid size: $v" ;; esac
    case "$unit" in
        '')   echo "$n" ;;
        K|k)  echo $(( n * 1024 )) ;;
        M|m)  echo $(( n * 1024 * 1024 )) ;;
        G|g)  echo $(( n * 1024 * 1024 * 1024 )) ;;
    esac
}

# Portable file size in bytes (GNU and BSD stat differ, wc does not)
file_size() { wc -c < "$1" | tr -d ' '; }

human_size() {
    awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ } printf "%.1f %s", b, u[i] }'
}
