#!/usr/bin/env bash
# shellcheck shell=bash
#
# Analyse de certificats, chaîne TLS, création du truststore PKCS12.

CERT_EXPORT_DIR=""
EXPORTED_CERTS=()
CERT_EXPORT_LIST=()

TLS_PROBE_HOSTS=(
    "repo.maven.apache.org:443"
    "dl.google.com:443"
    "plugins.gradle.org:443"
)

describe_certificate() {
    local pem_file="$1"
    openssl x509 -in "$pem_file" -noout -subject -issuer -dates -fingerprint -sha256 2>/dev/null ||
        warn "Analyse impossible pour $pem_file"
}

certificate_fingerprint_sha256() {
    local pem_file="$1"
    openssl x509 -in "$pem_file" -noout -fingerprint -sha256 2>/dev/null |
        sed 's/sha256 Fingerprint=//I' |
        tr -d ':'
}

certificate_subject_cn() {
    local pem_file="$1"
    openssl x509 -in "$pem_file" -noout -subject 2>/dev/null |
        sed -n 's/.*CN=\([^,/]*\).*/\1/p' |
        head -1
}

extract_tls_chain_pem() {
    local host_port="$1"
    local output_file="$2"
    local host="${host_port%%:*}"
    local port="${host_port##*:}"

    : > "$output_file"

    # Récupère la chaîne TLS présentée (via proxy MITM si actif).
    if ! echo | openssl s_client \
        -connect "$host:$port" \
        -servername "$host" \
        -showcerts 2>/dev/null > "$WORKDIR/tls-${host}.txt"
    then
        warn "Connexion TLS impossible vers $host:$port"
        return 1
    fi

    awk '
        /BEGIN CERTIFICATE/ { capture=1 }
        capture { print }
        /END CERTIFICATE/ { capture=0; print "" }
    ' "$WORKDIR/tls-${host}.txt" > "$output_file"

    [[ -s "$output_file" ]]
}

