#!/usr/bin/env bash
# shellcheck shell=bash
#
# Bloc de variables d'environnement dans le profil shell (~/.zshrc).

SHELL_PROFILE_FILE=""
SHELL_PROFILE_BACKUP=""
SHELL_BLOCK_WRITTEN=false

detect_shell_profile() {
    if [[ -n "${SHELL_PROFILE_OVERRIDE:-}" ]]; then
        SHELL_PROFILE_FILE="$SHELL_PROFILE_OVERRIDE"
        return 0
    fi

    if [[ -f "$HOME/.zshrc" ]]; then
        SHELL_PROFILE_FILE="$HOME/.zshrc"
        return 0
    fi

    if [[ -f "$HOME/.zprofile" ]]; then
        SHELL_PROFILE_FILE="$HOME/.zprofile"
        return 0
    fi

    if [[ -f "$HOME/.bash_profile" ]]; then
        SHELL_PROFILE_FILE="$HOME/.bash_profile"
        return 0
    fi

    SHELL_PROFILE_FILE="$HOME/.zshrc"
}

remove_profile_block_from_file() {
    local input_file="$1"
    local output_file="$2"
    awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
        BEGIN { skip=0 }
        $0 == begin { skip=1; next }
        $0 == end { skip=0; next }
        skip==0 { print }
    ' "$input_file" > "$output_file"
}

extract_dart_vm_options_from_profile() {
    local file="$1"
    local line value

    [[ -f "$file" ]] || return 0

    line="$(grep -E '^[[:space:]]*export[[:space:]]+DART_VM_OPTIONS=' "$file" 2>/dev/null | tail -1 || true)"
    [[ -n "$line" ]] || return 0

    value="${line#export DART_VM_OPTIONS=}"
    value="${value#\"}"
    value="${value%\"}"
    echo "$value"
}

merge_dart_vm_options() {
    local existing="$1"
    local -a tokens=()
    local -a cleaned=()
    local token result=""

    if [[ -n "$existing" ]]; then
        read -r -a tokens <<< "$existing"
        for token in "${tokens[@]}"; do
            [[ "$token" == --root-certs-file=* ]] && continue
            cleaned+=("$token")
        done
    fi

    cleaned+=("--root-certs-file=\${NETSKOPE_CA_BUNDLE}")

    for token in "${cleaned[@]}"; do
        result+="${token} "
    done
    echo "${result%" "}"
}

write_shell_profile_block() {
    local temp_file bundle existing_dart merged_dart

    detect_shell_profile
    bundle="$CA_BUNDLE_FILE"
    mkdir -p "$(dirname "$SHELL_PROFILE_FILE")"
    touch "$SHELL_PROFILE_FILE"

    if [[ -f "$SHELL_PROFILE_FILE" && -s "$SHELL_PROFILE_FILE" ]]; then
        if ! manifest_entry_exists "shell_profile_backup"; then
            SHELL_PROFILE_BACKUP="${SHELL_PROFILE_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
            if [[ "$DRY_RUN" == false ]]; then
                cp "$SHELL_PROFILE_FILE" "$SHELL_PROFILE_BACKUP"
                write_manifest_entry "shell_profile_backup" "$SHELL_PROFILE_BACKUP"
            fi
        fi
    fi

    existing_dart="$(extract_dart_vm_options_from_profile "$SHELL_PROFILE_FILE")"
    [[ -z "$existing_dart" && -n "${DART_VM_OPTIONS:-}" ]] && existing_dart="$DART_VM_OPTIONS"
    merged_dart="$(merge_dart_vm_options "$existing_dart")"

    temp_file="$WORKDIR/shell-profile.new"
    remove_profile_block_from_file "$SHELL_PROFILE_FILE" "$temp_file"

    {
        cat "$temp_file"
        [[ -s "$temp_file" ]] && echo
        echo "$MARKER_BEGIN"
        cat <<EOF
# Bundle CA d'entreprise (Netskope) — gradle-corporate-truststore v${SCRIPT_VERSION}
export NETSKOPE_CA_BUNDLE="${bundle}"
export DART_VM_OPTIONS="${merged_dart}"
export NODE_EXTRA_CA_CERTS="\${NETSKOPE_CA_BUNDLE}"
export SSL_CERT_FILE="\${NETSKOPE_CA_BUNDLE}"
export REQUESTS_CA_BUNDLE="\${NETSKOPE_CA_BUNDLE}"
export CURL_CA_BUNDLE="\${NETSKOPE_CA_BUNDLE}"
export AWS_CA_BUNDLE="\${NETSKOPE_CA_BUNDLE}"
export GIT_SSL_CAINFO="\${NETSKOPE_CA_BUNDLE}"
EOF
        echo "$MARKER_END"
        echo
    } > "$WORKDIR/shell-profile.final"

    if [[ "$DRY_RUN" == false ]]; then
        cp "$WORKDIR/shell-profile.final" "$SHELL_PROFILE_FILE"
        write_manifest_entry "shell_profile" "$SHELL_PROFILE_FILE"
    fi
    SHELL_BLOCK_WRITTEN=true

    log "Profil shell configuré : $SHELL_PROFILE_FILE"
    report_line "Shell profile: $SHELL_PROFILE_FILE"
}

restore_shell_profile_from_backup() {
    local backup_file="$1"
    [[ -f "$backup_file" ]] || die "Sauvegarde profil shell introuvable : $backup_file"
    detect_shell_profile
    cp "$backup_file" "$SHELL_PROFILE_FILE"
    log "Profil shell restauré : $SHELL_PROFILE_FILE"
}

remove_shell_profile_block_only() {
    local temp_file
    detect_shell_profile
    [[ -f "$SHELL_PROFILE_FILE" ]] || return 0
    temp_file="$WORKDIR/shell-profile.restored"
    remove_profile_block_from_file "$SHELL_PROFILE_FILE" "$temp_file"
    if [[ "$DRY_RUN" == false ]]; then
        cp "$temp_file" "$SHELL_PROFILE_FILE"
    fi
    log "Bloc shell retiré de : $SHELL_PROFILE_FILE"
}
