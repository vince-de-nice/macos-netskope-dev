#!/usr/bin/env bash
#
# macos-netskope-dev — Configuration TLS Netskope pour dev macOS
#
# Configure individuellement ou en bloc (--all) les outils de développement
# Flutter/Android/iOS derrière Netskope, sans modifier les cacerts JDK.
#
# Usage :
#   ./install.sh --all --netskope
#   ./install.sh --gradle --netskope
#   ./install.sh --dart --git --netskope
#   ./install.sh --docs dart
#   ./install.sh --status
#   ./install.sh --rollback
#
# Admin (configuration pour un développeur) :
#   sudo ./install.sh --as-user jdupont --all --netskope --yes
#   Voir docs/ADMIN.md
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/manifest.sh"
source "$SCRIPT_DIR/lib/admin.sh"
source "$SCRIPT_DIR/lib/keychain.sh"
source "$SCRIPT_DIR/lib/certificate.sh"
source "$SCRIPT_DIR/lib/ca-bundle.sh"
source "$SCRIPT_DIR/lib/java.sh"
source "$SCRIPT_DIR/lib/gradle.sh"
source "$SCRIPT_DIR/lib/shell-profile.sh"
source "$SCRIPT_DIR/lib/tls-verify.sh"
source "$SCRIPT_DIR/lib/stacks.sh"
source "$SCRIPT_DIR/lib/rollback.sh"
source "$SCRIPT_DIR/lib/compliance.sh"

load_store_password() {
    if [[ -n "${MND_STORE_PASSWORD:-}" ]]; then
        STORE_PASSWORD="$MND_STORE_PASSWORD"
    elif [[ -n "${MND_STORE_PASSWORD_FILE:-}" && -f "$MND_STORE_PASSWORD_FILE" ]]; then
        STORE_PASSWORD="$(tr -d '[:space:]' < "$MND_STORE_PASSWORD_FILE")"
        [[ -n "$STORE_PASSWORD" ]] || die "Fichier mot de passe vide : $MND_STORE_PASSWORD_FILE"
    else
        STORE_PASSWORD="${TRUSTSTORE_PASSWORD:-$DEFAULT_STORE_PASSWORD}"
    fi
}

load_store_password
MANIFEST_ENTRIES=()

MODE=""
CERT_NAME=""
TLS_DISCOVERY_HOST="repo.maven.apache.org:443"
DO_ROLLBACK=false
ROLLBACK_STACK=""
LIST_NETSKOPE=false
SHOW_STATUS=false
SHOW_COMPLIANCE=false
COMPLIANCE_JSON=false
SHOW_DOCS=""
INSTALL_ALL=false
INCLUDE_SIMULATOR=false
SKIP_VERIFY=false
AUTO_ROLLBACK=true
FORCE_DISCOVER_TLS=false

SELECTED_STACKS=()
SHELL_PROFILE_OVERRIDE=""
CERT_FINGERPRINT=""

