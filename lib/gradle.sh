#!/usr/bin/env bash
# shellcheck shell=bash
#
# Configuration de ~/.gradle/gradle.properties pour utiliser le truststore PKCS12.

GRADLE_PROPERTIES="${GRADLE_DIR}/gradle.properties"
GRADLE_PROPERTIES_BACKUP=""

merge_jvm_truststore_args() {
    local existing_args="$1"
    local truststore="$2"
    local password="$3"
    local -a tokens=()
    local token

    # Retire d'éventuels paramètres trustStore existants.
    if [[ -n "$existing_args" ]]; then
        read -r -a tokens <<< "$existing_args"
    fi
    local -a cleaned=()

    if [[ -n "$existing_args" ]]; then
        read -r -a tokens <<< "$existing_args"
    fi

    if ((${#tokens[@]} > 0)); then
        for token in "${tokens[@]}"; do
            [[ "$token" == -Djavax.net.ssl.trustStore=* ]] && continue
            [[ "$token" == -Djavax.net.ssl.trustStoreType=* ]] && continue
            [[ "$token" == -Djavax.net.ssl.trustStorePassword=* ]] && continue
            cleaned+=("$token")
        done
    fi

    cleaned+=(
        "-Djavax.net.ssl.trustStore=${truststore}"
        "-Djavax.net.ssl.trustStoreType=PKCS12"
        "-Djavax.net.ssl.trustStorePassword=${password}"
    )

    # Reconstruit une seule ligne (org.gradle.jvmargs).
    local result=""
    for token in "${cleaned[@]}"; do
        result+="${token} "
    done
    echo "${result%" "}"
}

extract_existing_jvmargs() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    awk -F= '
        /^[[:space:]]*org\.gradle\.jvmargs[[:space:]]*=/ {
            sub(/^[[:space:]]*org\.gradle\.jvmargs[[:space:]]*=[[:space:]]*/, "")
            print
            exit
        }
    ' "$file"
}

remove_generated_block() {
    local input_file="$1"
    local output_file="$2"
    awk '
        BEGIN { skip=0 }
        $0 ~ /^# BEGIN gradle-corporate-truststore$/ { skip=1; next }
        $0 ~ /^# END gradle-corporate-truststore$/ { skip=0; next }
        skip==0 { print }
    ' "$input_file" > "$output_file"
}

configure_gradle_properties() {
    local existing_jvmargs merged_jvmargs temp_file

    mkdir -p "$GRADLE_DIR"
    touch "$GRADLE_PROPERTIES"

    if [[ -f "$GRADLE_PROPERTIES" && -s "$GRADLE_PROPERTIES" ]]; then
        GRADLE_PROPERTIES_BACKUP="${GRADLE_PROPERTIES}.backup.$(date +%Y%m%d-%H%M%S)"
        if [[ "$DRY_RUN" == false ]]; then
            cp "$GRADLE_PROPERTIES" "$GRADLE_PROPERTIES_BACKUP"
            write_manifest_entry "gradle_properties_backup" "$GRADLE_PROPERTIES_BACKUP"
            log "Sauvegarde gradle.properties : $GRADLE_PROPERTIES_BACKUP"
        else
            log "Dry-run : sauvegarde gradle.properties simulée"
        fi
    fi

    existing_jvmargs="$(extract_existing_jvmargs "$GRADLE_PROPERTIES")"
    merged_jvmargs="$(merge_jvm_truststore_args "$existing_jvmargs" "$TRUSTSTORE_FILE" "$STORE_PASSWORD")"

    temp_file="$WORKDIR/gradle.properties.new"
    remove_generated_block "$GRADLE_PROPERTIES" "$temp_file"

    {
        cat "$temp_file"
        [[ -s "$temp_file" ]] && echo
        echo "$MARKER_BEGIN"
        echo "org.gradle.jvmargs=${merged_jvmargs}"
        echo "$MARKER_END"
        echo
    } > "$WORKDIR/gradle.properties.final"

    if [[ "$DRY_RUN" == false ]]; then
        cp "$WORKDIR/gradle.properties.final" "$GRADLE_PROPERTIES"
        write_manifest_entry "gradle_properties" "$GRADLE_PROPERTIES"
    fi

    log "Gradle configuré : $GRADLE_PROPERTIES"
    report_line "Gradle properties updated: $GRADLE_PROPERTIES"
    report_line "org.gradle.jvmargs=${merged_jvmargs}"
}

restore_gradle_properties_from_backup() {
    local backup_file="$1"

    [[ -f "$backup_file" ]] || die "Sauvegarde gradle.properties introuvable : $backup_file"

    cp "$backup_file" "$GRADLE_PROPERTIES"
    log "gradle.properties restauré depuis : $backup_file"
}

remove_gradle_generated_block_only() {
    local temp_file="$WORKDIR/gradle.properties.restored"

    [[ -f "$GRADLE_PROPERTIES" ]] || return 0
    remove_generated_block "$GRADLE_PROPERTIES" "$temp_file"
    cp "$temp_file" "$GRADLE_PROPERTIES"
    log "Bloc généré retiré de gradle.properties."
}
