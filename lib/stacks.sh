#!/usr/bin/env bash
# shellcheck shell=bash
#
# Configuration par stack (Gradle, Dart, Git, Node, …) pour Flutter + Netskope.

# Stacks disponibles (ordre d'exécution pour --all).
ALL_STACKS=(
    gradle
    shell
    dart
    git
    node
    python
    ruby
    curl
    gcloud
    aws
    simulator
)

CONFIGURED_STACKS=()

stack_doc_file() {
    local stack="$1"
    echo "$SCRIPT_DIR/docs/stacks/${stack}.md"
}

print_stack_doc() {
    local stack="$1"
    local doc_file
    doc_file="$(stack_doc_file "$stack")"
    [[ -f "$doc_file" ]] || die "Documentation introuvable pour la stack '$stack' : $doc_file"
    cat "$doc_file"
}

print_all_docs_index() {
    local stack doc_file
    echo "Documentation gradle-corporate-truststore v${SCRIPT_VERSION}"
    echo
    echo "Guides :"
    echo "  docs/README.md     — développeur"
    echo "  docs/ADMIN.md      — administrateur IT"
    echo
    echo "Stacks disponibles :"
    echo
    for stack in "${ALL_STACKS[@]}"; do
        doc_file="$(stack_doc_file "$stack")"
        if [[ -f "$doc_file" ]]; then
            echo "  ./install.sh --docs $stack"
            echo "    → docs/stacks/${stack}.md"
        fi
    done
    echo
    echo "Index complet : docs/README.md"
}

mark_stack_configured() {
    local stack="$1"
    CONFIGURED_STACKS+=("$stack")
    write_manifest_entry "stack_${stack}" "configured"
}

configure_stack_gradle() {
    if ca_bundle_is_current && [[ -f "$TRUSTSTORE_FILE" ]]; then
        prepare_exported_certs_for_stacks || true
        log "Truststore à jour — réimport ignoré"
    else
        import_all_exported_certificates
    fi
    configure_gradle_properties
    mark_stack_configured "gradle"
}

configure_stack_shell() {
    ensure_ca_bundle_exists
    write_shell_profile_block
    mark_stack_configured "shell"
}

configure_stack_dart() {
    ensure_ca_bundle_exists
    if [[ "$SHELL_BLOCK_WRITTEN" != true ]]; then
        write_shell_profile_block
    fi
    mark_stack_configured "dart"
    log "Dart/Flutter : utilisez DART_VM_OPTIONS (profil shell ou export manuel)."
    report_line "Dart: DART_VM_OPTIONS via shell profile"
}

configure_stack_git() {
    ensure_ca_bundle_exists
    if [[ "$DRY_RUN" == false ]]; then
        git config --global http.sslCAInfo "$CA_BUNDLE_FILE"
        write_manifest_entry "git_ssl_ca_info" "$CA_BUNDLE_FILE"
    fi
    log "Git configuré : http.sslCAInfo → $CA_BUNDLE_FILE"
    report_line "Git: http.sslCAInfo=$CA_BUNDLE_FILE"
    mark_stack_configured "git"
}

configure_stack_node() {
    ensure_ca_bundle_exists
    if command -v npm >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == false ]]; then
            npm config set cafile "$CA_BUNDLE_FILE" --location=user 2>/dev/null || \
                npm config set cafile "$CA_BUNDLE_FILE"
            write_manifest_entry "npm_cafile" "$CA_BUNDLE_FILE"
        fi
        log "npm configuré : cafile → $CA_BUNDLE_FILE"
        report_line "npm: cafile=$CA_BUNDLE_FILE"
    else
        warn "npm absent — NODE_EXTRA_CA_CERTS via profil shell uniquement."
    fi
    if [[ "$SHELL_BLOCK_WRITTEN" != true ]]; then
        write_shell_profile_block
    fi
    mark_stack_configured "node"
}

configure_stack_python() {
    ensure_ca_bundle_exists
    if [[ "$SHELL_BLOCK_WRITTEN" != true ]]; then
        write_shell_profile_block
    fi
    mark_stack_configured "python"
    log "Python : REQUESTS_CA_BUNDLE / SSL_CERT_FILE via profil shell."
    report_line "Python: env via shell profile"
}

configure_stack_ruby() {
    ensure_ca_bundle_exists
    if [[ "$SHELL_BLOCK_WRITTEN" != true ]]; then
        write_shell_profile_block
    fi
    mark_stack_configured "ruby"
    log "Ruby/CocoaPods : SSL_CERT_FILE via profil shell."
    report_line "Ruby: SSL_CERT_FILE via shell profile"
}