usage() {
    cat <<EOF

macos-netskope-dev v${SCRIPT_VERSION}

Configure les outils de dev Flutter/macOS pour Netskope (SSL inspection).

Usage :

  $0 --all --netskope              Toutes les stacks (sauf simulateur)
  $0 --all --simulator --netskope  Inclut le simulateur iOS booté
  $0 --gradle --netskope           Gradle/Android uniquement
  $0 --dart --git --netskope       Stacks au choix
  $0 --docs [STACK]                Documentation d'une stack
  $0 --status                      État de la configuration
  $0 --compliance [--json]         Conformité Intune/MDM (exit 0/1/2)
  $0 --rollback                    Restauration

Développeur (sur son propre compte) :

  $0 --all --netskope --yes
  source ~/.zshrc

Administrateur (pour un compte développeur) :

  sudo $0 --as-user <login> --all --netskope --yes
  sudo -u <login> $0 --status

  Guide complet : docs/ADMIN.md
  Ne pas exécuter sudo $0 sans --as-user (configurerait root).

Stacks (--all ou individuelles) :

  --gradle      JVM Gradle : truststore PKCS12 + gradle.properties
  --shell       Variables d'env dans ~/.zshrc (bundle CA central)
  --dart        Flutter/Dart : DART_VM_OPTIONS
  --git         Git HTTPS : http.sslCAInfo
  --node        npm : cafile + NODE_EXTRA_CA_CERTS
  --python      pip/requests : REQUESTS_CA_BUNDLE
  --ruby        CocoaPods/Ruby : SSL_CERT_FILE
  --curl        curl/Homebrew : CURL_CA_BUNDLE
  --gcloud      Google Cloud SDK
  --aws         AWS CLI : AWS_CA_BUNDLE
  --simulator   Simulateur iOS booté (certificats root)
  --go          Go toolchain (SSL_CERT_FILE)
  --rust        Rust/cargo (CARGO_HTTP_CAINFO)

Source des certificats (obligatoire sauf --status/--docs/--rollback) :

  --netskope          CA Netskope depuis le Keychain (recommandé)
  --cert "NOM"        Certificat par nom
  --discover-tls      Chaîne TLS + Keychain (nécessite --force, déconseillé)
  --force             Autorise --discover-tls (hors Netskope, usage avancé)

Autres options :

  --all               Toutes les stacks ci-dessus
  --list-netskope     Liste les CA Netskope du Keychain
  --tls-host H:PORT   Hôte pour --discover-tls
  --rollback          Restaure la configuration précédente
  --password PASS     Mot de passe truststore PKCS12 (défaut: changeit)
                        Préférer MND_STORE_PASSWORD ou MND_STORE_PASSWORD_FILE
  --shell-profile F   Profil shell cible (défaut: auto ~/.zshrc)
  --cert-fingerprint FP  Certificat Netskope par empreinte SHA-256 (8+ car.)
  --rollback-stack S  Rollback d'une stack (git, node, gcloud, shell, gradle)
  --skip-verify       Ignore les tests de connectivité
  --verbose           Logs détaillés
  --dry-run           Simulation
  --yes               Non interactif
  --no-auto-rollback  Désactive le rollback auto en cas d'échec
  --as-user LOGIN     Admin : exécuter pour le compte LOGIN (ex. jdupont)
  --compliance        Évalue la conformité (Intune Proactive Remediation)
  --json              Sortie JSON (avec --compliance)

Documentation : docs/README.md  |  docs/ADMIN.md  |  docs/INTUNE.md
                ./install.sh --docs STACK

Fichiers :

  Truststore : $TRUSTSTORE_FILE
  Bundle PEM : ${TRUSTSTORE_DIR}/nscacert_combined.pem
  Gradle     : $GRADLE_DIR/gradle.properties
  Rapport    : $REPORT_FILE

EOF
}

