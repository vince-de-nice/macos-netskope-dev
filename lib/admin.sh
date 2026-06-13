#!/usr/bin/env bash
# shellcheck shell=bash
#
# Exécution par un administrateur au nom d'un développeur (--as-user).

INSTALL_AS_USER=""
REMAINING_ARGS=()

ADMIN_INSTALL_MODE=""
ADMIN_CERT_NAME=""
ADMIN_TLS_HOST="repo.maven.apache.org:443"
ADMIN_DO_ROLLBACK=false
ADMIN_SHOW_STATUS=false
ADMIN_SHOW_DOCS=""
ADMIN_LIST_NETSKOPE=false
ADMIN_DRY_RUN=false

preparse_as_user() {
    INSTALL_AS_USER=""
    REMAINING_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --as-user)
                INSTALL_AS_USER="${2:-}"
                [[ -n "$INSTALL_AS_USER" ]] ||
                    die "Option --as-user requiert le login macOS du développeur."
                shift 2
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

preparse_install_flags() {
    local args=("$@")
    local i=0

    ADMIN_INSTALL_MODE=""
    ADMIN_CERT_NAME=""
    ADMIN_TLS_HOST="repo.maven.apache.org:443"
    ADMIN_DO_ROLLBACK=false
    ADMIN_SHOW_STATUS=false
    ADMIN_SHOW_DOCS=""
    ADMIN_LIST_NETSKOPE=false
    ADMIN_DRY_RUN=false

    while ((i < ${#args[@]})); do
        case "${args[$i]}" in
            --netskope)
                ADMIN_INSTALL_MODE="netskope"
                ;;
            --cert)
                ADMIN_INSTALL_MODE="cert"
                ADMIN_CERT_NAME="${args[$((i + 1))]:-}"
                i=$((i + 1))
                ;;
            --discover-tls)
                ADMIN_INSTALL_MODE="discover-tls"
                ;;
            --tls-host)
                ADMIN_TLS_HOST="${args[$((i + 1))]:-}"
                i=$((i + 1))
                ;;
            --rollback)
                ADMIN_DO_ROLLBACK=true
                ;;
            --status)
                ADMIN_SHOW_STATUS=true
                ;;
            --docs)
                if [[ -n "${args[$((i + 1))]:-}" && "${args[$((i + 1))]}" != --* ]]; then
                    ADMIN_SHOW_DOCS="${args[$((i + 1))]}"
                    i=$((i + 1))
                else
                    ADMIN_SHOW_DOCS="index"
                fi
                ;;
            --list-netskope)
                ADMIN_LIST_NETSKOPE=true
                ;;
            --dry-run)
                ADMIN_DRY_RUN=true
                ;;
        esac
        i=$((i + 1))
    done
}

admin_install_requires_cert_export() {
    [[ "$ADMIN_DO_ROLLBACK" == true ]] && return 1
    [[ "$ADMIN_SHOW_STATUS" == true ]] && return 1
    [[ -n "$ADMIN_SHOW_DOCS" ]] && return 1
    [[ "$ADMIN_LIST_NETSKOPE" == true ]] && return 1
    [[ -n "$ADMIN_INSTALL_MODE" ]]
}

apply_user_paths() {
    local target_home="$1"

    export HOME="$target_home"
    export USER="$INSTALL_AS_USER"
    export LOGNAME="$INSTALL_AS_USER"
    export GRADLE_DIR="$target_home/.gradle"
    export TRUSTSTORE_DIR="$GRADLE_DIR/corporate-truststore"
    export TRUSTSTORE_FILE="$TRUSTSTORE_DIR/corporate-truststore.p12"
    export STATE_DIR="$TRUSTSTORE_DIR/state"
    export REPORT_FILE="$TRUSTSTORE_DIR/install-report.txt"
    export MANIFEST_FILE="$STATE_DIR/manifest.json"
    export CA_BUNDLE_FILE="$TRUSTSTORE_DIR/nscacert_combined.pem"
    export CERTS_CACHE_DIR="$TRUSTSTORE_DIR/certs"
}

