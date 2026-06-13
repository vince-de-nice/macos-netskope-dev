#!/usr/bin/env bash
# shellcheck shell=bash
#
# Lecture / fusion du manifest d'installation (installations incrémentales).

load_existing_manifest_entries() {
    local line key value in_entries=false

    [[ -f "$MANIFEST_FILE" ]] || return 0

    MANIFEST_ENTRIES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *'"entries"'* && "$line" == *'{'* ]]; then
            in_entries=true
            continue
        fi
        [[ "$in_entries" == true ]] || continue
        [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$ ]] && break

        if [[ "$line" =~ ^[[:space:]]*\"([^\"]+)\"[[:space:]]*:[[:space:]]*\"(.*)\"[[:space:]]*,?[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value//\\\"/\"}"
            value="${value//\\\\/\\}"
            MANIFEST_ENTRIES+=("$(json_escape "$key")|$(json_escape "$value")")
        fi
    done < "$MANIFEST_FILE"
}

manifest_entry_exists() {
    local needle="$1"
    local entry key escaped

    escaped="$(json_escape "$needle")"
    for entry in "${MANIFEST_ENTRIES[@]:-}"; do
        key="${entry%%|*}"
        [[ "$key" == "$escaped" ]] && return 0
    done
    return 1
}

write_manifest_entry() {
    local key="$1"
    local value="$2"
    local escaped_key escaped_value entry i

    escaped_key="$(json_escape "$key")"
    escaped_value="$(json_escape "$value")"

    for i in "${!MANIFEST_ENTRIES[@]}"; do
        entry="${MANIFEST_ENTRIES[$i]}"
        if [[ "${entry%%|*}" == "$escaped_key" ]]; then
            MANIFEST_ENTRIES[$i]="${escaped_key}|${escaped_value}"
            return 0
        fi
    done

    MANIFEST_ENTRIES+=("${escaped_key}|${escaped_value}")
}

save_manifest() {
    local entry key value created_at

    ensure_dirs
    created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    {
        echo "{"
        echo "  \"version\": \"$SCRIPT_VERSION\","
        echo "  \"updated_at\": \"$created_at\","
        echo "  \"truststore_file\": \"$(json_escape "$TRUSTSTORE_FILE")\","
        echo "  \"entries\": {"
        local first=true
        for entry in "${MANIFEST_ENTRIES[@]:-}"; do
            key="${entry%%|*}"
            value="${entry#*|}"
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": "%s"' "$key" "$value"
        done
        echo
        echo "  }"
        echo "}"
    } > "$MANIFEST_FILE"
    chmod 600 "$MANIFEST_FILE"
}

load_manifest_value() {
    local key="$1" key_escaped

    [[ -f "$MANIFEST_FILE" ]] || return 1
    key_escaped="$(printf '%s' "$key" | sed 's/[][\\.*^$()+?{}|]/\\&/g')"
    sed -n "s/^[[:space:]]*\"${key_escaped}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$MANIFEST_FILE" | head -1
}