parse_args() {
    local tls_host="repo.maven.apache.org:443"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                INSTALL_ALL=true
                shift
                ;;
            --gradle|--shell|--dart|--git|--node|--python|--ruby|--curl|--gcloud|--aws|--go|--rust)
                SELECTED_STACKS+=("${1#--}")
                shift
                ;;
            --shell-profile)
                SHELL_PROFILE_OVERRIDE="${2:-}"
                [[ -n "$SHELL_PROFILE_OVERRIDE" ]] || die "Option --shell-profile requiert un chemin."
                export SHELL_PROFILE_OVERRIDE
                shift 2
                ;;
            --cert-fingerprint)
                CERT_FINGERPRINT="${2:-}"
                [[ -n "$CERT_FINGERPRINT" ]] || die "Option --cert-fingerprint requiert une empreinte."
                MODE="netskope"
                shift 2
                ;;
            --rollback-stack)
                ROLLBACK_STACK="${2:-}"
                [[ -n "$ROLLBACK_STACK" ]] || die "Option --rollback-stack requiert un nom de stack."
                DO_ROLLBACK=true
                shift 2
                ;;
            --simulator)
                INCLUDE_SIMULATOR=true
                SELECTED_STACKS+=("simulator")
                shift
                ;;
            --netskope)
                MODE="netskope"
                shift
                ;;
            --cert)
                MODE="cert"
                CERT_NAME="${2:-}"
                [[ -n "$CERT_NAME" ]] || die "Option --cert requiert un nom."
                shift 2
                ;;
            --discover-tls)
                MODE="discover-tls"
                shift
                ;;
            --force)
                FORCE_DISCOVER_TLS=true
                shift
                ;;
            --list-netskope)
                LIST_NETSKOPE=true
                shift
                ;;
            --tls-host)
                tls_host="${2:-}"
                [[ -n "$tls_host" ]] || die "Option --tls-host requiert HOST:PORT."
                shift 2
                ;;
            --rollback)
                DO_ROLLBACK=true
                shift
                ;;
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --compliance)
                SHOW_COMPLIANCE=true
                shift
                ;;
            --json)
                COMPLIANCE_JSON=true
                shift
                ;;
            --docs)
                if [[ -n "${2:-}" && "$2" != --* ]]; then
                    SHOW_DOCS="$2"
                    shift 2
                else
                    SHOW_DOCS="index"
                    shift
                fi
                ;;
            --password)
                STORE_PASSWORD="${2:-}"
                [[ -n "$STORE_PASSWORD" ]] || die "Option --password requiert une valeur."
                shift 2
                ;;
            --skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes|-y)
                NON_INTERACTIVE=true
                shift
                ;;
            --no-auto-rollback)
                AUTO_ROLLBACK=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Option inconnue : $1 (utilisez --help)"
                ;;
        esac
    done

    TLS_DISCOVERY_HOST="$tls_host"

    if [[ "$INSTALL_ALL" == true ]]; then
        SELECTED_STACKS=("${ALL_STACKS_DEFAULT[@]}")
        if [[ "$INCLUDE_SIMULATOR" == true ]]; then
            SELECTED_STACKS+=("simulator")
        fi
    fi

    # Rétrocompatibilité : --netskope ou --cert-fingerprint seul → gradle uniquement.
    if ((${#SELECTED_STACKS[@]} == 0)) && [[ -n "$MODE" || -n "$CERT_FINGERPRINT" ]]; then
        SELECTED_STACKS=("gradle")
    fi
}

validate_mode() {
    if [[ "$DO_ROLLBACK" == true || "$LIST_NETSKOPE" == true || "$SHOW_STATUS" == true \
        || "$SHOW_COMPLIANCE" == true || -n "$SHOW_DOCS" ]]; then
        return 0
    fi

    ((${#SELECTED_STACKS[@]} > 0)) || {
        usage
        exit 1
    }

    if [[ "$MODE" == "discover-tls" && "$FORCE_DISCOVER_TLS" != true ]]; then
        die "Option --discover-tls désactivée par défaut.

Derrière Netskope, utilisez --netskope (recommandé) pour exporter les CA d'entreprise depuis le Keychain.
--discover-tls importe la chaîne TLS publique d'un hôte (Let's Encrypt, etc.) et ne remplace pas les CA Netskope.

Si vous savez vraiment ce que vous faites : ajoutez --force"
    fi
}

list_netskope_certs() {
    local line label keychain count=0

    echo "Certificats Netskope dans le Keychain macOS :"
    echo

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        label="${line%%|*}"
        keychain="${line#*|}"
        echo "  - $label"
        echo "    Trousseau : $keychain"
        count=$((count + 1))
    done < <(find_netskope_certificates)

    echo
    if [[ "$count" -eq 0 ]]; then
        echo "Aucun certificat Netskope trouvé."
        exit 1
    fi

    echo "$count certificat(s) trouvé(s). Installation :"
    echo "  $0 --all --netskope"
}

prepare_certificates() {
    case "$MODE" in
        netskope)
            if [[ -n "$CERT_FINGERPRINT" ]]; then
                build_cert_export_list_by_fingerprint "$CERT_FINGERPRINT"
            else
                build_cert_export_list_netskope_auto
            fi
            ;;
        cert)
            build_cert_export_list_from_name "$CERT_NAME"
            ;;
        discover-tls)
            discover_chain_from_tls_and_keychain "$TLS_DISCOVERY_HOST"
            ;;
        *)
            die "Mode certificat inconnu : $MODE"
            ;;
    esac

    export_certificates_to_dir
    build_ca_bundle_from_exports
}

needs_gradle_stack() {
    local s
    for s in "${SELECTED_STACKS[@]}"; do
        [[ "$s" == "gradle" ]] && return 0
    done
    return 1
}

