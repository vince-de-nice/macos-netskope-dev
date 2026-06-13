#!/usr/bin/env bash
# shellcheck shell=bash
#
# Journalisation centralisée pour scripts Intune / MDM.

GCT_LOG_DIR="${GCT_LOG_DIR:-/var/log/gradle-corporate-truststore}"

intune_ensure_log_dir() {
    if [[ "$EUID" -eq 0 ]]; then
        mkdir -p "$GCT_LOG_DIR"
        chmod 755 "$GCT_LOG_DIR"
    fi
}

intune_log() {
    local level="$1"
    local message
    shift
    message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"

    echo "$message"
    if [[ "$EUID" -eq 0 && -d "$GCT_LOG_DIR" ]]; then
        echo "$message" >> "$GCT_LOG_DIR/intune.log"
    fi
}

intune_log_info() {
    intune_log "INFO" "$@"
}

intune_log_warn() {
    intune_log "WARN" "$@" >&2
}

intune_log_error() {
    intune_log "ERROR" "$@" >&2
}

intune_get_console_user() {
    local user

    user="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)"
    if [[ -z "$user" || "$user" == "root" || "$user" == "_mbsetupuser" || "$user" == "loginwindow" ]]; then
        return 1
    fi
    echo "$user"
}

intune_resolve_user_home() {
    local username="$1"
    local home=""

    if [[ "$EUID" -eq 0 ]]; then
        home="$(dscl . -read "/Users/$username" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    else
        home="$(eval echo "~$username" 2>/dev/null || true)"
    fi

    [[ -z "$home" ]] && home="/Users/$username"
    [[ -d "$home" ]] || return 1
    echo "$home"
}
