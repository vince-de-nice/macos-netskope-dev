#!/usr/bin/env bash
# shellcheck shell=bash
#
# Export de certificats depuis le Keychain macOS.
# Recherche optimisée pour Netskope et CA d'entreprise.

KEYCHAIN_SYSTEM="/Library/Keychains/System.keychain"
KEYCHAIN_LOGIN="${HOME}/Library/Keychains/login.keychain-db"
KEYCHAIN_LOGIN_LEGACY="${HOME}/Library/Keychains/login.keychain"

# Motifs courants Netskope (insensible à la casse via grep).
NETSKOPE_PATTERNS=(
    "netskope"
    "netskope root"
    "netskope intermediate"
    "netskope client root"
    "netskope tenant root"
    "netskope cert"
)

KEYCHAIN_SEARCH_PATHS=(
    "$KEYCHAIN_SYSTEM"
    "$KEYCHAIN_LOGIN"
    "$KEYCHAIN_LOGIN_LEGACY"
)

list_keychain_labels() {
    local keychain="$1"
    [[ -f "$keychain" ]] || return 0

    security dump-keychain "$keychain" 2>/dev/null |
        awk '/"labl"/ {
            gsub(/.*"labl"<blob>=/, "")
            gsub(/"/, "")
            if (length($0) > 0) print
        }'
}