admin_export_certs_for_user() {
    local username="$1"
    local target_home admin_workdir saved_home saved_gradle saved_truststore saved_state saved_manifest saved_bundle saved_certs

    preparse_install_flags "${@:2}"
    admin_install_requires_cert_export || return 0
    [[ "$ADMIN_DRY_RUN" == true ]] && return 0

    target_home="$(resolve_user_home "$username")" ||
        die "Utilisateur introuvable ou répertoire home absent : $username"

    log "Export Keychain (root) pour : $username → $target_home"

    saved_home="$HOME"
    saved_gradle="$GRADLE_DIR"
    saved_truststore="$TRUSTSTORE_DIR"
    saved_state="$STATE_DIR"
    saved_manifest="$MANIFEST_FILE"
    saved_bundle="$CA_BUNDLE_FILE"
    saved_certs="$CERTS_CACHE_DIR"

    apply_user_paths "$target_home"

    admin_workdir="$(mktemp -d "${TMPDIR:-/tmp}/gradle-truststore-admin.XXXXXX")"
    WORKDIR="$admin_workdir"
    CERT_EXPORT_DIR="$WORKDIR/certs"
    mkdir -p "$CERT_EXPORT_DIR" "$TRUSTSTORE_DIR" "$STATE_DIR"
    chmod 700 "$TRUSTSTORE_DIR" "$STATE_DIR"

    load_existing_manifest_entries

    MODE="$ADMIN_INSTALL_MODE"
    CERT_NAME="$ADMIN_CERT_NAME"
    TLS_DISCOVERY_HOST="$ADMIN_TLS_HOST"

    case "$MODE" in
        netskope)
            build_cert_export_list_netskope_auto
            ;;
        cert)
            [[ -n "$CERT_NAME" ]] || die "Option --cert requiert un nom."
            build_cert_export_list_from_name "$CERT_NAME"
            ;;
        discover-tls)
            discover_chain_from_tls_and_keychain "$TLS_DISCOVERY_HOST"
            ;;
    esac

    export_certificates_to_dir
    build_ca_bundle_from_exports
    save_manifest

    rm -rf "$admin_workdir"
    WORKDIR=""

    export HOME="$saved_home"
    export GRADLE_DIR="$saved_gradle"
    export TRUSTSTORE_DIR="$saved_truststore"
    export STATE_DIR="$saved_state"
    export MANIFEST_FILE="$saved_manifest"
    export CA_BUNDLE_FILE="$saved_bundle"
    export CERTS_CACHE_DIR="$saved_certs"

    log "Certificats exportés dans : $target_home/.gradle/corporate-truststore/"
}

resolve_user_home() {
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

maybe_reexec_as_user() {
    local target_home

    [[ -n "$INSTALL_AS_USER" ]] || return 0
    [[ "$(whoami)" == "$INSTALL_AS_USER" ]] && return 0

    target_home="$(resolve_user_home "$INSTALL_AS_USER")" ||
        die "Utilisateur introuvable ou répertoire home absent : $INSTALL_AS_USER"

    if [[ "$EUID" -eq 0 ]]; then
        admin_export_certs_for_user "$INSTALL_AS_USER" "${REMAINING_ARGS[@]}"
    fi

    log "Exécution au nom de : $INSTALL_AS_USER (home: $target_home)"

    exec sudo -u "$INSTALL_AS_USER" \
        env HOME="$target_home" USER="$INSTALL_AS_USER" LOGNAME="$INSTALL_AS_USER" \
        GCT_CERTS_EXPORTED=1 \
        "$SCRIPT_DIR/install.sh" "${REMAINING_ARGS[@]}"
}

guard_root_install() {
    if [[ "$EUID" -eq 0 && -z "$INSTALL_AS_USER" ]]; then
        die "Installation en root interdite.

Ce script configure le compte utilisateur courant (~/.gradle, ~/.zshrc, git global, etc.).
Relancez de l'une des façons suivantes :

  • En tant que développeur (recommandé) :
      ./install.sh --all --netskope --yes

  • En tant qu'admin, pour un développeur :
      sudo ./install.sh --as-user <login> --all --netskope --yes

Voir docs/ADMIN.md pour le guide administrateur."
    fi
}
