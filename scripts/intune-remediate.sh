#!/usr/bin/env bash
#
# Script de remédiation Intune (Proactive Remediation + planification MDM).
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/intune-log.sh
source "$SCRIPT_DIR/lib/intune-log.sh"

GCT_INSTALL_DIR="${GCT_INSTALL_DIR:-/usr/local/share/gradle-corporate-truststore}"
INSTALL_SH="${GCT_INSTALL_DIR}/install.sh"
GCT_NETSKOPE_WAIT_SECS="${GCT_NETSKOPE_WAIT_SECS:-300}"
GCT_NETSKOPE_RETRY_INTERVAL="${GCT_NETSKOPE_RETRY_INTERVAL:-15}"
LOGIN_ONLY=false
FORCE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--login-only] [--force]

Remédiation Intune pour gradle-corporate-truststore.
Doit s'exécuter en root (script macOS Intune — gestion des appareils).

  --login-only   Remédie uniquement si non conforme (LaunchDaemon / connexion)
  --force        Force la réinstallation même si conforme

Variables :
  GCT_INSTALL_DIR              Chemin d'installation
  GCT_NETSKOPE_WAIT_SECS       Attente max CA Netskope (défaut: 300)
  GCT_NETSKOPE_RETRY_INTERVAL  Intervalle entre tentatives (défaut: 15)
  GCT_STORE_PASSWORD           Mot de passe truststore PKCS12 (optionnel)

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --login-only)
                LOGIN_ONLY=true
                shift
                ;;
            --force)
                FORCE=true
                shift
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

wait_for_netskope() {
    local deadline=$((SECONDS + GCT_NETSKOPE_WAIT_SECS))

    intune_log_info "Attente des certificats Netskope (max ${GCT_NETSKOPE_WAIT_SECS}s)..."

    while ((SECONDS < deadline)); do
        if "$INSTALL_SH" --list-netskope >/dev/null 2>&1; then
            intune_log_info "Certificats Netskope détectés."
            return 0
        fi
        sleep "$GCT_NETSKOPE_RETRY_INTERVAL"
    done

    intune_log_warn "Certificats Netskope non détectés après ${GCT_NETSKOPE_WAIT_SECS}s."
    return 1
}

remediate_user() {
    local target_user="$1"

    intune_log_info "Remédiation pour $target_user"

    wait_for_netskope || intune_log_warn "Poursuite sans certificats Netskope confirmés."

    if [[ -n "${GCT_STORE_PASSWORD:-}" ]]; then
        if sudo env GCT_STORE_PASSWORD="$GCT_STORE_PASSWORD" \
            "$INSTALL_SH" --as-user "$target_user" --all --netskope --yes \
            2>&1 | tee -a "$GCT_LOG_DIR/remediate.log"; then
            intune_log_info "Remédiation réussie pour $target_user"
            return 0
        fi
    elif sudo "$INSTALL_SH" --as-user "$target_user" --all --netskope --yes \
        2>&1 | tee -a "$GCT_LOG_DIR/remediate.log"; then
        intune_log_info "Remédiation réussie pour $target_user"
        return 0
    fi

    intune_log_error "Remédiation échouée pour $target_user (voir $GCT_LOG_DIR/remediate.log)"
    return 1
}

main() {
    local target_user target_home compliance_exit=0

    parse_args "$@"
    intune_ensure_log_dir

    if [[ "$EUID" -ne 0 ]]; then
        intune_log_error "Ce script doit s'exécuter en root."
        exit 2
    fi

    if [[ ! -x "$INSTALL_SH" ]]; then
        intune_log_error "install.sh introuvable : $INSTALL_SH"
        exit 2
    fi

    target_user="$(intune_get_console_user)" || {
        intune_log_warn "Aucun utilisateur console — remédiation ignorée."
        exit 0
    }

    target_home="$(intune_resolve_user_home "$target_user")" || {
        intune_log_error "Home introuvable pour : $target_user"
        exit 2
    }

    if [[ "$LOGIN_ONLY" == true && "$FORCE" != true ]]; then
        sudo -u "$target_user" \
            env HOME="$target_home" USER="$target_user" LOGNAME="$target_user" \
            "$INSTALL_SH" --compliance >/dev/null 2>&1 || compliance_exit=$?

        if [[ "$compliance_exit" -eq 0 ]]; then
            intune_log_info "$target_user déjà conforme — aucune action."
            exit 0
        fi
        intune_log_info "$target_user non conforme (exit $compliance_exit) — remédiation."
    fi

    remediate_user "$target_user"
}

main "$@"