find_certificates_by_name() {
    local search_name="$1"
    local -a results=()
    local keychain label normalized needle line

    needle="$(echo "$search_name" | tr '[:upper:]' '[:lower:]')"

    if [[ -n "${MND_TEST_NETSKOPE_CERTS_FILE:-}" && -f "$MND_TEST_NETSKOPE_CERTS_FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            label="${line%%|*}"
            normalized="$(echo "$label" | tr '[:upper:]' '[:lower:]')"
            [[ "$normalized" == *"$needle"* ]] && results+=("$line")
        done < "$MND_TEST_NETSKOPE_CERTS_FILE"
        if ((${#results[@]} > 0)); then
            printf '%s\n' "${results[@]}"
        fi
        return 0
    fi

    for keychain in "${KEYCHAIN_SEARCH_PATHS[@]}"; do
        [[ -f "$keychain" ]] || continue

        while IFS= read -r label; do
            [[ -z "$label" ]] && continue
            normalized="$(echo "$label" | tr '[:upper:]' '[:lower:]')"
            if [[ "$normalized" == *"$needle"* ]]; then
                results+=("$label|$keychain")
            fi
        done < <(list_keychain_labels "$keychain")
    done

    if ((${#results[@]} == 0)); then
        # Fallback : recherche exacte via security find-certificate
        for keychain in "${KEYCHAIN_SEARCH_PATHS[@]}"; do
            [[ -f "$keychain" ]] || continue
            if security find-certificate -c "$search_name" "$keychain" >/dev/null 2>&1; then
                results+=("$search_name|$keychain")
            fi
        done
    fi

    if ((${#results[@]} == 0)); then
        return 0
    fi

    printf '%s\n' "${results[@]}"
}

find_netskope_certificates() {
    if [[ -n "${MND_TEST_NETSKOPE_CERTS_FILE:-}" && -f "$MND_TEST_NETSKOPE_CERTS_FILE" ]]; then
        cat "$MND_TEST_NETSKOPE_CERTS_FILE"
        return 0
    fi

    local -a results=()
    local keychain label normalized pattern match

    for keychain in "${KEYCHAIN_SEARCH_PATHS[@]}"; do
        [[ -f "$keychain" ]] || continue

        while IFS= read -r label; do
            [[ -z "$label" ]] && continue
            normalized="$(echo "$label" | tr '[:upper:]' '[:lower:]')"
            match=false
            for pattern in "${NETSKOPE_PATTERNS[@]}"; do
                if [[ "$normalized" == *"$pattern"* ]]; then
                    match=true
                    break
                fi
            done
            if [[ "$match" == true ]]; then
                results+=("$label|$keychain")
            fi
        done < <(list_keychain_labels "$keychain")
    done

    if ((${#results[@]} == 0)); then
        return 0
    fi

    printf '%s\n' "${results[@]}" | awk -F'|' '!seen[$1]++'
}

export_certificate_pem() {
    local cert_name="$1"
    local output_file="$2"
    local keychain="${3:-}"
    local fixture=""

    if [[ -n "${MND_TEST_CERT_FIXTURE_DIR:-}" ]]; then
        fixture="$MND_TEST_CERT_FIXTURE_DIR/$(sanitize_alias "$cert_name").pem"
        if [[ -f "$fixture" ]]; then
            cp "$fixture" "$output_file"
            [[ -s "$output_file" ]] && return 0
        fi
    fi

    : > "$output_file"

    if [[ -n "$keychain" && -f "$keychain" ]]; then
        if security find-certificate -c "$cert_name" -p "$keychain" >> "$output_file" 2>/dev/null; then
            [[ -s "$output_file" ]] && return 0
        fi
    fi

    # Trousseau système
    if [[ -f "$KEYCHAIN_SYSTEM" ]]; then
        if security find-certificate -c "$cert_name" -p "$KEYCHAIN_SYSTEM" >> "$output_file" 2>/dev/null; then
            [[ -s "$output_file" ]] && return 0
        fi
    fi

    # Trousseau par défaut (login)
    if security find-certificate -c "$cert_name" -p >> "$output_file" 2>/dev/null; then
        [[ -s "$output_file" ]] && return 0
    fi

    return 1
}

export_certificates_to_dir() {
    # Entrée : tableau global CERT_EXPORT_LIST ("label|keychain|alias")
    local label keychain alias pem_file source final_pem
    local -a exported=()

    mkdir -p "$CERT_EXPORT_DIR"
    USED_CERT_ALIASES=()

    for entry in "${CERT_EXPORT_LIST[@]}"; do
        IFS='|' read -r label keychain alias <<< "$entry"
        pem_file="$CERT_EXPORT_DIR/${alias}.pem"

        if [[ "$keychain" == tls:* ]]; then
            source="$WORKDIR/${alias}.pem"
            if [[ -f "$source" ]]; then
                cp "$source" "$pem_file"
            else
                warn "Certificat TLS introuvable pour alias $alias"
                continue
            fi
            log "Utilisation certificat TLS : $label (alias: $alias)"
        else
            log "Export Keychain : '$label' (alias Java: $alias)"
            if ! export_certificate_pem "$label" "$pem_file" "$keychain"; then
                warn "Impossible d'exporter '$label' depuis le Keychain."
                continue
            fi
        fi

        if ! openssl x509 -in "$pem_file" -noout >/dev/null 2>&1; then
            warn "Fichier PEM invalide pour '$label'."
            rm -f "$pem_file"
            continue
        fi

        final_pem="$pem_file"
        ensure_unique_alias "$alias" "$pem_file"
        alias="$RESOLVED_CERT_ALIAS"
        final_pem="$CERT_EXPORT_DIR/${alias}.pem"
        if [[ "$pem_file" != "$final_pem" ]]; then
            mv "$pem_file" "$final_pem"
            pem_file="$final_pem"
        fi

        exported+=("$alias|$pem_file|$label")
        report_line "Exported: $label -> $pem_file"
    done

    if ((${#exported[@]} == 0)); then
        die "Aucun certificat n'a pu être exporté."
    fi

    EXPORTED_CERTS=("${exported[@]}")
}

build_cert_export_list_from_name() {
    local cert_name="$1"
    local -a matches=()
    local item label keychain alias line

    matches=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && matches+=("$line")
    done < <(find_certificates_by_name "$cert_name")

    if ((${#matches[@]} == 0)); then
        die "Certificat introuvable dans le Keychain : '$cert_name'"
    fi

    if ((${#matches[@]} > 1)); then
        warn "Plusieurs certificats correspondent à '$cert_name' :"
        for item in "${matches[@]}"; do
            warn "  - ${item%%|*}"
        done
        warn "Tous les certificats correspondants seront importés."
    fi

    CERT_EXPORT_LIST=()
    for item in "${matches[@]}"; do
        label="${item%%|*}"
        keychain="${item#*|}"
        alias="$(sanitize_alias "$label")"
        CERT_EXPORT_LIST+=("$label|$keychain|$alias")
    done
}

build_cert_export_list_by_fingerprint() {
    local needle="${1//:/}"
    needle="$(echo "$needle" | tr '[:upper:]' '[:lower:]')"
    local -a matches=()
    local item label keychain alias line fp

    while IFS= read -r line; do
        [[ -n "$line" ]] && matches+=("$line")
    done < <(find_netskope_certificates)

    if ((${#matches[@]} == 0)); then
        die "Aucun certificat Netskope trouvé pour --cert-fingerprint."
    fi

    CERT_EXPORT_LIST=()
    for item in "${matches[@]}"; do
        label="${item%%|*}"
        keychain="${item#*|}"
        if ! export_certificate_pem "$label" "$WORKDIR/fp-check.pem" "$keychain"; then
            continue
        fi
        fp="$(openssl x509 -in "$WORKDIR/fp-check.pem" -noout -fingerprint -sha256 2>/dev/null |
            sed 's/sha256 Fingerprint=//I' | tr -d ': ' | tr '[:upper:]' '[:lower:]')"
        rm -f "$WORKDIR/fp-check.pem"
        [[ "$fp" == *"$needle"* ]] || continue
        alias="$(sanitize_alias "$label")"
        log "Certificat sélectionné par empreinte : $label ($fp)"
        CERT_EXPORT_LIST+=("$label|$keychain|$alias")
    done

    ((${#CERT_EXPORT_LIST[@]} > 0)) ||
        die "Aucun certificat ne correspond à l'empreinte : $1"
}

build_cert_export_list_netskope_auto() {
    local -a matches=()
    local item label keychain alias line

    matches=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && matches+=("$line")
    done < <(find_netskope_certificates)

    if ((${#matches[@]} == 0)); then
        die "Aucun certificat Netskope trouvé dans le Keychain. Utilisez --cert \"Nom\" ou --netskope."
    fi

    log "Certificats Netskope détectés :"
    CERT_EXPORT_LIST=()
    for item in "${matches[@]}"; do
        label="${item%%|*}"
        keychain="${item#*|}"
        alias="$(sanitize_alias "$label")"
        log "  - $label"
        CERT_EXPORT_LIST+=("$label|$keychain|$alias")
    done
}