configure_stack_curl() {
    ensure_ca_bundle_exists
    if [[ "$SHELL_BLOCK_WRITTEN" != true ]]; then
        write_shell_profile_block
    fi
    mark_stack_configured "curl"
    log "curl : CURL_CA_BUNDLE via profil shell."
    report_line "curl: CURL_CA_BUNDLE via shell profile"
}

configure_stack_gcloud() {
    ensure_ca_bundle_exists
    if command -v gcloud >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == false ]]; then
            gcloud config set core/custom_ca_certs_file "$CA_BUNDLE_FILE" >/dev/null 2>&1 || true
            write_manifest_entry "gcloud_custom_ca" "$CA_BUNDLE_FILE"
        fi
        log "gcloud configuré : core/custom_ca_certs_file → $CA_BUNDLE_FILE"
        report_line "gcloud: custom_ca_certs_file=$CA_BUNDLE_FILE"
    else
        warn "gcloud absent — configuration ignorée."
    fi
    mark_stack_configured "gcloud"
}

configure_stack_aws() {
    ensure_ca_bundle_exists
    if [[ "$SHELL_BLOCK_WRITTEN" != true ]]; then
        write_shell_profile_block
    fi
    mark_stack_configured "aws"
    log "AWS CLI : AWS_CA_BUNDLE via profil shell."
    report_line "AWS: AWS_CA_BUNDLE via shell profile"
}

configure_stack_simulator() {
    local entry pem_file label booted

    ensure_ca_bundle_exists
    prepare_exported_certs_for_stacks

    if ! command -v xcrun >/dev/null 2>&1; then
        warn "Xcode/xcrun absent — stack simulator ignorée."
        return 0
    fi

    booted="$(xcrun simctl list devices booted 2>/dev/null | grep -E 'Booted' || true)"
    if [[ -z "$booted" ]]; then
        warn "Aucun simulateur iOS démarré — démarrez un simulateur puis relancez --simulator."
        warn "Les certificats root seront ajoutés au prochain run avec simulateur booté."
        mark_stack_configured "simulator"
        return 0
    fi

    for entry in "${EXPORTED_CERTS[@]}"; do
        IFS='|' read -r _ pem_file label <<< "$entry"
        [[ "$label" == *"Root"* || "$label" == *"root"* ]] || continue
        if [[ "$DRY_RUN" == false ]]; then
            xcrun simctl keychain booted add-root-cert "$pem_file" 2>/dev/null ||
                warn "Impossible d'ajouter '$label' au simulateur booté."
        fi
        log "Simulateur iOS : certificat root ajouté — $label"
        report_line "Simulator: added root cert $label"
    done

    mark_stack_configured "simulator"
}

stack_is_selected() {
    local needle="$1"
    local s
    for s in "${SELECTED_STACKS[@]}"; do
        [[ "$s" == "$needle" ]] && return 0
    done
    return 1
}

configure_stack() {
    local stack="$1"
    case "$stack" in
        gradle) configure_stack_gradle ;;
        shell) configure_stack_shell ;;
        dart) configure_stack_dart ;;
        git) configure_stack_git ;;
        node) configure_stack_node ;;
        python) configure_stack_python ;;
        ruby) configure_stack_ruby ;;
        curl) configure_stack_curl ;;
        gcloud) configure_stack_gcloud ;;
        aws) configure_stack_aws ;;
        simulator) configure_stack_simulator ;;
        *) die "Stack inconnue : $stack" ;;
    esac
}

verify_stack() {
    local stack="$1"

    if [[ "$DRY_RUN" == true || "$SKIP_VERIFY" == true ]]; then
        return 0
    fi

    case "$stack" in
        gradle)
            verify_tls_endpoints
            ;;
        dart)
            command -v dart >/dev/null 2>&1 || { warn "dart absent — vérification ignorée."; return 0; }
            DART_VM_OPTIONS="--root-certs-file=$CA_BUNDLE_FILE" \
                dart pub --version >/dev/null 2>&1 ||
                warn "Vérification dart échouée (pub.dev peut être inaccessible)."
            ;;
        git)
            command -v git >/dev/null 2>&1 || return 0
            GIT_SSL_CAINFO="$CA_BUNDLE_FILE" \
                git ls-remote https://github.com/git/git.git HEAD >/dev/null 2>&1 ||
                warn "Vérification git échouée (github.com)."
            ;;
        node)
            command -v npm >/dev/null 2>&1 || return 0
            NODE_EXTRA_CA_CERTS="$CA_BUNDLE_FILE" \
                npm ping --registry https://registry.npmjs.org/ >/dev/null 2>&1 ||
                warn "Vérification npm échouée (registry.npmjs.org)."
            ;;
        curl)
            command -v curl >/dev/null 2>&1 || return 0
            CURL_CA_BUNDLE="$CA_BUNDLE_FILE" \
                curl -fsSI https://pub.dev >/dev/null 2>&1 ||
                warn "Vérification curl échouée (pub.dev)."
            ;;
        gcloud)
            command -v gcloud >/dev/null 2>&1 || return 0
            gcloud config get-value core/custom_ca_certs_file >/dev/null 2>&1 ||
                warn "Vérification gcloud échouée."
            ;;
        *)
            return 0
            ;;
    esac
}

