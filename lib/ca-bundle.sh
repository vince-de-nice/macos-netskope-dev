#!/usr/bin/env bash
# shellcheck shell=bash
#
# Bundle PEM des CA d'entreprise (utilisé par Dart, Git, Node, etc.).

CA_BUNDLE_FILE="${CA_BUNDLE_FILE:-$TRUSTSTORE_DIR/nscacert_combined.pem}"
CERTS_CACHE_DIR="${CERTS_CACHE_DIR:-$TRUSTSTORE_DIR/certs}"

compute_ca_bundle_fingerprint() {
    local bundle="${1:-$CA_BUNDLE_FILE}"

    [[ -f "$bundle" && -s "$bundle" ]] || return 1
    shasum -a 256 "$bundle" | awk '{print $1}'
}

cache_exported_certificates() {
    local entry alias pem_file label dest

    [[ -n "${EXPORTED_CERTS:-}" ]] || return 0
    [[ "$DRY_RUN" == true ]] && return 0

    mkdir -p "$CERTS_CACHE_DIR"
    rm -f "$CERTS_CACHE_DIR"/*.pem

    for entry in "${EXPORTED_CERTS[@]}"; do
        IFS='|' read -r alias pem_file label <<< "$entry"
        [[ -f "$pem_file" ]] || continue
        dest="$CERTS_CACHE_DIR/${alias}.pem"
        cp "$pem_file" "$dest"
    done
}

load_exported_certs_from_cache() {
    local pem alias label

    EXPORTED_CERTS=()
    [[ -d "$CERTS_CACHE_DIR" ]] || return 1

    shopt -s nullglob
    local pems=("$CERTS_CACHE_DIR"/*.pem)
    shopt -u nullglob

    ((${#pems[@]} > 0)) || return 1

    for pem in "${pems[@]}"; do
        alias="$(basename "$pem" .pem)"
        label="$(certificate_subject_cn "$pem" 2>/dev/null || echo "$alias")"
        [[ -z "$label" ]] && label="$alias"
        EXPORTED_CERTS+=("$alias|$pem|$label")
    done

    ((${#EXPORTED_CERTS[@]} > 0))
}

hydrate_exported_certs_from_bundle() {
    local split_dir pem cn alias index=0

    [[ -f "$CA_BUNDLE_FILE" && -s "$CA_BUNDLE_FILE" ]] || return 1

    split_dir="$WORKDIR/bundle-split"
    split_pem_bundle "$CA_BUNDLE_FILE" "$split_dir"

    EXPORTED_CERTS=()
    for pem in "$split_dir"/cert-*.pem; do
        [[ -f "$pem" ]] || continue
        index=$((index + 1))
        cn="$(certificate_subject_cn "$pem")"
        [[ -n "$cn" ]] || cn="bundle-cert-${index}"
        alias="$(sanitize_alias "$cn")"
        EXPORTED_CERTS+=("$alias|$pem|$cn")
    done

    ((${#EXPORTED_CERTS[@]} > 0))
}

ca_bundle_is_current() {
    local stored_fp current_fp

    [[ -f "$CA_BUNDLE_FILE" && -s "$CA_BUNDLE_FILE" ]] || return 1
    stored_fp="$(load_manifest_value ca_fingerprint 2>/dev/null || true)"
    [[ -n "$stored_fp" ]] || return 1
    current_fp="$(compute_ca_bundle_fingerprint)" || return 1
    [[ "$stored_fp" == "$current_fp" ]]
}

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
        cache_exported_certificates
        write_manifest_entry "ca_fingerprint" "$(compute_ca_bundle_fingerprint)"
    fi

    log "Bundle CA PEM : $CA_BUNDLE_FILE"
    write_manifest_entry "ca_bundle_file" "$CA_BUNDLE_FILE"
    report_line "CA bundle: $CA_BUNDLE_FILE"
}

ensure_ca_bundle_exists() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    [[ -f "$CA_BUNDLE_FILE" && -s "$CA_BUNDLE_FILE" ]] ||
        die "Bundle CA absent : $CA_BUNDLE_FILE (lancez d'abord l'export de certificats)."
}

prepare_exported_certs_for_stacks() {
    if [[ -n "${EXPORTED_CERTS:-}" ]]; then
        return 0
    fi

    load_exported_certs_from_cache ||
        hydrate_exported_certs_from_bundle ||
        die "Impossible de charger les certificats exportés."
}
