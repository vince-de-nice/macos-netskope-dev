#!/usr/bin/env bash
# shellcheck shell=bash
#
# Fonctions communes : logging, erreurs, privilèges, chemins, état.

: "${SCRIPT_VERSION:=4.0.0}"
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

DEFAULT_STORE_PASSWORD="changeit"
GRADLE_DIR="${GRADLE_DIR:-$HOME/.gradle}"
TRUSTSTORE_DIR="${TRUSTSTORE_DIR:-$GRADLE_DIR/corporate-truststore}"
TRUSTSTORE_FILE="${TRUSTSTORE_FILE:-$TRUSTSTORE_DIR/corporate-truststore.p12}"
STATE_DIR="${STATE_DIR:-$TRUSTSTORE_DIR/state}"
REPORT_FILE="${REPORT_FILE:-$TRUSTSTORE_DIR/install-report.txt}"
MANIFEST_FILE="${MANIFEST_FILE:-$STATE_DIR/manifest.json}"

MARKER_BEGIN="# BEGIN gradle-corporate-truststore"
MARKER_END="# END gradle-corporate-truststore"

VERBOSE=false
DRY_RUN=false
NON_INTERACTIVE=false

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    echo "[$(timestamp)] [INFO] $*"
}

warn() {
    echo "[$(timestamp)] [WARN] $*" >&2
}

error() {
    echo "[$(timestamp)] [ERROR] $*" >&2
}

debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[$(timestamp)] [DEBUG] $*" >&2
    fi
}

die() {
    error "$*"
    exit 1
}

require_macos() {
    [[ "$(uname -s)" == "Darwin" ]] || die "Ce script nécessite macOS."
}

require_commands() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if ((${#missing[@]} > 0)); then
        die "Commandes manquantes : ${missing[*]}"
    fi
}

ensure_sudo() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    if [[ "$EUID" -eq 0 ]]; then
        return 0
    fi

    if ! sudo -v; then
        die "Privilèges administrateur requis pour accéder au trousseau système."
    fi
}

confirm_or_die() {
    local prompt="$1"
    if [[ "$NON_INTERACTIVE" == true ]]; then
        return 0
    fi
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || die "Opération annulée par l'utilisateur."
}

init_workdir() {
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/gradle-truststore.XXXXXX")"
    trap 'cleanup_workdir' EXIT
}

cleanup_workdir() {
    [[ -n "${WORKDIR:-}" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
}

ensure_dirs() {
    mkdir -p "$TRUSTSTORE_DIR" "$STATE_DIR"
    chmod 700 "$TRUSTSTORE_DIR" "$STATE_DIR"
}

reset_report() {
    ensure_dirs
    {
        echo "Install Report"
        echo "Version: $SCRIPT_VERSION"
        echo "Date: $(date)"
        echo "Host: $(scutil --get ComputerName 2>/dev/null || hostname)"
        echo "User: $(whoami)"
        echo
    } > "$REPORT_FILE"
}

report_line() {
    echo "$*" >> "$REPORT_FILE"
}

sanitize_alias() {
    local input="$1"
    echo "$input" |
        tr '[:upper:]' '[:lower:]' |
        tr ' ' '-' |
        tr -cd 'a-z0-9._-'
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    printf '%s' "$s"
}

write_manifest_entry() {
    local key="$1"
    local value="$2"
    MANIFEST_ENTRIES+=("$(json_escape "$key")|$(json_escape "$value")")
}

save_manifest() {
    local entry key value
    ensure_dirs
    {
        echo "{"
        echo "  \"version\": \"$SCRIPT_VERSION\","
        echo "  \"created_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
        echo "  \"truststore_file\": \"$(json_escape "$TRUSTSTORE_FILE")\","
        echo "  \"store_password\": \"$(json_escape "${STORE_PASSWORD:-$DEFAULT_STORE_PASSWORD}")\","
        echo "  \"entries\": {"
        local first=true
        for entry in "${MANIFEST_ENTRIES[@]:-}"; do
            key="${entry%%|*}"
            value="${entry#*|}"
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": "%s"' "$key" "$value"
        done
        echo
        echo "  }"
        echo "}"
    } > "$MANIFEST_FILE"
}

load_manifest_value() {
    local key="$1"
    [[ -f "$MANIFEST_FILE" ]] || return 1
    sed -n "s/^[[:space:]]*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$MANIFEST_FILE" | head -1
}