needs_certificate_export() {
    if [[ "${MND_CERTS_EXPORTED:-}" == "1" ]]; then
        return 1
    fi

    if ca_bundle_is_current; then
        return 1
    fi

    if [[ -f "$CA_BUNDLE_FILE" && -s "$CA_BUNDLE_FILE" ]] && ! needs_gradle_stack; then
        return 1
    fi

    return 0
}

has_reusable_certificate_material() {
    if needs_certificate_export; then
        return 1
    fi

    [[ -f "$CA_BUNDLE_FILE" && -s "$CA_BUNDLE_FILE" ]] && return 0
    certs_cache_has_pems && return 0

    return 1
}

validate_certificate_source() {
    if [[ -n "$MODE" || -n "$CERT_FINGERPRINT" ]]; then
        return 0
    fi

    if has_reusable_certificate_material; then
        log "Certificats existants détectés — réutilisation sans --netskope / --discover-tls."
        return 0
    fi

    die "Source de certificats requise : --netskope, --cert, --cert-fingerprint ou --discover-tls --force
(ou relancez après une première installation ayant exporté les CA dans ~/.gradle/macos-netskope-dev/)"
}

resolve_certificate_material() {
    if needs_certificate_export; then
        prepare_certificates
        return 0
    fi

    if load_exported_certs_from_cache; then
        log "Certificats chargés depuis le cache : $CERTS_CACHE_DIR"
    elif [[ -f "$CA_BUNDLE_FILE" && -s "$CA_BUNDLE_FILE" ]]; then
        log "Bundle CA existant réutilisé : $CA_BUNDLE_FILE"
        prepare_exported_certs_for_stacks
    else
        die "Matériel CA introuvable. Relancez avec --netskope, --discover-tls --force ou une autre source de certificats."
    fi
}

run_install() {
    local stack

    init_workdir
    reset_report
    ensure_dirs
    load_existing_manifest_entries
    validate_certificate_source

    CERT_EXPORT_DIR="$WORKDIR/certs"
    mkdir -p "$CERT_EXPORT_DIR"

    require_commands security openssl sed awk grep

    if needs_certificate_export; then
        [[ "$DRY_RUN" == true ]] || ensure_sudo
    fi

    if needs_gradle_stack; then
        require_commands keytool
        report_java_environment
        probe_tls_hosts_for_report
    fi

    resolve_certificate_material

    if [[ "$AUTO_ROLLBACK" == true && "$DRY_RUN" == false ]]; then
        begin_install_transaction
    fi

    for stack in "${SELECTED_STACKS[@]}"; do
        log "Configuration stack : $stack"
        report_line ""
        report_line "=== Stack: $stack ==="
        configure_stack "$stack"
        verify_stack "$stack"
    done

    if [[ "$AUTO_ROLLBACK" == true && "$DRY_RUN" == false ]]; then
        end_install_transaction
    fi

    save_manifest
    print_install_summary
}

main() {
    preparse_as_user "$@"
    maybe_reexec_as_user
    guard_root_install
    parse_args "${REMAINING_ARGS[@]}"
    require_macos
    validate_mode

    if [[ -n "$SHOW_DOCS" ]]; then
        if [[ "$SHOW_DOCS" == "index" ]]; then
            print_all_docs_index
        else
            print_stack_doc "$SHOW_DOCS"
        fi
        exit 0
    fi

    if [[ "$SHOW_STATUS" == true ]]; then
        print_install_status
        exit 0
    fi

    if [[ "$SHOW_COMPLIANCE" == true ]]; then
        local compliance_exit=0
        export COMPLIANCE_JSON="$COMPLIANCE_JSON"
        run_compliance_check || compliance_exit=$?
        exit "$compliance_exit"
    fi

    if [[ "$DO_ROLLBACK" == true ]]; then
        init_workdir
        reset_report
        if [[ -n "${ROLLBACK_STACK:-}" ]]; then
            perform_rollback_stack "$ROLLBACK_STACK"
        else
            perform_rollback
        fi
        echo
        echo "Rollback effectué. Consultez $REPORT_FILE"
        exit 0
    fi

    if [[ "$LIST_NETSKOPE" == true ]]; then
        list_netskope_certs
        exit 0
    fi

    run_install "$@"
}

main "$@"
