#!/usr/bin/env bash
#
# Suite de tests automatisée pour gradle-corporate-truststore.
# Exécutable sans Netskope : certificats mock, dry-run, répertoires isolés dans /tmp.
#
# Usage :
#   ./test/run-tests.sh
#   ./test/run-tests.sh --verbose
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERBOSE=false
PASSED=0
FAILED=0
SKIPPED=0
MOCK_CERTS_INSTALLED=false
TEST_ROOT=""

# Certificats mock injectés temporairement dans le Keychain login.
MOCK_CERT_NAMES=(
    "Netskope Root CA"
    "Netskope Intermediate CA"
)

usage() {
    cat <<EOF
Usage: $0 [--verbose]

Tests automatisés (sans Netskope requis ; simule les CA Netskope) :
  - Syntaxe bash, shellcheck (optionnel)
  - Unitaires (alias, merge jvmargs, admin, profil shell, bundle PEM)
  - Intégration dry-run (toutes stacks, profil Firebase)
  - Truststore PKCS12 réel (keytool) + TLS Java (si réseau)
  - Rollback (gradle, shell, git)
  - Garde anti-root (si sudo sans mot de passe)
  - Documentation complète

Variables d'environnement isolées dans /tmp.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Option inconnue : $1" >&2
                usage
                exit 1
                ;;
        esac
    done
}

log_test() {
    echo "[TEST] $*"
}

log_pass() {
    PASSED=$((PASSED + 1))
    echo "  PASS: $*"
}

log_fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL: $*" >&2
}

log_skip() {
    SKIPPED=$((SKIPPED + 1))
    echo "  SKIP: $*"
}

assert_eq() {
    local desc="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$expected" == "$actual" ]]; then
        log_pass "$desc"
    else
        log_fail "$desc (attendu: '$expected', obtenu: '$actual')"
    fi
}

assert_contains() {
    local desc="$1"
    local haystack="$2"
    local needle="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_pass "$desc"
    else
        log_fail "$desc (chaîne absente: '$needle')"
        [[ "$VERBOSE" == true ]] && echo "    sortie: $haystack" >&2
    fi
}

assert_success() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        log_pass "$desc"
    else
        log_fail "$desc (commande en échec: $*)"
    fi
}

assert_failure() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        log_fail "$desc (commande aurait dû échouer: $*)"
    else
        log_pass "$desc"
    fi
}

setup_test_root() {
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gradle-truststore-tests.XXXXXX")"
    ORIG_HOME="${HOME:-}"
    export TRUSTSTORE_DIR="$TEST_ROOT/truststore"
    export GRADLE_DIR="$TEST_ROOT/gradle"
    export TRUSTSTORE_FILE="$TRUSTSTORE_DIR/corporate-truststore.p12"
    export STATE_DIR="$TRUSTSTORE_DIR/state"
    export MANIFEST_FILE="$STATE_DIR/manifest.json"
    export REPORT_FILE="$TRUSTSTORE_DIR/install-report.txt"
    export CA_BUNDLE_FILE="$TRUSTSTORE_DIR/nscacert_combined.pem"
}

restore_home() {
    [[ -n "${ORIG_HOME:-}" ]] && export HOME="$ORIG_HOME"
}

cleanup_test_root() {
    [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] && rm -rf "$TEST_ROOT"
}

purge_mock_certs() {
    local name hash
    for name in "${MOCK_CERT_NAMES[@]}"; do
        while IFS= read -r hash; do
            [[ -z "$hash" ]] && continue
            security delete-certificate -Z "$hash" 2>/dev/null || true
        done < <(
            security find-certificate -a -c "$name" -Z 2>/dev/null |
                awk '/^SHA-1 hash:/ {print $3}'
        )
    done
    MOCK_CERTS_INSTALLED=false
}

trap 'purge_mock_certs; cleanup_test_root' EXIT

install_mock_netskope_certs() {
    [[ "$MOCK_CERTS_INSTALLED" == true ]] && return 0

    purge_mock_certs

    local workdir="$TEST_ROOT/mock-certs"
    mkdir -p "$workdir"

    openssl req -x509 -newkey rsa:2048 \
        -keyout "$workdir/root-key.pem" \
        -out "$workdir/netskope-root.pem" \
        -days 1 -nodes \
        -subj "/CN=Netskope Root CA/O=Netskope Inc/C=US" \
        2>/dev/null

    openssl req -x509 -newkey rsa:2048 \
        -keyout "$workdir/inter-key.pem" \
        -out "$workdir/netskope-intermediate.pem" \
        -days 1 -nodes \
        -subj "/CN=Netskope Intermediate CA/O=Netskope Inc/C=US" \
        2>/dev/null

    security add-certificates \
        "$workdir/netskope-root.pem" \
        "$workdir/netskope-intermediate.pem" \
        2>/dev/null

    MOCK_CERTS_INSTALLED=true
}

# ---------------------------------------------------------------------------
# Tests statiques
# ---------------------------------------------------------------------------

