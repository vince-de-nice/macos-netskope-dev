#!/usr/bin/env bash
#
# Script de détection Intune (Proactive Remediation).
# Exit 0 = conforme, 1 = remédiation requise, 2 = erreur.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/intune-log.sh
source "$SCRIPT_DIR/lib/intune-log.sh"

MND_INSTALL_DIR="${MND_INSTALL_DIR:-/usr/local/share/macos-netskope-dev}"
INSTALL_SH="${MND_INSTALL_DIR}/install.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--json]

Détection de conformité pour Microsoft Intune Proactive Remediation.
Doit s'exécuter en root (script macOS Intune — gestion des appareils).

Variables :
  MND_INSTALL_DIR          Chemin d'installation (défaut: /usr/local/share/macos-netskope-dev)
  MND_LOG_DIR              Journal (/var/log/macos-netskope-dev)
  MND_SKIP_IF_NO_USER=1    Exit 0 si aucun utilisateur console (défaut: 1)

EOF
}

OUTPUT_JSON=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                OUTPUT_JSON=true
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

write_skip_json() {
    local reason="$1"
    cat <<EOF
{
  "status": "skipped",
  "compliant": true,
  "reason": "$(printf '%s' "$reason" | sed 's/"/\\"/g')",
  "checked_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

main() {
    local target_user target_home compliance_args=() exit_code=0 json_output

    parse_args "$@"
    intune_ensure_log_dir

    if [[ "$EUID" -ne 0 ]]; then
        intune_log_error "Ce script doit s'exécuter en root (contexte Intune appareil)."
        exit 2
    fi

    if [[ ! -x "$INSTALL_SH" ]]; then
        intune_log_error "install.sh introuvable : $INSTALL_SH"
        exit 2
    fi

    target_user="$(intune_get_console_user)" || {
        intune_log_warn "Aucun utilisateur console — détection ignorée."
        if [[ "$OUTPUT_JSON" == true ]]; then
            write_skip_json "no_console_user"
        fi
        if [[ "${MND_SKIP_IF_NO_USER:-1}" == "1" ]]; then
            exit 0
        fi
        exit 1
    }

    target_home="$(intune_resolve_user_home "$target_user")" || {
        intune_log_error "Home introuvable pour : $target_user"
        exit 2
    }

    intune_log_info "Détection conformité pour $target_user ($target_home)"

    compliance_args=(--compliance)
    [[ "$OUTPUT_JSON" == true ]] && compliance_args+=(--json)

    json_output="$(sudo -u "$target_user" \
        env HOME="$target_home" USER="$target_user" LOGNAME="$target_user" \
        COMPLIANCE_JSON="${OUTPUT_JSON}" \
        "$INSTALL_SH" "${compliance_args[@]}" 2>&1)" || exit_code=$?

    if [[ "$OUTPUT_JSON" == true ]]; then
        echo "$json_output"
    else
        echo "$json_output"
    fi

    local report_path="$target_home/.gradle/macos-netskope-dev/compliance-report.json"

    if [[ -f "$report_path" ]]; then
        cp "$report_path" "$MND_LOG_DIR/${target_user}-compliance.json" 2>/dev/null || true
    fi

    intune_log_info "Résultat détection : exit $exit_code"
    exit "$exit_code"
}

main "$@"
