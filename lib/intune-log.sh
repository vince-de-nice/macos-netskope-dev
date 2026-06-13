#!/usr/bin/env bash
# shellcheck shell=bash
#
# Journalisation centralisée pour scripts Intune / MDM.

MND_LOG_DIR="${MND_LOG_DIR:-/var/log/macos-netskope-dev}"
MND_RUN_ID="${MND_RUN_ID:-mnd-$(date +%Y%m%d%H%M%S)-$$}"

intune_ensure_log_dir() {
    if [[ "$EUID" -eq 0 ]]; then
        mkdir -p "$MND_LOG_DIR"
        chmod 755 "$MND_LOG_DIR"
        if [[ ! -f "$MND_LOG_DIR/.logrotate_hint" ]]; then
            cat > "$MND_LOG_DIR/.logrotate_hint" <<'EOF'
# Exemple newsyslog (/etc/newsyslog.d/macos-netskope-dev.conf) :
# /var/log/macos-netskope-dev/*.log  644  root  wheel  7  10240  *
EOF
        fi
    fi
}

intune_log() {
    local level="$1"
    local message
    shift
    message="[$(date '+%Y-%m-%d %H:%M:%S')] [$MND_RUN_ID] [$level] $*"

    echo "$message"
    if [[ "$EUID" -eq 0 && -d "$MND_LOG_DIR" ]]; then
        echo "$message" >> "$MND_LOG_DIR/intune.log"
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

intune_list_target_users() {
    local -a users=()
    local item

    if [[ -n "${MND_TARGET_USERS:-}" ]]; then
        IFS=',' read -ra users <<< "${MND_TARGET_USERS// /}"
        for item in "${users[@]}"; do
            [[ -n "$item" ]] && echo "$item"
        done
        return 0
    fi

    intune_get_console_user || return 1
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
