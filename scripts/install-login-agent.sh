#!/usr/bin/env bash
#
# Installe un LaunchDaemon ou LaunchAgent pour vérifier la conformité après connexion.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/intune-log.sh
source "$SCRIPT_DIR/lib/intune-log.sh"

MND_INSTALL_DIR="${MND_INSTALL_DIR:-/usr/local/share/macos-netskope-dev}"
PLIST_LABEL="com.macos-netskope-dev.login"
CHECK_INTERVAL="${MND_LOGIN_CHECK_INTERVAL:-600}"
AGENT_MODE="${MND_LOGIN_AGENT_MODE:-daemon}"
PLIST_PATH=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [--uninstall] [--agent daemon|launchagent]

Installe ou supprime le job de vérification post-connexion.
Doit s'exécuter en root.

  --agent daemon       LaunchDaemon système (défaut)
  --agent launchagent  LaunchAgent /Library/LaunchAgents (contexte utilisateur)

Intervalle ${CHECK_INTERVAL}s :
  ${MND_INSTALL_DIR}/scripts/intune-remediate.sh --login-only

Variables :
  MND_INSTALL_DIR           Chemin d'installation
  MND_LOGIN_CHECK_INTERVAL  Intervalle en secondes (défaut: 600)
  MND_LOGIN_AGENT_MODE      daemon | launchagent

EOF
}

resolve_plist_path() {
    case "$AGENT_MODE" in
        daemon)
            PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
            ;;
        launchagent)
            PLIST_PATH="/Library/LaunchAgents/${PLIST_LABEL}.plist"
            ;;
        *)
            intune_log_error "Mode agent inconnu : $AGENT_MODE"
            exit 2
            ;;
    esac
}

write_plist() {
    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${MND_INSTALL_DIR}/scripts/intune-remediate.sh</string>
        <string>--login-only</string>
    </array>
    <key>StartInterval</key>
    <integer>${CHECK_INTERVAL}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/macos-netskope-dev/login-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/macos-netskope-dev/login-daemon.err</string>
</dict>
</plist>
EOF
}

install_daemon() {
    local domain="system"

    intune_ensure_log_dir
    resolve_plist_path

    if [[ ! -x "${MND_INSTALL_DIR}/scripts/intune-remediate.sh" ]]; then
        intune_log_error "Script introuvable : ${MND_INSTALL_DIR}/scripts/intune-remediate.sh"
        exit 2
    fi

    write_plist
    chmod 644 "$PLIST_PATH"
    chown root:wheel "$PLIST_PATH"

    launchctl bootout "${domain}/${PLIST_LABEL}" 2>/dev/null || true
    launchctl bootstrap "$domain" "$PLIST_PATH"
    launchctl enable "${domain}/${PLIST_LABEL}"

    intune_log_info "Job installé ($AGENT_MODE) : $PLIST_PATH (intervalle ${CHECK_INTERVAL}s)"
}

uninstall_daemon() {
    resolve_plist_path
    launchctl bootout "system/${PLIST_LABEL}" 2>/dev/null || true
    launchctl bootout "gui/$(id -u 2>/dev/null || echo 0)/${PLIST_LABEL}" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    rm -f "/Library/LaunchDaemons/${PLIST_LABEL}.plist"
    rm -f "/Library/LaunchAgents/${PLIST_LABEL}.plist"
    intune_log_info "Job supprimé."
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            --agent)
                AGENT_MODE="${2:-daemon}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                intune_log_error "Option inconnue : $1"
                exit 2
                ;;
        esac
    done
}

UNINSTALL=false

main() {
    parse_args "$@"

    if [[ "$EUID" -ne 0 ]]; then
        intune_log_error "Ce script doit s'exécuter en root."
        exit 2
    fi

    if [[ "$UNINSTALL" == true ]]; then
        uninstall_daemon
    else
        install_daemon
    fi
}

main "$@"
