#!/usr/bin/env bash
#
# Script de remédiation Intune (Proactive Remediation + planification MDM).
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/intune-log.sh
source "$SCRIPT_DIR/lib/intune-log.sh"

MND_INSTALL_DIR="${MND_INSTALL_DIR:-/usr/local/share/macos-netskope-dev}"
INSTALL_SH="${MND_INSTALL_DIR}/install.sh"
MND_NETSKOPE_WAIT_SECS="${MND_NETSKOPE_WAIT_SECS:-300}"
MND_NETSKOPE_RETRY_INTERVAL="${MND_NETSKOPE_RETRY_INTERVAL:-15}"
MND_NETSKOPE_REQUIRED="${MND_NETSKOPE_REQUIRED:-1}"
LOGIN_ONLY=false
FORCE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--login-only] [--force]

Remédiation Intune pour macos-netskope-dev.
Doit s'exécuter en root (script macOS Intune — gestion des appareils).

  --login-only   Remédie uniquement si non conforme (LaunchDaemon / connexion)
  --force        Force la réinstallation même si conforme

Variables :
  MND_INSTALL_DIR              Chemin d'installation
  MND_NETSKOPE_WAIT_SECS       Attente max CA Netskope (défaut: 300)
  MND_NETSKOPE_RETRY_INTERVAL  Intervalle entre tentatives (défaut: 15)
  MND_NETSKOPE_REQUIRED=1        Échoue si CA absentes après attente (défaut: 1)
  MND_STORE_PASSWORD             Mot de passe truststore PKCS12 (optionnel)
  MND_STORE_PASSWORD_FILE        Fichier mot de passe (recommandé Intune)
  MND_TARGET_USERS               Liste login séparés par virgule (multi-user)

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
    local deadline=$((SECONDS + MND_NETSKOPE_WAIT_SECS))

    intune_log_info "Attente des certificats Netskope (max ${MND_NETSKOPE_WAIT_SECS}s)..."

    while ((SECONDS < deadline)); do
        if "$INSTALL_SH" --list-netskope >/dev/null 2>&1; then
            intune_log_info "Certificats Netskope détectés."
            return 0
        fi
        sleep "$MND_NETSKOPE_RETRY_INTERVAL"
    done

    intune_log_warn "Certificats Netskope non détectés après ${MND_NETSKOPE_WAIT_SECS}s."
    return 1
}

remediate_user() {
    local target_user="$1"
    local -a install_env=()

    intune_log_info "Remédiation pour $target_user"

    if ! wait_for_netskope; then
        if [[ "$MND_NETSKOPE_REQUIRED" == "1" ]]; then
            intune_log_error "CA Netskope requises — remédiation annulée pour $target_user."
            return 1
        fi
        intune_log_warn "Poursuite sans certificats Netskope confirmés."
    fi

    if [[ -n "${MND_STORE_PASSWORD_FILE:-}" && -f "$MND_STORE_PASSWORD_FILE" ]]; then
        install_env+=(MND_STORE_PASSWORD_FILE="$MND_STORE_PASSWORD_FILE")
    elif [[ -n "${MND_STORE_PASSWORD:-}" ]]; then
        install_env+=(MND_STORE_PASSWORD="$MND_STORE_PASSWORD")
    fi

    if ((${#install_env[@]} > 0)); then
        if env "${install_env[@]}" \
            "$INSTALL_SH" --as-user "$target_user" --all --netskope --yes \
            2>&1 | tee -a "$MND_LOG_DIR/remediate.log"; then
            intune_log_info "Remédiation réussie pour $target_user"
            return 0
        fi
    elif "$INSTALL_SH" --as-user "$target_user" --all --netskope --yes \
        2>&1 | tee -a "$MND_LOG_DIR/remediate.log"; then
        intune_log_info "Remédiation réussie pour $target_user"
        return 0
    fi

    intune_log_error "Remédiation échouée pour $target_user (voir $MND_LOG_DIR/remediate.log)"
    return 1
}

should_remediate_user() {
    local target_user="$1"
    local target_home compliance_exit=0

    if [[ "$LOGIN_ONLY" != true || "$FORCE" == true ]]; then
        return 0
    fi

    target_home="$(intune_resolve_user_home "$target_user")" || return 1

    sudo -u "$target_user" \
        env HOME="$target_home" USER="$target_user" LOGNAME="$target_user" \
        "$INSTALL_SH" --compliance >/dev/null 2>&1 || compliance_exit=$?

    if [[ "$compliance_exit" -eq 0 ]]; then
        intune_log_info "$target_user déjà conforme — aucune action."
        return 1
    fi

    intune_log_info "$target_user non conforme (exit $compliance_exit) — remédiation."
    return 0
}

main() {
    local target_user failed=0 remediated=0

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

    while IFS= read -r target_user; do
        [[ -n "$target_user" ]] || continue
        should_remediate_user "$target_user" || continue
        if remediate_user "$target_user"; then
            remediated=$((remediated + 1))
        else
            failed=$((failed + 1))
        fi
    done < <(intune_list_target_users)

    if [[ "$remediated" -eq 0 && "$failed" -eq 0 ]]; then
        intune_log_warn "Aucun utilisateur cible — remédiation ignorée."
        exit 0
    fi

    if [[ "$failed" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
