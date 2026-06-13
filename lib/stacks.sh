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
    echo "Documentation macos-netskope-dev v${SCRIPT_VERSION}"
    echo
    echo "Guides :"
    echo "  docs/README.md              — développeur"
    echo "  docs/ADMIN.md               — administrateur IT"
    echo "  docs/CHECKLIST-IT-FLUTTER.md — go-live Flutter (IT)"
    echo "  docs/NETSKOPE-APPLE-IT.md   — Netskope / Apple / Xcode (IT réseau)"
    echo "  docs/DEV-IOS-XCODE.md       — développeur iOS"
    echo "  docs/INTUNE.md              — Microsoft Intune"
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
        mark_stack_configured "gcloud"
    else
        warn "gcloud absent — stack non configurée."
    fi
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
    local entry pem_file label booted added=0

    ensure_ca_bundle_exists
    prepare_exported_certs_for_stacks

    if ! command -v xcrun >/dev/null 2>&1; then
        warn "Xcode/xcrun absent — stack simulator ignorée."
        return 0
    fi

    booted="$(xcrun simctl list devices booted 2>/dev/null | grep -E 'Booted' || true)"
    if [[ -z "$booted" ]]; then
        warn "Aucun simulateur iOS démarré — démarrez un simulateur puis relancez --simulator."
        return 0
    fi

    for entry in "${EXPORTED_CERTS[@]}"; do
        IFS='|' read -r _ pem_file label <<< "$entry"
        [[ "$label" == *"Root"* || "$label" == *"root"* ]] || continue
        if [[ "$DRY_RUN" == false ]]; then
            xcrun simctl keychain booted add-root-cert "$pem_file" 2>/dev/null ||
                warn "Impossible d'ajouter '$label' au simulateur booté."
        fi
        added=$((added + 1))
        log "Simulateur iOS : certificat root ajouté — $label"
        report_line "Simulator: added root cert $label"
    done

    if [[ "$added" -gt 0 || "$DRY_RUN" == true ]]; then
        mark_stack_configured "simulator"
    else
        warn "Aucun certificat root Netskope trouvé pour le simulateur."
    fi
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

stack_needs_shell_reload() {
    case "$1" in
        shell|dart|node|python|ruby|curl|aws) return 0 ;;
        *) return 1
    esac
}

get_configured_stacks_from_manifest() {
    local stack configured
    CONFIGURED_STACKS_FROM_MANIFEST=()
    for stack in "${ALL_STACKS[@]}"; do
        configured="$(load_manifest_value "stack_${stack}" 2>/dev/null || true)"
        [[ "$configured" == "configured" ]] && CONFIGURED_STACKS_FROM_MANIFEST+=("$stack")
    done
}

