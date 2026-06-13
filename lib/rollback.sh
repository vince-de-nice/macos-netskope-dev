#!/usr/bin/env bash
# shellcheck shell=bash
#
# Rollback transactionnel de la configuration Gradle / truststore.

perform_rollback() {
    local manifest="$MANIFEST_FILE"
    local truststore_backup gradle_backup

    [[ -f "$manifest" ]] ||
        die "Aucune installation précédente trouvée (manifest absent) : $manifest"

    log "Rollback à partir de : $manifest"
    report_line ""
    report_line "=== Rollback ==="

    truststore_backup="$(load_manifest_value "truststore_backup")"
    gradle_backup="$(load_manifest_value "gradle_properties_backup")"

    if [[ -n "$gradle_backup" && -f "$gradle_backup" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            restore_gradle_properties_from_backup "$gradle_backup"
        fi
        log "gradle.properties : restauré"
    else
        if [[ "$DRY_RUN" == false ]]; then
            remove_gradle_generated_block_only
        fi
        log "gradle.properties : bloc généré supprimé"
    fi

    if [[ -n "$truststore_backup" && -f "$truststore_backup" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            cp "$truststore_backup" "$TRUSTSTORE_FILE"
            chmod 600 "$TRUSTSTORE_FILE"
        fi
        log "Truststore restauré depuis : $truststore_backup"
    else
        if [[ -f "$TRUSTSTORE_FILE" ]]; then
            if [[ "$DRY_RUN" == false ]]; then
                rm -f "$TRUSTSTORE_FILE"
            fi
            log "Truststore supprimé : $TRUSTSTORE_FILE"
        fi
    fi

    rollback_configured_stacks

    if [[ -f "$CA_BUNDLE_FILE" && "$DRY_RUN" == false ]]; then
        rm -f "$CA_BUNDLE_FILE"
        log "Bundle CA supprimé : $CA_BUNDLE_FILE"
    fi

    if [[ "$DRY_RUN" == false ]]; then
        mv "$manifest" "${manifest}.rolled-back.$(date +%Y%m%d-%H%M%S)"
    fi

    log "Rollback terminé."
}

rollback_on_failure() {
    local exit_code=$?
    if [[ "$exit_code" -ne 0 && "${INSTALL_TRANSACTION_ACTIVE:-false}" == true && "$DRY_RUN" == false ]]; then
        warn "Échec détecté (code $exit_code). Tentative de rollback automatique..."
        perform_rollback || warn "Rollback automatique incomplet."
    fi
}

begin_install_transaction() {
    INSTALL_TRANSACTION_ACTIVE=true
    trap 'rollback_on_failure' ERR
}

end_install_transaction() {
    INSTALL_TRANSACTION_ACTIVE=false
    trap - ERR
}
