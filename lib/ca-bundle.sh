#!/usr/bin/env bash
# shellcheck shell=bash
#
# Bundle PEM des CA d'entreprise (utilisé par Dart, Git, Node, etc.).

CA_BUNDLE_FILE="${CA_BUNDLE_FILE:-$TRUSTSTORE_DIR/nscacert_combined.pem}"

build_ca_bundle_from_exports() {
    local entry alias pem_file label

    [[ -n "${EXPORTED_CERTS:-}" ]] ||
        die "Aucun certificat exporté pour construire le bundle PEM."

    if [[ "$DRY_RUN" == false ]]; then
        : > "$CA_BUNDLE_FILE"
        for entry in "${EXPORTED_CERTS[@]}"; do
            IFS='|' read -r _ pem_file _ <<< "$entry"
            [[ -f "$pem_file" ]] || continue
            cat "$pem_file" >> "$CA_BUNDLE_FILE"
            echo >> "$CA_BUNDLE_FILE"
        done
        chmod 600 "$CA_BUNDLE_FILE"
    fi

    log "Bundle CA PEM : $CA_BUNDLE_FILE"
    write_manifest_entry "ca_bundle_file" "$CA_BUNDLE_FILE"
    report_line "CA bundle: $CA_BUNDLE_FILE"
}

build_ca_bundle_from_keychain_combined() {
    # Méthode recommandée Netskope : racines système + CA déployées dans le Keychain.
    if [[ "$DRY_RUN" == false ]]; then
        security find-certificate -a -p \
            /System/Library/Keychains/SystemRootCertificates.keychain \
            /Library/Keychains/System.keychain \
            > "$CA_BUNDLE_FILE" 2>/dev/null || true

        if [[ ! -s "$CA_BUNDLE_FILE" ]]; then
            build_ca_bundle_from_exports
            return 0
        fi
        chmod 600 "$CA_BUNDLE_FILE"
    fi

    log "Bundle CA PEM (Keychain combiné) : $CA_BUNDLE_FILE"
    write_manifest_entry "ca_bundle_file" "$CA_BUNDLE_FILE"
    report_line "CA bundle (keychain combined): $CA_BUNDLE_FILE"
}

ensure_ca_bundle_exists() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    [[ -f "$CA_BUNDLE_FILE" && -s "$CA_BUNDLE_FILE" ]] ||
        die "Bundle CA absent : $CA_BUNDLE_FILE (lancez d'abord l'export de certificats)."
}