print_post_install_actions() {
    local -a stacks=("$@")
    local stack step=1
    local need_shell=false need_gradle=false need_simulator=false
    local has_actions=false

    for stack in "${stacks[@]}"; do
        case "$stack" in
            gradle) need_gradle=true ;;
            simulator) need_simulator=true ;;
        esac
        stack_needs_shell_reload "$stack" && need_shell=true
    done

    [[ "$SHELL_BLOCK_WRITTEN" == true ]] && need_shell=true

    ((${#stacks[@]} > 0)) || return 0

    echo "Actions pour prise en compte :"

    if [[ "$need_shell" == true ]]; then
        detect_shell_profile
        echo "  ${step}. Recharger le profil shell (variables Dart, npm, curl, etc.) :"
        echo "       source $SHELL_PROFILE_FILE"
        echo "     Puis ouvrir un nouveau terminal ou redémarrer l'IDE (VS Code, Android Studio)."
        report_line "Post-install: source $SHELL_PROFILE_FILE"
        step=$((step + 1))
        has_actions=true
    fi

    if [[ "$need_gradle" == true ]]; then
        echo "  ${step}. Arrêter le Gradle daemon (truststore JVM) avant le prochain build Android :"
        echo "       cd <votre_projet>/android && ./gradlew --stop"
        echo "     Puis relancer : flutter run  ou  flutter build apk"
        report_line "Post-install: ./gradlew --stop dans android/"
        step=$((step + 1))
        has_actions=true
    fi

    if [[ "$need_simulator" == true ]]; then
        echo "  ${step}. Simulateur iOS : relancer l'app dans le simulateur (certificats root injectés)."
        echo "     Si le simulateur n'était pas démarré : booter un simulateur puis"
        echo "       ./install.sh --simulator --netskope --yes"
        report_line "Post-install: relancer app simulateur ou re-run --simulator"
        step=$((step + 1))
        has_actions=true
    fi

    local has_git=false has_gcloud=false
    for stack in "${stacks[@]}"; do
        [[ "$stack" == "git" ]] && has_git=true
        [[ "$stack" == "gcloud" ]] && has_gcloud=true
    done

    if [[ "$has_git" == true && "$need_shell" == false ]]; then
        echo "  ${step}. Git : pris en compte au prochain git fetch / clone (aucun redémarrage)."
        step=$((step + 1))
        has_actions=true
    fi

    if [[ "$has_gcloud" == true ]]; then
        echo "  ${step}. gcloud : configuration active immédiatement (gcloud config)."
        has_actions=true
    fi

    if [[ "$has_actions" == false ]]; then
        echo "  Aucune relance requise pour les stacks installées."
    fi
    echo
}

print_install_status() {
    local stack doc_file configured manifest_version
    local truststore_state bundle_state manifest_state
    local configured_count=0 healthy=true

    echo "État de la configuration — v${SCRIPT_VERSION}"
    echo

    truststore_state="$(file_exists_label "$TRUSTSTORE_FILE")"
    bundle_state="$(file_exists_label "$CA_BUNDLE_FILE")"
    manifest_state="$(file_exists_label "$MANIFEST_FILE")"

    echo "Fichiers :"
    echo "  Truststore : $TRUSTSTORE_FILE  [$truststore_state]"
    echo "  Bundle PEM : $CA_BUNDLE_FILE  [$bundle_state]"
    echo "  Manifest   : $MANIFEST_FILE  [$manifest_state]"

    if [[ "$manifest_state" == "OK" ]]; then
        manifest_version="$(load_manifest_version 2>/dev/null || true)"
        [[ -n "$manifest_version" ]] && echo "  Version manifest : $manifest_version"
    fi

    if gradle_has_generated_block; then
        echo "  Gradle     : ${GRADLE_DIR}/gradle.properties  [OK — bloc configuré]"
    elif [[ -f "${GRADLE_DIR}/gradle.properties" ]]; then
        echo "  Gradle     : ${GRADLE_DIR}/gradle.properties  [SANS BLOC]"
    else
        echo "  Gradle     : ${GRADLE_DIR}/gradle.properties  [ABSENT]"
    fi

    if shell_has_generated_block; then
        detect_shell_profile
        echo "  Profil shell : $SHELL_PROFILE_FILE  [OK — bloc configuré]"
    else
        detect_shell_profile
        echo "  Profil shell : $SHELL_PROFILE_FILE  [SANS BLOC]"
    fi
    echo

    if [[ "$manifest_state" != "OK" ]]; then
        echo "Aucune installation détectée."
        echo "Lancez : ./install.sh --all --netskope --yes"
        return 0
    fi

    echo "Stacks :"
    for stack in "${ALL_STACKS[@]}"; do
        configured="$(load_manifest_value "stack_${stack}" 2>/dev/null || true)"
        if [[ "$configured" == "configured" ]]; then
            echo "  [✓] $stack"
            configured_count=$((configured_count + 1))
        else
            echo "  [ ] $stack"
        fi
        doc_file="$(stack_doc_file "$stack")"
        [[ -f "$doc_file" ]] && echo "      doc: ./install.sh --docs $stack"
    done
    echo

    if [[ "$configured_count" -eq 0 ]]; then
        echo "⚠ Installation incomplète : manifest présent mais aucune stack configurée."
        healthy=false
    fi

    if [[ "$configured_count" -gt 0 && "$truststore_state" != "OK" && "$bundle_state" != "OK" ]]; then
        echo "⚠ Installation incomplète : stacks enregistrées mais truststore/bundle absents."
        healthy=false
    fi

    if [[ "$truststore_state" == "OK" || "$bundle_state" == "OK" ]] && [[ "$configured_count" -eq 0 ]]; then
        echo "⚠ Résidu détecté : fichiers ou manifest sans stack configurée."
        echo "  Nettoyage : rm -rf $TRUSTSTORE_DIR"
        echo "  Puis       : ./install.sh --all --netskope --yes"
        healthy=false
    fi

    if [[ "$healthy" == true && "$configured_count" -gt 0 ]]; then
        echo "Installation opérationnelle ($configured_count stack(s) configurée(s))."
        echo "Rollback  : ./install.sh --rollback"
        echo
        get_configured_stacks_from_manifest
        print_post_install_actions "${CONFIGURED_STACKS_FROM_MANIFEST[@]}"
    elif [[ "$healthy" == false ]]; then
        echo "Relance recommandée : ./install.sh --all --netskope --yes"
        echo
    else
        echo
    fi
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

    print_post_install_actions "${CONFIGURED_STACKS[@]}"

    echo "Rollback : ./install.sh --rollback"
    echo "État     : ./install.sh --status"
    echo "======================================================"
    echo
}
