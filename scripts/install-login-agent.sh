#!/usr/bin/env bash
#
# Installe un LaunchDaemon pour vérifier la conformité après connexion utilisateur.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/intune-log.sh
source "$SCRIPT_DIR/lib/intune-log.sh"

MND_INSTALL_DIR="${MND_INSTALL_DIR:-/usr/local/share/macos-netskope-dev}"
PLIST_LABEL="com.macos-netskope-dev.login"
PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
CHECK_INTERVAL="${MND_LOGIN_CHECK_INTERVAL:-600}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--uninstall]

Installe ou supprime le LaunchDaemon de vérification post-connexion.
Doit s'exécuter en root.

Le daemon exécute toutes les ${CHECK_INTERVAL}s :
  ${MND_INSTALL_DIR}/scripts/intune-remediate.sh --login-only

Variables :
  MND_INSTALL_DIR           Chemin d'installation
  MND_LOGIN_CHECK_INTERVAL  Intervalle en secondes (défaut: 600)

EOF
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
    intune_ensure_log_dir

    if [[ ! -x "${MND_INSTALL_DIR}/scripts/intune-remediate.sh" ]]; then
        intune_log_error "Script introuvable : ${MND_INSTALL_DIR}/scripts/intune-remediate.sh"
        exit 2
    fi

    write_plist
    chmod 644 "$PLIST_PATH"
    chown root:wheel "$PLIST_PATH"

    launchctl bootout "system/${PLIST_LABEL}" 2>/dev/null || true
    launchctl bootstrap system "$PLIST_PATH"
    launchctl enable "system/${PLIST_LABEL}"

    intune_log_info "LaunchDaemon installé : $PLIST_PATH (intervalle ${CHECK_INTERVAL}s)"
}

uninstall_daemon() {
    launchctl bootout "system/${PLIST_LABEL}" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    intune_log_info "LaunchDaemon supprimé."
}

main() {
    if [[ "$EUID" -ne 0 ]]; then
        intune_log_error "Ce script doit s'exécuter en root."
        exit 2
    fi

    case "${1:-install}" in
        --uninstall)
            uninstall_daemon
            ;;
        -h|--help)
            usage
            ;;
        *)
            install_daemon
            ;;
    esac
}

main "$@"