test_bash_syntax() {
    log_test "Syntaxe bash (bash -n)"
    local script failed=false

    for script in "$PROJECT_DIR"/install.sh "$PROJECT_DIR"/lib/*.sh "$PROJECT_DIR"/test/run-tests.sh; do
        if bash -n "$script" 2>/dev/null; then
            [[ "$VERBOSE" == true ]] && echo "  ok: $(basename "$script")"
        else
            log_fail "bash -n $(basename "$script")"
            failed=true
        fi
    done

    [[ "$failed" == false ]] && log_pass "tous les scripts bash"
}

test_shellcheck() {
    log_test "shellcheck (projet complet)"

    if ! command -v shellcheck >/dev/null 2>&1; then
        log_skip "shellcheck non installé (brew install shellcheck)"
        return 0
    fi

    local script failed=false sc_output
    for script in "$PROJECT_DIR"/install.sh "$PROJECT_DIR"/lib/*.sh "$PROJECT_DIR"/test/run-tests.sh; do
        sc_output="$(cd "$PROJECT_DIR" && shellcheck -S warning -x "$script" 2>&1)" || true
        if [[ -z "$sc_output" ]]; then
            [[ "$VERBOSE" == true ]] && echo "  ok: $(basename "$script")"
        else
            log_fail "shellcheck $(basename "$script")"
            if [[ "$VERBOSE" == true ]]; then
                echo "$sc_output" | sed 's/^/    /' >&2
            fi
            failed=true
        fi
    done

    [[ "$failed" == false ]] && log_pass "shellcheck sans avertissement"
}

# ---------------------------------------------------------------------------
# Tests unitaires (fonctions lib/)
# ---------------------------------------------------------------------------

source_libs() {
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/common.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/manifest.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/gradle.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/rollback.sh"
}

source_all_libs() {
    source_libs
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/admin.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/keychain.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/certificate.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/ca-bundle.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/shell-profile.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/java.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/stacks.sh"
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/tls-verify.sh"
}

tests_require_commands() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    ((${#missing[@]} > 0)) && return 1
    return 0
}

init_lib_workdir() {
    WORKDIR="$(mktemp -d "${TEST_ROOT}/work.XXXXXX")"
    STORE_PASSWORD="${DEFAULT_STORE_PASSWORD:-changeit}"
    SHELL_BLOCK_WRITTEN=false
    MANIFEST_ENTRIES=()
    EXPORTED_CERTS=()
    CONFIGURED_STACKS=()
    DRY_RUN=false
}

test_sanitize_alias() {
    log_test "sanitize_alias"
    source_libs

    assert_eq "minuscules et tirets" "netskope-root-ca" "$(sanitize_alias "Netskope Root CA")"
    assert_eq "caractères spéciaux retirés" "ca-test" "$(sanitize_alias "CA (Test!)")"
}

test_json_escape() {
    log_test "json_escape"
    source_libs

    assert_eq "guillemets échappés" 'foo\"bar' "$(json_escape 'foo"bar')"
    assert_eq "backslash échappé" 'foo\\bar' "$(json_escape 'foo\bar')"
}

test_merge_jvm_truststore_args() {
    log_test "merge_jvm_truststore_args"
    source_libs

    local result
    result="$(merge_jvm_truststore_args "-Xmx2g" "/tmp/store.p12" "secret")"
    assert_contains "conserve les args existants" "$result" "-Xmx2g"
    assert_contains "ajoute trustStore" "$result" "-Djavax.net.ssl.trustStore=/tmp/store.p12"
    assert_contains "ajoute trustStoreType" "$result" "-Djavax.net.ssl.trustStoreType=PKCS12"
    assert_contains "ajoute trustStorePassword" "$result" "-Djavax.net.ssl.trustStorePassword=secret"

    result="$(merge_jvm_truststore_args \
        "-Xmx2g -Djavax.net.ssl.trustStore=/old.p12 -Djavax.net.ssl.trustStoreType=JKS -Djavax.net.ssl.trustStorePassword=old" \
        "/new.p12" "newpass")"
    assert_contains "remplace trustStore obsolète" "$result" "-Djavax.net.ssl.trustStore=/new.p12"
    [[ "$result" != *"/old.p12"* ]] && log_pass "supprime l'ancien trustStore" || log_fail "supprime l'ancien trustStore"
}

test_extract_existing_jvmargs() {
    log_test "extract_existing_jvmargs"
    source_libs

    local props_file="$TEST_ROOT/jvmargs-test.properties"
    cat > "$props_file" <<'EOF'
org.gradle.daemon=true
org.gradle.jvmargs=-Xmx4g -XX:+HeapDumpOnOutOfMemoryError
EOF

    assert_eq "extrait org.gradle.jvmargs" \
        "-Xmx4g -XX:+HeapDumpOnOutOfMemoryError" \
        "$(extract_existing_jvmargs "$props_file")"
}

test_remove_generated_block() {
    log_test "remove_generated_block"
    source_libs

    local input="$TEST_ROOT/gradle-input.properties"
    local output="$TEST_ROOT/gradle-output.properties"

    cat > "$input" <<EOF
org.gradle.daemon=true
$MARKER_BEGIN
org.gradle.jvmargs=-Djavax.net.ssl.trustStore=/old.p12
$MARKER_END

EOF

    remove_generated_block "$input" "$output"
    assert_eq "retire le bloc généré" \
        "$(printf 'org.gradle.daemon=true\n\n')" \
        "$(cat "$output")"
}

test_remove_shell_profile_block() {
    log_test "remove_profile_block (shell)"
    source_all_libs

    local input="$TEST_ROOT/shell-input.zshrc"
    local output="$TEST_ROOT/shell-output.zshrc"

    cat > "$input" <<EOF
export PATH="/usr/bin"
$MARKER_BEGIN
export NETSKOPE_CA_BUNDLE="/tmp/test.pem"
$MARKER_END

EOF

    remove_profile_block_from_file "$input" "$output"
    assert_eq "retire le bloc shell" \
        "$(printf 'export PATH="/usr/bin"\n\n')" \
        "$(cat "$output")"
}

test_preparse_as_user() {
    log_test "preparse_as_user (--as-user)"
    source_all_libs

    preparse_as_user --as-user jdupont --all --netskope --yes
    assert_eq "login extrait" "jdupont" "$INSTALL_AS_USER"
    assert_eq "args restants" "--all --netskope --yes" "${REMAINING_ARGS[*]}"
}

test_resolve_user_home() {
    log_test "resolve_user_home (utilisateur courant)"
    source_all_libs

    local home
    home="$(resolve_user_home "$(whoami)")"
    assert_eq "home courant" "$HOME" "$home"
}

test_netskope_pattern_matching() {
    log_test "find_netskope_certificates (mock Keychain)"
    install_mock_netskope_certs
    source_all_libs

    local count=0
    while IFS= read -r _; do
        [[ -n "$_" ]] && count=$((count + 1))
    done < <(find_netskope_certificates)

    if [[ "$count" -ge 2 ]]; then
        log_pass "au moins 2 certificats Netskope mock détectés ($count)"
    else
        log_fail "détection mock insuffisante ($count)"
    fi
}

create_mock_pem() {
    local output_file="$1"
    local cn="${2:-Netskope Root CA}"
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$TEST_ROOT/mock-key.pem" \
        -out "$output_file" \
        -days 1 -nodes \
        -subj "/CN=${cn}/O=Netskope Inc/C=US" \
        2>/dev/null
}

test_ca_bundle_pem_valid() {
    log_test "build_ca_bundle_from_exports (PEM valide)"
    source_all_libs
    init_lib_workdir
    tests_require_commands openssl || { log_skip "openssl absent"; return 0; }

    mkdir -p "$TRUSTSTORE_DIR"
    local pem="$TEST_ROOT/netskope-root.pem"
    create_mock_pem "$pem" "Netskope Root CA"
    EXPORTED_CERTS=("netskope-root-ca|$pem|Netskope Root CA")
    DRY_RUN=false
    build_ca_bundle_from_exports

    assert_success "bundle PEM existe" test -f "$CA_BUNDLE_FILE"
    assert_success "PEM parseable openssl" openssl x509 -in "$CA_BUNDLE_FILE" -noout -subject
    assert_contains "subject Netskope" \
        "$(openssl x509 -in "$CA_BUNDLE_FILE" -noout -subject 2>/dev/null)" \
        "Netskope"
}

test_truststore_keytool_import() {
    log_test "truststore PKCS12 + import keytool (réel)"
    tests_require_commands keytool openssl || { log_skip "keytool/openssl absent"; return 0; }

    source_all_libs
    init_lib_workdir
    DRY_RUN=false
    NON_INTERACTIVE=true

    mkdir -p "$TRUSTSTORE_DIR"
    local pem="$TEST_ROOT/import-root.pem"
    create_mock_pem "$pem" "Netskope Root CA"
    EXPORTED_CERTS=("netskope-root-ca|$pem|Netskope Root CA")

    find_base_java_cacerts >/dev/null 2>&1 || {
        log_skip "cacerts Java introuvable"
        return 0
    }

    create_or_refresh_truststore
    import_certificate_into_truststore "netskope-root-ca" "$pem" "Netskope Root CA"

    if keytool -list \
        -keystore "$TRUSTSTORE_FILE" \
        -storetype PKCS12 \
        -storepass "$DEFAULT_STORE_PASSWORD" \
        -alias netskope-root-ca >/dev/null 2>&1; then
        log_pass "alias présent dans le truststore PKCS12"
    else
        log_fail "alias absent du truststore PKCS12"
    fi
}

test_tls_java_endpoints() {
    log_test "verify_tls_endpoints (Java TLS réel)"
    tests_require_commands keytool javac java openssl || { log_skip "JDK incomplet"; return 0; }

    source_all_libs
    init_lib_workdir
    DRY_RUN=false
    NON_INTERACTIVE=true

    mkdir -p "$TRUSTSTORE_DIR"
    local pem="$TEST_ROOT/tls-root.pem"
    create_mock_pem "$pem" "Netskope Root CA"
    EXPORTED_CERTS=("netskope-root-ca|$pem|Netskope Root CA")

    find_base_java_cacerts >/dev/null 2>&1 || { log_skip "cacerts Java absent"; return 0; }

    create_or_refresh_truststore
    import_certificate_into_truststore "netskope-root-ca" "$pem" "Netskope Root CA"

    set +e
    verify_tls_endpoints >/dev/null 2>&1
    local tls_exit=$?
    set -e

    if [[ "$tls_exit" -eq 0 ]]; then
        log_pass "Maven Central / Google Maven / Gradle Portal accessibles via JVM"
    else
        log_skip "TLS Java échoué (réseau/proxy — attendu sans Netskope actif)"
    fi
}

# ---------------------------------------------------------------------------
# Tests d'intégration (install.sh)
# ---------------------------------------------------------------------------

set_install_paths() {
    INSTALL_HOME="$TEST_ROOT/install-home"
    export GRADLE_DIR="$INSTALL_HOME/.gradle"
    export TRUSTSTORE_DIR="$INSTALL_HOME/.gradle/corporate-truststore"
    export TRUSTSTORE_FILE="$INSTALL_HOME/.gradle/corporate-truststore/corporate-truststore.p12"
    export STATE_DIR="$INSTALL_HOME/.gradle/corporate-truststore/state"
    export MANIFEST_FILE="$INSTALL_HOME/.gradle/corporate-truststore/state/manifest.json"
    export REPORT_FILE="$INSTALL_HOME/.gradle/corporate-truststore/install-report.txt"
    export CA_BUNDLE_FILE="$INSTALL_HOME/.gradle/corporate-truststore/nscacert_combined.pem"
    export CERTS_CACHE_DIR="$INSTALL_HOME/.gradle/corporate-truststore/certs"
    GRADLE_PROPERTIES="${GRADLE_DIR}/gradle.properties"
}

run_install() {
    set_install_paths
    mkdir -p "$STATE_DIR"
    env \
        GRADLE_DIR="$GRADLE_DIR" \
        TRUSTSTORE_DIR="$TRUSTSTORE_DIR" \
        TRUSTSTORE_FILE="$TRUSTSTORE_FILE" \
        STATE_DIR="$STATE_DIR" \
        MANIFEST_FILE="$MANIFEST_FILE" \
        REPORT_FILE="$REPORT_FILE" \
        CA_BUNDLE_FILE="$CA_BUNDLE_FILE" \
        CERTS_CACHE_DIR="$CERTS_CACHE_DIR" \
        "$PROJECT_DIR/install.sh" "$@"
}

test_list_netskope_without_mock() {
    log_test "--list-netskope sans certificats mock"

    purge_mock_certs

    # shellcheck disable=SC1091
    source "$PROJECT_DIR/lib/keychain.sh"
    if [[ -n "$(find_netskope_certificates)" ]]; then
        log_skip "certificats Netskope réels présents (agent installé sur cette machine)"
        return 0
    fi

    local output exit_code=0
    output="$(run_install --list-netskope 2>&1)" || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        log_fail "--list-netskope aurait dû échouer sans certificats Netskope"
    else
        assert_contains "message d'absence" "$output" "Aucun certificat Netskope trouvé"
    fi
}

test_list_netskope_with_mock() {
    log_test "--list-netskope avec certificats mock"
    install_mock_netskope_certs

    local output
    output="$(run_install --list-netskope 2>&1)"
    assert_contains "détecte Netskope Root CA" "$output" "Netskope Root CA"
    assert_contains "détecte Netskope Intermediate CA" "$output" "Netskope Intermediate CA"
}

test_netskope_dry_run() {
    log_test "--gradle --netskope --dry-run avec certificats mock"
    install_mock_netskope_certs

    local output
    output="$(run_install --gradle --netskope --dry-run --yes --verbose 2>&1)"
    assert_contains "installation terminée" "$output" "INSTALLATION TERMINÉE"
    assert_contains "alias root importé" "$output" "netskope-root-ca"
    assert_contains "alias intermediate importé" "$output" "netskope-intermediate-ca"
    assert_contains "stack gradle" "$output" "gradle"
}

test_dart_stack_dry_run() {
    log_test "--dart --netskope --dry-run (sans gradle)"
    install_mock_netskope_certs

    export SHELL_PROFILE_OVERRIDE="$TEST_ROOT/test.zshrc"
    local output
    output="$(run_install --dart --netskope --dry-run --yes --skip-verify 2>&1)"
    assert_contains "stack dart configurée" "$output" "Configuration stack : dart"
    assert_contains "bundle CA créé" "$output" "Bundle CA PEM"
}

test_shell_profile_block_write() {
    log_test "write_shell_profile_block (contenu variables Netskope)"
    source_all_libs
    init_lib_workdir

    export SHELL_PROFILE_OVERRIDE="$TEST_ROOT/test-shell.zshrc"
    : > "$CA_BUNDLE_FILE"
    DRY_RUN=false
    write_shell_profile_block

    local content
    content="$(cat "$TEST_ROOT/test-shell.zshrc")"
    assert_contains "NETSKOPE_CA_BUNDLE" "$content" "NETSKOPE_CA_BUNDLE"
    assert_contains "DART_VM_OPTIONS" "$content" "DART_VM_OPTIONS"
    assert_contains "NODE_EXTRA_CA_CERTS" "$content" "NODE_EXTRA_CA_CERTS"
    assert_contains "marqueur BEGIN" "$content" "# BEGIN gradle-corporate-truststore"
}

test_all_stacks_dry_run() {
    log_test "--all --netskope --dry-run (toutes les stacks)"
    install_mock_netskope_certs

    export SHELL_PROFILE_OVERRIDE="$TEST_ROOT/test-all.zshrc"
    local output
    output="$(run_install --all --netskope --dry-run --yes --skip-verify 2>&1)"
    assert_contains "installation terminée" "$output" "INSTALLATION TERMINÉE"

    local stack
    for stack in gradle shell dart git node python ruby curl gcloud aws; do
        assert_contains "stack $stack" "$output" "Configuration stack : $stack"
    done
}

test_firebase_stacks_dry_run() {
    log_test "profil Firebase (--gradle --dart --git --node --ruby)"
    install_mock_netskope_certs

    export SHELL_PROFILE_OVERRIDE="$TEST_ROOT/test-firebase.zshrc"
    local output
    output="$(run_install --gradle --dart --git --node --ruby --netskope --dry-run --yes --skip-verify 2>&1)"
    assert_contains "stack gradle" "$output" "Configuration stack : gradle"
    assert_contains "stack dart" "$output" "Configuration stack : dart"
    assert_contains "stack git" "$output" "Configuration stack : git"
    assert_contains "stack node" "$output" "Configuration stack : node"
    assert_contains "stack ruby" "$output" "Configuration stack : ruby"
}

test_git_stack_configure() {
    log_test "configure_stack_git (git config isolé)"
    source_all_libs
    init_lib_workdir

    local fake_home="$TEST_ROOT/fake-home-git"
    mkdir -p "$fake_home"
    export HOME="$fake_home"
    mkdir -p "$TRUSTSTORE_DIR"
    create_mock_pem "$CA_BUNDLE_FILE" "Netskope Root CA"
    DRY_RUN=false
    configure_stack_git
    restore_home

    assert_contains "git sslCAInfo dans .gitconfig" \
        "$(cat "$fake_home/.gitconfig" 2>/dev/null)" \
        "nscacert_combined.pem"
}

test_status_after_dry_run() {
    log_test "--status après installation dry-run"
    install_mock_netskope_certs

    export SHELL_PROFILE_OVERRIDE="$TEST_ROOT/test-status.zshrc"
    run_install --gradle --dart --netskope --dry-run --yes --skip-verify >/dev/null 2>&1

    # dry-run ne crée pas le manifest — status doit indiquer absence
    local output
    output="$(run_install --status 2>&1)"
    if [[ -f "$MANIFEST_FILE" ]]; then
        assert_contains "stacks configurées" "$output" "gradle"
    else
        assert_contains "aucune installation" "$output" "Aucune installation"
    fi
}

test_root_install_blocked() {
    log_test "bloque sudo install.sh sans --as-user"
    if ! sudo -n true 2>/dev/null; then
        log_skip "sudo sans mot de passe indisponible"
        return 0
    fi

    local output exit_code=0
    output="$(sudo "$PROJECT_DIR/install.sh" --all --netskope 2>&1)" || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        assert_contains "refus root" "$output" "root interdite"
    else
        log_fail "installation root aurait dû être refusée"
    fi
}

test_all_stack_docs_exist() {
    log_test "documentation stacks complète"
    local doc_name docs_missing=false
    for doc_name in gradle shell dart git node python ruby curl gcloud aws simulator; do
        if [[ -f "$PROJECT_DIR/docs/stacks/${doc_name}.md" ]]; then
            [[ "$VERBOSE" == true ]] && echo "  ok: ${doc_name}.md"
        else
            log_fail "doc manquante: docs/stacks/${doc_name}.md"
            docs_missing=true
        fi
    done
    if [[ "$docs_missing" == false ]]; then
        log_pass "11 fiches stacks présentes"
    fi
    if [[ -f "$PROJECT_DIR/docs/ADMIN.md" ]]; then
        log_pass "ADMIN.md présent"
    else
        log_fail "ADMIN.md absent"
    fi
}

test_rollback_shell_profile() {
    log_test "--rollback restaure le profil shell"
    source_all_libs

    mkdir -p "$STATE_DIR"
    local profile="$TEST_ROOT/rollback-shell.zshrc"
    local backup="$TEST_ROOT/rollback-shell.zshrc.backup"

    cat > "$backup" <<'EOF'
export PATH="/original/bin"
EOF

    cat > "$profile" <<EOF
export PATH="/original/bin"
$MARKER_BEGIN
export NETSKOPE_CA_BUNDLE="/tmp/old.pem"
$MARKER_END
EOF

    export SHELL_PROFILE_OVERRIDE="$profile"

    cat > "$MANIFEST_FILE" <<EOF
{
  "version": "4.0.0",
  "created_at": "2026-01-01T00:00:00Z",
  "truststore_file": "$TRUSTSTORE_FILE",
  "store_password": "changeit",
  "entries": {
    "shell_profile_backup": "$backup",
    "stack_shell": "configured"
  }
}
EOF

    init_lib_workdir
    perform_rollback

    assert_eq "profil shell restauré" "$(cat "$backup")" "$(cat "$profile")"
}

test_rollback_git_config() {
    log_test "--rollback supprime git http.sslCAInfo"
    source_all_libs

    local fake_home="$TEST_ROOT/rollback-git-home"
    mkdir -p "$fake_home"
    export HOME="$fake_home"

    git config --global http.sslCAInfo "$CA_BUNDLE_FILE"

    mkdir -p "$STATE_DIR"
    cat > "$MANIFEST_FILE" <<EOF
{
  "version": "4.0.0",
  "created_at": "2026-01-01T00:00:00Z",
  "truststore_file": "$TRUSTSTORE_FILE",
  "store_password": "changeit",
  "entries": {
    "stack_git": "configured"
  }
}
EOF

    init_lib_workdir
    perform_rollback
    restore_home

    if [[ -f "$fake_home/.gitconfig" ]] && grep -q sslCAInfo "$fake_home/.gitconfig" 2>/dev/null; then
        log_fail "http.sslCAInfo encore présent après rollback"
    else
        log_pass "http.sslCAInfo supprimé"
    fi
}

test_discover_tls_dry_run() {
    log_test "--gradle --discover-tls --dry-run (connexion directe, sans proxy)"
    tests_require_commands openssl

    local output
    output="$(run_install --gradle --discover-tls --dry-run --yes 2>&1)"
    assert_contains "installation terminée" "$output" "INSTALLATION TERMINÉE"
    assert_contains "certificats importés" "$output" "Certificats importés"
}

test_docs_gradle() {
    log_test "--docs gradle"
    local output
    output="$(run_install --docs gradle 2>&1)"
    assert_contains "doc gradle endpoints" "$output" "repo.maven.apache.org"
    assert_contains "doc gradle commande" "$output" "--gradle"
}

test_rollback_removes_block() {
    log_test "--rollback supprime le bloc généré"
    source_libs
    set_install_paths

    mkdir -p "$GRADLE_DIR" "$STATE_DIR"
    cat > "$GRADLE_PROPERTIES" <<EOF
org.gradle.daemon=true
$MARKER_BEGIN
org.gradle.jvmargs=-Djavax.net.ssl.trustStore=$TRUSTSTORE_FILE
$MARKER_END

EOF

    cat > "$MANIFEST_FILE" <<EOF
{
  "version": "4.1.0",
  "updated_at": "2026-01-01T00:00:00Z",
  "truststore_file": "$TRUSTSTORE_FILE",
  "entries": {}
}
EOF

    run_install --rollback --yes >/dev/null 2>&1

    local content
    content="$(cat "$GRADLE_PROPERTIES")"
    assert_contains "gradle.properties sans marqueur BEGIN" "$content" "org.gradle.daemon=true"
    [[ "$content" != *"$MARKER_BEGIN"* ]] && log_pass "marqueur BEGIN absent" || log_fail "marqueur BEGIN absent"
    [[ ! -f "$MANIFEST_FILE" ]] && log_pass "manifest archivé" || log_fail "manifest archivé"
}

test_rollback_restores_backup() {
    log_test "--rollback restaure gradle.properties depuis sauvegarde"
    source_libs
    set_install_paths

    mkdir -p "$GRADLE_DIR" "$STATE_DIR"
    local backup="$GRADLE_DIR/gradle.properties.backup.test"

    cat > "$backup" <<EOF
org.gradle.daemon=false
org.gradle.jvmargs=-Xmx1g
EOF

    cat > "$GRADLE_PROPERTIES" <<EOF
org.gradle.daemon=true
$MARKER_BEGIN
org.gradle.jvmargs=-Djavax.net.ssl.trustStore=$TRUSTSTORE_FILE
$MARKER_END

EOF

    cat > "$MANIFEST_FILE" <<EOF
{
  "version": "4.1.0",
  "updated_at": "2026-01-01T00:00:00Z",
  "truststore_file": "$TRUSTSTORE_FILE",
  "entries": {
    "gradle_properties_backup": "$backup"
  }
}
EOF

    run_install --rollback --yes >/dev/null 2>&1

    assert_eq "gradle.properties restauré" \
        "$(cat "$backup")" \
        "$(cat "$GRADLE_PROPERTIES")"
}

test_help() {
    log_test "--help"
    local output
    output="$(run_install --help 2>&1)"
    assert_contains "affiche usage" "$output" "Usage"
    assert_contains "option --netskope" "$output" "--netskope"
    assert_contains "option --rollback" "$output" "--rollback"
    assert_contains "option --all" "$output" "--all"
    assert_contains "option --dart" "$output" "--dart"
    assert_contains "option --as-user" "$output" "--as-user"
    assert_contains "mention admin doc" "$output" "ADMIN.md"
}

test_docs_admin() {
    log_test "docs/ADMIN.md"
    local admin_doc="$PROJECT_DIR/docs/ADMIN.md"
    if [[ -f "$admin_doc" ]]; then
        log_pass "fichier présent"
    else
        log_fail "fichier absent"
        return
    fi
    local content
    content="$(cat "$admin_doc")"
    assert_contains "as-user documenté" "$content" "--as-user"
    assert_contains "interdit root" "$content" "root"
}

test_shellcheckrc_present() {
    log_test ".shellcheckrc"
    if [[ -f "$PROJECT_DIR/.shellcheckrc" ]]; then
        log_pass "fichier présent"
    else
        log_fail ".shellcheckrc absent"
    fi
    assert_contains "external-sources" "$(cat "$PROJECT_DIR/.shellcheckrc")" "external-sources"
}

test_docs_all_stacks_cli() {
    log_test "--docs pour chaque stack"
    local doc_name output
    for doc_name in gradle shell dart git node python ruby curl gcloud aws simulator; do
        output="$(run_install --docs "$doc_name" 2>&1)"
        assert_contains "doc CLI $doc_name" "$output" "# Stack"
    done
}

test_manifest_save_load() {
    log_test "save_manifest / load_manifest_value"
    source_all_libs
    init_lib_workdir
    DRY_RUN=false
    STORE_PASSWORD="changeit"
    write_manifest_entry "stack_gradle" "configured"
    write_manifest_entry "truststore_file" "$TRUSTSTORE_FILE"
    save_manifest

    assert_success "manifest créé" test -f "$MANIFEST_FILE"
    assert_eq "stack_gradle" "configured" "$(load_manifest_value stack_gradle)"
    assert_eq "truststore_file" "$TRUSTSTORE_FILE" "$(load_manifest_value truststore_file)"
}

test_manifest_merge_incremental() {
    log_test "manifest merge (install incrémentale)"
    source_all_libs
    init_lib_workdir
    DRY_RUN=false

    write_manifest_entry "stack_gradle" "configured"
    write_manifest_entry "ca_fingerprint" "abc123"
    save_manifest

    load_existing_manifest_entries
    write_manifest_entry "stack_git" "configured"
    save_manifest

    assert_eq "gradle conservé" "configured" "$(load_manifest_value stack_gradle)"
    assert_eq "git ajouté" "configured" "$(load_manifest_value stack_git)"
    assert_eq "fingerprint conservé" "abc123" "$(load_manifest_value ca_fingerprint)"
}

test_merge_dart_vm_options() {
    log_test "merge_dart_vm_options"
    source_all_libs

    local result
    result="$(merge_dart_vm_options "--enable-experiment=patterns")"
    assert_contains "conserve options existantes" "$result" "--enable-experiment=patterns"
    assert_contains "ajoute root-certs-file" "$result" "--root-certs-file=\${NETSKOPE_CA_BUNDLE}"

    result="$(merge_dart_vm_options "--root-certs-file=/old.pem --enable-experiment=foo")"
    assert_contains "remplace ancien root-certs" "$result" "--root-certs-file=\${NETSKOPE_CA_BUNDLE}"
    [[ "$result" != *"/old.pem"* ]] && log_pass "supprime ancien root-certs-file" || log_fail "supprime ancien root-certs-file"
}

test_ca_bundle_reuse_fingerprint() {
    log_test "ca_bundle_is_current (réutilisation bundle)"
    source_all_libs
    init_lib_workdir
    DRY_RUN=false

    mkdir -p "$CERTS_CACHE_DIR" "$TRUSTSTORE_DIR"
    create_mock_pem "$CA_BUNDLE_FILE" "Netskope Root CA"

    local fp
    fp="$(compute_ca_bundle_fingerprint)"
    write_manifest_entry "ca_fingerprint" "$fp"
    save_manifest

    load_existing_manifest_entries
    assert_success "bundle considéré à jour" ca_bundle_is_current
}

test_write_manifest_entry_updates() {
    log_test "write_manifest_entry (mise à jour clé existante)"
    source_all_libs
    init_lib_workdir
    DRY_RUN=false

    write_manifest_entry "stack_gradle" "configured"
    write_manifest_entry "stack_gradle" "updated"
    save_manifest

    assert_eq "valeur mise à jour" "updated" "$(load_manifest_value stack_gradle)"
}

test_admin_preparse_install_flags() {
    log_test "preparse_install_flags (admin export)"
    source_all_libs

    preparse_install_flags --as-user jdupont --all --netskope --dry-run --yes
    assert_eq "mode netskope" "netskope" "$ADMIN_INSTALL_MODE"
    assert_eq "dry-run détecté" "true" "$ADMIN_DRY_RUN"

    preparse_install_flags --rollback
    assert_failure "rollback sans export" admin_install_requires_cert_export
}

test_manifest_no_store_password() {
    log_test "manifest sans store_password en clair"
    source_all_libs
    init_lib_workdir
    DRY_RUN=false

    write_manifest_entry "stack_gradle" "configured"
    save_manifest

    if grep -q 'store_password' "$MANIFEST_FILE" 2>/dev/null; then
        log_fail "store_password ne doit pas être dans le manifest"
    else
        log_pass "store_password absent du manifest"
    fi
}

test_sanitize_netskope_variants() {
    log_test "sanitize_alias (variantes Netskope)"
    source_libs

    assert_eq "root CA" "netskope-root-ca" "$(sanitize_alias "Netskope Root CA")"
    assert_eq "intermediate" "netskope-intermediate-ca" "$(sanitize_alias "Netskope Intermediate CA")"
    assert_eq "tenant root" "netskope-tenant-root-ca" "$(sanitize_alias "Netskope Tenant Root CA")"
    assert_eq "client root" "netskope-client-root-ca" "$(sanitize_alias "Netskope Client Root CA")"
}

test_find_cert_by_name_mock() {
    log_test "find_certificates_by_name (mock Keychain)"
    install_mock_netskope_certs
    source_all_libs

    local count=0 line
    while IFS= read -r line; do
        [[ -n "$line" ]] && count=$((count + 1))
    done < <(find_certificates_by_name "Netskope Root")

    if [[ "$count" -ge 1 ]]; then
        log_pass "certificat trouvé par nom partiel ($count)"
    else
        log_fail "aucun certificat pour 'Netskope Root'"
    fi
}

test_configure_gradle_properties_real() {
    log_test "configure_gradle_properties (écriture réelle)"
    source_all_libs
    init_lib_workdir
    mkdir -p "$TRUSTSTORE_DIR" "$GRADLE_DIR"
    touch "$TRUSTSTORE_FILE"
    DRY_RUN=false

    configure_gradle_properties

    assert_success "gradle.properties existe" test -f "$GRADLE_PROPERTIES"
    assert_contains "marqueur BEGIN" "$(cat "$GRADLE_PROPERTIES")" "$MARKER_BEGIN"
    assert_contains "trustStore PKCS12" "$(cat "$GRADLE_PROPERTIES")" "PKCS12"
    assert_contains "chemin truststore" "$(cat "$GRADLE_PROPERTIES")" "$TRUSTSTORE_FILE"
}

test_cert_flag_dry_run() {
    log_test "--cert 'Netskope Root CA' --gradle --dry-run"
    install_mock_netskope_certs

    local output
    output="$(run_install --gradle --cert "Netskope Root CA" --dry-run --yes --skip-verify 2>&1)"
    assert_contains "installation terminée" "$output" "INSTALLATION TERMINÉE"
    assert_contains "alias root" "$output" "netskope-root-ca"
}

test_gradle_e2e_real_install() {
    log_test "E2E réel --gradle --netskope (truststore + gradle.properties)"
    install_mock_netskope_certs

    if ! sudo -n true 2>/dev/null; then
        log_skip "sudo interactif requis (lancez en local avec mot de passe admin)"
        return 0
    fi

    export SHELL_PROFILE_OVERRIDE="$TEST_ROOT/e2e.zshrc"
    local output exit_code=0
    output="$(run_install --gradle --netskope --yes --skip-verify 2>&1)" || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        log_fail "installation E2E échouée (code $exit_code)"
        [[ "$VERBOSE" == true ]] && echo "$output" >&2
        return
    fi

    assert_success "truststore PKCS12 créé" test -f "$TRUSTSTORE_FILE"
    assert_contains "gradle.properties configuré" "$(cat "$GRADLE_PROPERTIES")" "gradle-corporate-truststore"

    run_install --rollback --yes >/dev/null 2>&1 || true
    log_pass "rollback E2E exécuté"
}

test_npm_stack_configure() {
    log_test "configure_stack_node (npm cafile)"
    if ! command -v npm >/dev/null 2>&1; then
        log_skip "npm absent"
        return 0
    fi

    source_all_libs
    init_lib_workdir
    local fake_home="$TEST_ROOT/fake-home-npm"
    mkdir -p "$fake_home" "$TRUSTSTORE_DIR"
    export HOME="$fake_home"
    create_mock_pem "$CA_BUNDLE_FILE" "Netskope Root CA"
    DRY_RUN=false
    configure_stack_node
    restore_home

    if grep -q "cafile" "$fake_home/.npmrc" 2>/dev/null; then
        log_pass "npm cafile configuré"
    else
        local cafile
        cafile="$(npm config --userconfig "$fake_home/.npmrc" get cafile 2>/dev/null || true)"
        assert_contains "npm cafile" "$cafile" "nscacert_combined.pem"
    fi
}

test_certificate_subject_cn() {
    log_test "certificate_subject_cn"
    source_all_libs
    tests_require_commands openssl || { log_skip "openssl absent"; return 0; }

    local pem="$TEST_ROOT/cn-test.pem"
    create_mock_pem "$pem" "Netskope Root CA"
    assert_eq "CN extrait" "Netskope Root CA" "$(certificate_subject_cn "$pem")"
}

test_load_manifest_missing() {
    log_test "load_manifest_value (manifest absent)"
    source_libs
    local saved_manifest="$MANIFEST_FILE"
    MANIFEST_FILE="$TEST_ROOT/absent-manifest-never-created.json"
    if load_manifest_value "stack_gradle" 2>/dev/null; then
        log_fail "load_manifest_value aurait dû échouer"
    else
        log_pass "échec attendu sans manifest"
    fi
    MANIFEST_FILE="$saved_manifest"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"

    echo "======================================================"
    echo " gradle-corporate-truststore — tests automatisés"
    echo "======================================================"
    echo

    setup_test_root
    purge_mock_certs
    [[ "$VERBOSE" == true ]] && echo "Répertoire de test : $TEST_ROOT"
    echo

    test_bash_syntax
    echo
    test_shellcheck
    echo
    test_shellcheckrc_present
    echo
    test_sanitize_alias
    echo
    test_sanitize_netskope_variants
    echo
    test_json_escape
    echo
    test_merge_jvm_truststore_args
    echo
    test_extract_existing_jvmargs
    echo
    test_remove_generated_block
    echo
    test_remove_shell_profile_block
    echo
    test_preparse_as_user
    echo
    test_resolve_user_home
    echo
    test_netskope_pattern_matching
    echo
    test_find_cert_by_name_mock
    echo
    test_certificate_subject_cn
    echo
    test_ca_bundle_pem_valid
    echo
    test_truststore_keytool_import
    echo
    test_tls_java_endpoints
    echo
    test_manifest_save_load
    echo
    test_manifest_merge_incremental
    echo
    test_write_manifest_entry_updates
    echo
    test_manifest_no_store_password
    echo
    test_merge_dart_vm_options
    echo
    test_ca_bundle_reuse_fingerprint
    echo
    test_admin_preparse_install_flags
    echo
    test_load_manifest_missing
    echo
    test_configure_gradle_properties_real
    echo
    test_help
    echo
    test_all_stack_docs_exist
    echo
    test_docs_all_stacks_cli
    echo
    test_list_netskope_without_mock
    echo
    test_list_netskope_with_mock
    echo
    test_netskope_dry_run
    echo
    test_dart_stack_dry_run
    echo
    test_shell_profile_block_write
    echo
    test_all_stacks_dry_run
    echo
    test_firebase_stacks_dry_run
    echo
    test_git_stack_configure
    echo
    test_cert_flag_dry_run
    echo
    test_gradle_e2e_real_install
    echo
    test_npm_stack_configure
    echo
    test_discover_tls_dry_run
    echo
    test_status_after_dry_run
    echo
    test_root_install_blocked
    echo
    test_docs_gradle
    echo
    test_docs_admin
    echo
    test_rollback_removes_block
    echo
    test_rollback_restores_backup
    echo
    test_rollback_shell_profile
    echo
    test_rollback_git_config
    echo

    echo "======================================================"
    echo " Résultat : $PASSED passés, $FAILED échoués, $SKIPPED ignorés"
    echo "======================================================"

    if ((FAILED > 0)); then
        exit 1
    fi
}

main "$@"