rollback_stack_git() {
    if [[ "$DRY_RUN" == false ]]; then
        git config --global --unset http.sslCAInfo 2>/dev/null || true
    fi
    log "Git : http.sslCAInfo supprimé."
}

rollback_stack_node() {
    if command -v npm >/dev/null 2>&1 && [[ "$DRY_RUN" == false ]]; then
        npm config delete cafile --location=user 2>/dev/null || \
            npm config delete cafile 2>/dev/null || true
    fi
    log "npm : cafile supprimé."
}

rollback_stack_gcloud() {
    if command -v gcloud >/dev/null 2>&1 && [[ "$DRY_RUN" == false ]]; then
        gcloud config unset core/custom_ca_certs_file >/dev/null 2>&1 || true
    fi
    log "gcloud : custom_ca_certs_file supprimé."
}

rollback_configured_stacks() {
    local stack
    for stack in git node gcloud; do
        if load_manifest_value "stack_${stack}" >/dev/null 2>&1; then
            case "$stack" in
                git) rollback_stack_git ;;
                node) rollback_stack_node ;;
                gcloud) rollback_stack_gcloud ;;
            esac
        fi
    done

    local shell_backup
    shell_backup="$(load_manifest_value "shell_profile_backup")"
    if [[ -n "$shell_backup" && -f "$shell_backup" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            restore_shell_profile_from_backup "$shell_backup"
        fi
    else
        if [[ "$DRY_RUN" == false ]]; then
            remove_shell_profile_block_only
        fi
    fi
}

print_install_status() {
    local stack doc_file configured

    echo "État de la configuration — v${SCRIPT_VERSION}"
    echo
    echo "Fichiers :"
    echo "  Truststore : $TRUSTSTORE_FILE"
    echo "  Bundle PEM : $CA_BUNDLE_FILE"
    echo "  Manifest   : $MANIFEST_FILE"
    echo

    if [[ ! -f "$MANIFEST_FILE" ]]; then
        echo "Aucune installation détectée."
        echo "Lancez : ./install.sh --all --netskope"
        return 0
    fi

    echo "Stacks :"
    for stack in "${ALL_STACKS[@]}"; do
        configured="$(load_manifest_value "stack_${stack}" 2>/dev/null || true)"
        if [[ "$configured" == "configured" ]]; then
            echo "  [✓] $stack"
        else
            echo "  [ ] $stack"
        fi
        doc_file="$(stack_doc_file "$stack")"
        [[ -f "$doc_file" ]] && echo "      doc: ./install.sh --docs $stack"
    done
    echo
}

print_install_summary() {
    local stack entry alias label

    echo
    echo "======================================================"
    echo " INSTALLATION TERMINÉE — v${SCRIPT_VERSION}"
    echo "======================================================"
    echo
    echo "Stacks configurées :"
    for stack in "${CONFIGURED_STACKS[@]}"; do
        echo "  - $stack  (./install.sh --docs $stack)"
    done
    echo
    echo "Fichiers :"
    echo "  Truststore PKCS12 : $TRUSTSTORE_FILE"
    echo "  Bundle CA PEM     : $CA_BUNDLE_FILE"
    echo "  Gradle            : $GRADLE_PROPERTIES"
    echo "  Rapport           : $REPORT_FILE"
    echo

    if [[ -n "${EXPORTED_CERTS:-}" ]]; then
        echo "Certificats importés :"
        for entry in "${EXPORTED_CERTS[@]}"; do
            IFS='|' read -r alias _ label <<< "$entry"
            echo "  - $label (alias: $alias)"
        done
        echo
    fi

    if [[ "$SHELL_BLOCK_WRITTEN" == true ]]; then
        detect_shell_profile
        echo "Rechargez votre shell :"
        echo "  source $SHELL_PROFILE_FILE"
        echo
    fi

    echo "Rollback : ./install.sh --rollback"
    echo "État     : ./install.sh --status"
    echo "======================================================"
    echo
}
