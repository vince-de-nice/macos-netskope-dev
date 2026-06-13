#!/usr/bin/env bash
# shellcheck shell=bash
#
# Vérification TLS réelle via la JVM et le truststore PKCS12.

TLS_TEST_URLS=(
    "https://repo.maven.apache.org/maven2/"
    "https://dl.google.com/dl/android/maven2/"
    "https://plugins.gradle.org/m2/"
)

write_tls_test_java() {
    local java_file="$WORKDIR/TlsConnectivityTest.java"
    cat > "$java_file" <<'JAVA'
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public class TlsConnectivityTest {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("Usage: TlsConnectivityTest <url>");
            System.exit(2);
        }

        URL url = new URL(args[0]);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(20000);
        connection.setReadTimeout(20000);
        connection.setRequestMethod("HEAD");
        connection.connect();

        int code = connection.getResponseCode();
        InputStream stream = code >= 400 ? connection.getErrorStream() : connection.getInputStream();
        if (stream != null) {
            stream.close();
        }

        System.out.println("HTTP " + code);
        if (code >= 500) {
            System.exit(1);
        }
    }
}
JAVA
    echo "$java_file"
}

run_java_tls_test() {
    local url="$1"
    local java_bin javac_bin class_dir

    java_bin="$(find_java_bin_for_tests)" ||
        die "Impossible de trouver java pour les tests TLS."

    javac_bin="$(find_javac_bin_for_tests)" ||
        die "Impossible de trouver javac pour les tests TLS."

    class_dir="$WORKDIR/tls-test-classes"
    mkdir -p "$class_dir"

    local java_file
    java_file="$(write_tls_test_java)"

    "$javac_bin" -d "$class_dir" "$java_file"

    "$java_bin" \
        -Djavax.net.ssl.trustStore="$TRUSTSTORE_FILE" \
        -Djavax.net.ssl.trustStoreType=PKCS12 \
        -Djavax.net.ssl.trustStorePassword="$STORE_PASSWORD" \
        -cp "$class_dir" \
        TlsConnectivityTest \
        "$url"
}

verify_tls_endpoints() {
    local url failures=0

    if [[ "$DRY_RUN" == true ]]; then
        log "Mode dry-run : tests TLS ignorés."
        return 0
    fi

    [[ -f "$TRUSTSTORE_FILE" ]] ||
        die "Truststore absent pour les tests TLS : $TRUSTSTORE_FILE"

    log "Vérification TLS avec le truststore PKCS12..."
    report_line ""
    report_line "=== TLS Verification ==="

    for url in "${TLS_TEST_URLS[@]}"; do
        log "Test : $url"
        if run_java_tls_test "$url" > "$WORKDIR/tls-result.txt" 2> "$WORKDIR/tls-error.txt"; then
            log "  OK ($(tr -d '\n' < "$WORKDIR/tls-result.txt"))"
            report_line "OK $url -> $(tr -d '\n' < "$WORKDIR/tls-result.txt")"
        else
            warn "  ECHEC : $url"
            warn "  $(tr -d '\n' < "$WORKDIR/tls-error.txt" 2>/dev/null)"
            report_line "FAIL $url"
            report_line "$(cat "$WORKDIR/tls-error.txt" 2>/dev/null)"
            failures=$((failures + 1))
        fi
    done

    if ((failures > 0)); then
        die "$failures test(s) TLS ont échoué. Consultez $REPORT_FILE"
    fi

    log "Tous les tests TLS ont réussi."
}

probe_tls_hosts_for_report() {
    local host_port chain_file

    report_line ""
    report_line "=== TLS Probe (openssl) ==="

    for host_port in "${TLS_PROBE_HOSTS[@]}"; do
        chain_file="$WORKDIR/probe-${host_port//:/-}.pem"
        if extract_tls_chain_pem "$host_port" "$chain_file"; then
            report_line "Probe OK: $host_port"
            openssl x509 -in "$chain_file" -noout -subject -issuer >> "$REPORT_FILE" 2>/dev/null || true
        else
            report_line "Probe FAIL: $host_port"
        fi
        report_line ""
    done
}