split_pem_bundle() {
    local bundle_file="$1"
    local output_dir="$2"
    local file_index=0
    local current_file=""

    mkdir -p "$output_dir"
    rm -f "$output_dir"/*.pem

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
            current_file="$output_dir/cert-$(printf '%03d' "$file_index").pem"
            : > "$current_file"
            file_index=$((file_index + 1))
        fi
        if [[ -n "$current_file" ]]; then
            echo "$line" >> "$current_file"
        fi
    done < "$bundle_file"
}

discover_chain_from_tls_and_keychain() {
    local host_port="$1"
    local chain_file="$WORKDIR/tls-chain.pem"
    local split_dir="$WORKDIR/tls-split"
    local pem cn alias fp index=0

    log "Découverte TLS via $host_port (chaîne présentée par le proxy)..."

    extract_tls_chain_pem "$host_port" "$chain_file" ||
        die "Impossible d'obtenir la chaîne TLS depuis $host_port."

    split_pem_bundle "$chain_file" "$split_dir"

    CERT_EXPORT_LIST=()

    # 1) Certificats Netskope présents dans le Keychain (Root / Intermediate).
    local label keychain line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        label="${line%%|*}"
        keychain="${line#*|}"
        alias="$(sanitize_alias "$label")"
        CERT_EXPORT_LIST+=("$label|$keychain|$alias")
        log "  Keychain Netskope : $label"
    done < <(find_netskope_certificates)

    # 2) Certificats intermédiaires/racine présentés dans la chaîne TLS (hors feuille).
    for pem in "$split_dir"/cert-*.pem; do
        [[ -f "$pem" ]] || continue
        index=$((index + 1))
        [[ "$index" -eq 1 ]] && continue

        cn="$(certificate_subject_cn "$pem")"
        [[ -n "$cn" ]] || cn="tls-chain-cert-${index}"
        alias="$(sanitize_alias "$cn")"
        fp="$(certificate_fingerprint_sha256 "$pem")"

        # Source spéciale : certificat issu directement de la chaîne TLS (pas du Keychain).
        CERT_EXPORT_LIST+=("TLS:$cn|tls:$fp|$alias")
        cp "$pem" "$WORKDIR/${alias}.pem"
        log "  Chaîne TLS : $cn"
    done

    ((${#CERT_EXPORT_LIST[@]} > 0)) ||
        die "Découverte TLS échouée : aucun certificat Netskope ou chaîne TLS exploitable."
}

find_base_java_cacerts() {
    local java_home cacerts
    local -a java_homes=()

    if [[ -n "${FLUTTER_JAVA_HOME:-}" && -d "$FLUTTER_JAVA_HOME" ]]; then
        java_homes+=("$FLUTTER_JAVA_HOME")
    fi
    if [[ -n "${ANDROID_STUDIO_JBR:-}" && -d "$ANDROID_STUDIO_JBR" ]]; then
        java_homes+=("$ANDROID_STUDIO_JBR")
    fi
    if [[ -n "${JAVA_HOME:-}" && -d "$JAVA_HOME" ]]; then
        java_homes+=("$JAVA_HOME")
    fi

    if [[ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]]; then
        java_homes+=("/Applications/Android Studio.app/Contents/jbr/Contents/Home")
    fi

    if command -v /usr/libexec/java_home >/dev/null 2>&1; then
        while IFS= read -r java_home; do
            [[ -n "$java_home" && -d "$java_home" ]] && java_homes+=("$java_home")
        done < <(/usr/libexec/java_home -V 2>&1 | sed -n 's/^[[:space:]]*[0-9].*:[[:space:]]*//p' | tr -d ')')
    fi

    local -a cacerts_candidates=()
    if ((${#java_homes[@]} > 0)); then
        for java_home in "${java_homes[@]}"; do
            cacerts_candidates+=(
                "$java_home/lib/security/cacerts"
                "$java_home/jre/lib/security/cacerts"
                "$java_home/Contents/Home/lib/security/cacerts"
            )
        done
    fi

    if ((${#cacerts_candidates[@]} == 0)); then
        return 1
    fi

    for cacerts in "${cacerts_candidates[@]}"; do
        if [[ -f "$cacerts" ]]; then
            echo "$cacerts"
            return 0
        fi
    done

    return 1
}

detect_cacerts_store_type() {
    local cacerts_file="$1"

    if keytool -list -keystore "$cacerts_file" -storepass changeit -storetype PKCS12 >/dev/null 2>&1; then
        echo "PKCS12"
        return 0
    fi
    if keytool -list -keystore "$cacerts_file" -storepass changeit -storetype JKS >/dev/null 2>&1; then
        echo "JKS"
        return 0
    fi

    echo "JKS"
}

initialize_truststore_from_cacerts() {
    local base_cacerts="$1"
    local src_type

    src_type="$(detect_cacerts_store_type "$base_cacerts")"
    log "Conversion $src_type -> PKCS12"

    keytool -importkeystore -noprompt \
        -srckeystore "$base_cacerts" \
        -srcstoretype "$src_type" \
        -srcstorepass "$DEFAULT_STORE_PASSWORD" \
        -destkeystore "$TRUSTSTORE_FILE" \
        -deststoretype PKCS12 \
        -deststorepass "$STORE_PASSWORD"
}

create_or_refresh_truststore() {
    local base_cacerts backup_file

    ensure_dirs

    if [[ ! -f "$TRUSTSTORE_FILE" ]]; then
        base_cacerts="$(find_base_java_cacerts)" ||
            die "Impossible de trouver un cacerts Java de base pour initialiser le truststore."

        log "Initialisation du truststore PKCS12 depuis : $base_cacerts"
        if [[ "$DRY_RUN" == false ]]; then
            initialize_truststore_from_cacerts "$base_cacerts"
            chmod 600 "$TRUSTSTORE_FILE"
        fi
        write_manifest_entry "truststore_created_from" "$base_cacerts"
        report_line "Truststore initialized from: $base_cacerts"
    else
        log "Truststore existant : $TRUSTSTORE_FILE"
        if [[ "$DRY_RUN" == false ]] && ! manifest_entry_exists "truststore_backup"; then
            backup_file="${TRUSTSTORE_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
            cp "$TRUSTSTORE_FILE" "$backup_file"
            write_manifest_entry "truststore_backup" "$backup_file"
            report_line "Truststore backup: $backup_file"
        fi
    fi
}

truststore_has_alias() {
    local alias="$1"
    keytool -list \
        -keystore "$TRUSTSTORE_FILE" \
        -storetype PKCS12 \
        -storepass "$STORE_PASSWORD" \
        -alias "$alias" >/dev/null 2>&1
}

import_certificate_into_truststore() {
    local alias="$1"
    local pem_file="$2"
    local label="$3"

    log "Import dans truststore : $label (alias: $alias)"

    if truststore_has_alias "$alias"; then
        warn "Alias déjà présent : $alias"
        if [[ "$NON_INTERACTIVE" == false ]]; then
            confirm_or_die "Remplacer l'alias '$alias' ?"
        fi
        if [[ "$DRY_RUN" == false ]]; then
            keytool -delete \
                -keystore "$TRUSTSTORE_FILE" \
                -storetype PKCS12 \
                -storepass "$STORE_PASSWORD" \
                -alias "$alias"
        fi
    fi

    if [[ "$DRY_RUN" == false ]]; then
        keytool -importcert \
            -noprompt \
            -trustcacerts \
            -alias "$alias" \
            -file "$pem_file" \
            -keystore "$TRUSTSTORE_FILE" \
            -storetype PKCS12 \
            -storepass "$STORE_PASSWORD"
    fi

    describe_certificate "$pem_file" >> "$REPORT_FILE"
    report_line ""
}

import_all_exported_certificates() {
    local entry alias pem_file label

    create_or_refresh_truststore

    for entry in "${EXPORTED_CERTS[@]}"; do
        IFS='|' read -r alias pem_file label <<< "$entry"
        import_certificate_into_truststore "$alias" "$pem_file" "$label"
    done

    log "Vérification des alias importés..."
    for entry in "${EXPORTED_CERTS[@]}"; do
        IFS='|' read -r alias _ _ <<< "$entry"
        if [[ "$DRY_RUN" == false ]]; then
            truststore_has_alias "$alias" ||
                die "Alias absent après import : $alias"
        fi
    done
}
