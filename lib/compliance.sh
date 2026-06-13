#!/usr/bin/env bash
# shellcheck shell=bash
#
# Évaluation de conformité pour Intune / MDM (Proactive Remediation).

# Codes de sortie --compliance
: "${GCT_COMPLIANCE_OK:=0}"
: "${GCT_COMPLIANCE_NEEDS_REMEDIATION:=1}"
: "${GCT_COMPLIANCE_ERROR:=2}"

COMPLIANCE_STATUS=""
COMPLIANCE_REASONS=()
COMPLIANCE_CONFIGURED_STACKS=()
COMPLIANCE_MISSING_STACKS=()

# Stacks attendues par défaut (--all sans simulateur).
GCT_EXPECTED_STACKS=(
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
)

version_normalize() {
    local version="$1"
    local major=0 minor=0 patch=0

    IFS='.' read -r major minor patch <<< "$version"
    major="${major//[^0-9]/}"
    minor="${minor//[^0-9]/}"
    patch="${patch//[^0-9]/}"
    printf '%03d%03d%03d' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

version_lt() {
    local left right

    left="$(version_normalize "$1")"
    right="$(version_normalize "$2")"
    [[ "$left" < "$right" ]]
}

compliance_add_reason() {
    local reason="$1"
    local existing

    for existing in "${COMPLIANCE_REASONS[@]:-}"; do
        [[ "$existing" == "$reason" ]] && return 0
    done
    COMPLIANCE_REASONS+=("$reason")
}

compliance_collect_stack_state() {
    local stack configured

    COMPLIANCE_CONFIGURED_STACKS=()
    COMPLIANCE_MISSING_STACKS=()

    for stack in "${GCT_EXPECTED_STACKS[@]}"; do
        configured="$(load_manifest_value "stack_${stack}" 2>/dev/null || true)"
        if [[ "$configured" == "configured" ]]; then
            COMPLIANCE_CONFIGURED_STACKS+=("$stack")
        else
            COMPLIANCE_MISSING_STACKS+=("$stack")
        fi
    done
}

compliance_evaluate() {
    local manifest_state truststore_state bundle_state
    local configured_count manifest_version stored_fp current_fp
    local healthy=true exit_code=$GCT_COMPLIANCE_OK

    COMPLIANCE_STATUS="compliant"
    COMPLIANCE_REASONS=()

    manifest_state="$(file_exists_label "$MANIFEST_FILE")"
    truststore_state="$(file_exists_label "$TRUSTSTORE_FILE")"
    bundle_state="$(file_exists_label "$CA_BUNDLE_FILE")"

    if [[ "$manifest_state" != "OK" ]]; then
        compliance_add_reason "no_manifest"
        COMPLIANCE_STATUS="needs_remediation"
        healthy=false
    else
        load_existing_manifest_entries
        compliance_collect_stack_state
        configured_count="${#COMPLIANCE_CONFIGURED_STACKS[@]}"

        if [[ "$configured_count" -eq 0 ]]; then
            compliance_add_reason "no_stacks_configured"
            healthy=false
        fi

        if ((${#COMPLIANCE_MISSING_STACKS[@]} > 0)); then
            compliance_add_reason "missing_stacks"
            healthy=false
        fi

        if [[ "$configured_count" -gt 0 && "$truststore_state" != "OK" && "$bundle_state" != "OK" ]]; then
            compliance_add_reason "truststore_or_bundle_missing"
            healthy=false
        fi

        if [[ "$truststore_state" == "OK" || "$bundle_state" == "OK" ]] && [[ "$configured_count" -eq 0 ]]; then
            compliance_add_reason "orphan_artifacts"
            healthy=false
        fi

        manifest_version="$(load_manifest_version 2>/dev/null || true)"
        if [[ -n "$manifest_version" ]] && version_lt "$manifest_version" "$SCRIPT_VERSION"; then
            compliance_add_reason "script_version_outdated"
            healthy=false
        fi

        if [[ "$bundle_state" == "OK" ]]; then
            stored_fp="$(load_manifest_value ca_fingerprint 2>/dev/null || true)"
            current_fp="$(compute_ca_bundle_fingerprint 2>/dev/null || true)"
            if [[ -n "$stored_fp" && -n "$current_fp" && "$stored_fp" != "$current_fp" ]]; then
                compliance_add_reason "ca_fingerprint_mismatch"
                healthy=false
            elif [[ -z "$stored_fp" ]]; then
                compliance_add_reason "ca_fingerprint_missing"
                healthy=false
            elif ! ca_bundle_is_current; then
                compliance_add_reason "ca_bundle_stale"
                healthy=false
            fi
        fi

        if ! gradle_has_generated_block; then
            compliance_add_reason "gradle_block_missing"
            healthy=false
        fi

        if ! shell_has_generated_block; then
            compliance_add_reason "shell_block_missing"
            healthy=false
        fi
    fi

    if [[ "$healthy" == false ]]; then
        COMPLIANCE_STATUS="needs_remediation"
        exit_code=$GCT_COMPLIANCE_NEEDS_REMEDIATION
    fi

    return "$exit_code"
}

json_array_from_bash() {
    local -a items=("$@")
    local first=true item escaped

    if ((${#items[@]} == 0)); then
        printf '[]'
        return 0
    fi

    printf '['
    for item in "${items[@]}"; do
        escaped="$(json_escape "$item")"
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '"%s"' "$escaped"
    done
    printf ']'
}

write_compliance_report() {
    local report_path="${GCT_COMPLIANCE_REPORT:-$TRUSTSTORE_DIR/compliance-report.json}"
    local manifest_version truststore_state bundle_state stored_fp current_fp
    local json_output

    [[ "$DRY_RUN" == true ]] && return 0

    mkdir -p "$(dirname "$report_path")"
    json_output="$(build_compliance_json)"
    printf '%s\n' "$json_output" > "$report_path"
    chmod 600 "$report_path" 2>/dev/null || true
}

build_compliance_json() {
    local manifest_version truststore_state bundle_state stored_fp current_fp
    local compliant=false

    manifest_version="$(load_manifest_version 2>/dev/null || true)"
    truststore_state="$(file_exists_label "$TRUSTSTORE_FILE")"
    bundle_state="$(file_exists_label "$CA_BUNDLE_FILE")"
    stored_fp="$(load_manifest_value ca_fingerprint 2>/dev/null || true)"
    current_fp="$(compute_ca_bundle_fingerprint 2>/dev/null || true)"

    [[ "$COMPLIANCE_STATUS" == "compliant" ]] && compliant=true

    cat <<EOF
{
  "script_version": "$(json_escape "$SCRIPT_VERSION")",
  "manifest_version": "$(json_escape "${manifest_version:-}")",
  "user": "$(json_escape "$(whoami)")",
  "home": "$(json_escape "$HOME")",
  "hostname": "$(json_escape "$(scutil --get ComputerName 2>/dev/null || hostname)")",
  "compliant": $compliant,
  "status": "$(json_escape "$COMPLIANCE_STATUS")",
  "reasons": $(json_array_from_bash "${COMPLIANCE_REASONS[@]:-}"),
  "configured_stacks": $(json_array_from_bash "${COMPLIANCE_CONFIGURED_STACKS[@]:-}"),
  "missing_stacks": $(json_array_from_bash "${COMPLIANCE_MISSING_STACKS[@]:-}"),
  "expected_stacks": $(json_array_from_bash "${GCT_EXPECTED_STACKS[@]}"),
  "truststore": "$(json_escape "$truststore_state")",
  "bundle": "$(json_escape "$bundle_state")",
  "ca_fingerprint_stored": "$(json_escape "${stored_fp:-}")",
  "ca_fingerprint_current": "$(json_escape "${current_fp:-}")",
  "gradle_block": $(gradle_has_generated_block && echo true || echo false),
  "shell_block": $(shell_has_generated_block && echo true || echo false),
  "checked_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

print_compliance_human() {
    local stack

    echo "Conformité gradle-corporate-truststore — v${SCRIPT_VERSION}"
    echo
    echo "Statut : $COMPLIANCE_STATUS"
    if ((${#COMPLIANCE_REASONS[@]} > 0)); then
        echo "Raisons :"
        for stack in "${COMPLIANCE_REASONS[@]}"; do
            echo "  - $stack"
        done
    fi
    echo
    echo "Stacks configurées (${#COMPLIANCE_CONFIGURED_STACKS[@]}/${#GCT_EXPECTED_STACKS[@]}) :"
    if ((${#COMPLIANCE_CONFIGURED_STACKS[@]} > 0)); then
        for stack in "${COMPLIANCE_CONFIGURED_STACKS[@]}"; do
            echo "  [✓] $stack"
        done
    else
        echo "  (aucune)"
    fi
    if ((${#COMPLIANCE_MISSING_STACKS[@]} > 0)); then
        echo "Stacks manquantes :"
        for stack in "${COMPLIANCE_MISSING_STACKS[@]}"; do
            echo "  [ ] $stack"
        done
    fi
    echo
    if [[ "$COMPLIANCE_STATUS" == "compliant" ]]; then
        echo "Conforme — aucune remédiation requise."
    else
        echo "Non conforme — remédiation recommandée."
        echo "  Intune : scripts/intune-remediate.sh"
        echo "  Manuel   : ./install.sh --all --netskope --yes"
    fi
}

run_compliance_check() {
    local exit_code=0

    ensure_dirs
    compliance_evaluate || exit_code=$?

    if [[ "${COMPLIANCE_JSON:-false}" == true ]]; then
        build_compliance_json
    else
        print_compliance_human
    fi

    write_compliance_report
    return "$exit_code"
}
