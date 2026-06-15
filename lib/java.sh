#!/usr/bin/env bash
# shellcheck shell=bash
#
# Détection des JDK/JVM utilisés par Flutter, Gradle Wrapper et Android Studio.

FLUTTER_JAVA_HOME=""
ANDROID_STUDIO_JBR=""
GRADLE_JVM_HOME=""
PRIMARY_JAVA_HOME=""
DETECTED_JAVA_HOMES=()

java_home_from_binary() {
    local java_bin="$1"
    local home

    [[ -x "$java_bin" ]] || return 1
    home="$(cd "$(dirname "$java_bin")/.." && pwd)"
    [[ -d "$home" && -x "$home/bin/java" ]] || return 1
    echo "$home"
}

detect_android_studio_jbr() {
    local -a candidates=()
    local path

    candidates+=(
        "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        "/Applications/Android Studio.app/Contents/jbr"
        "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        "$HOME/Applications/Android Studio.app/Contents/jbr"
    )

    while IFS= read -r path; do
        [[ -n "$path" ]] && candidates+=("$path")
    done < <(compgen -G "/Applications/Android Studio*.app/Contents/jbr/Contents/Home" 2>/dev/null || true)

    for path in "${candidates[@]}"; do
        if [[ -d "$path" && -x "$path/bin/java" ]]; then
            ANDROID_STUDIO_JBR="$path"
            echo "$path"
            return 0
        fi
    done
    return 1
}

read_org_gradle_java_home() {
    local props_file="${GRADLE_DIR}/gradle.properties"
    local line home

    [[ -f "$props_file" ]] || return 1

    line="$(awk -F= '
        /^[[:space:]]*org\.gradle\.java\.home[[:space:]]*=/ {
            sub(/^[[:space:]]*org\.gradle\.java\.home[[:space:]]*=[[:space:]]*/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
    ' "$props_file")"

    [[ -n "$line" ]] || return 1

    home="${line/#\~/$HOME}"
    if [[ -d "$home" && -x "$home/bin/java" ]]; then
        echo "$home"
        return 0
    fi

    return 1
}

parse_gradle_version_file() {
    local gradle_file="$1"
    local line path

    [[ -f "$gradle_file" ]] || return 1

    # Gradle 8.8+ : chemin explicite du daemon JVM.
    line="$(grep -E '^Daemon JVM:' "$gradle_file" | head -1 || true)"
    if [[ -n "$line" ]]; then
        path="$(echo "$line" | sed -E 's/^Daemon JVM:[[:space:]]*//' | sed -E 's/[[:space:]]*\(.*//')"
        if path="$(java_home_from_binary "$path/bin/java" 2>/dev/null)"; then
            GRADLE_JVM_HOME="$path"
            echo "$path"
            return 0
        fi
        if [[ -d "$path" && -x "$path/bin/java" ]]; then
            GRADLE_JVM_HOME="$path"
            echo "$path"
            return 0
        fi
    fi

    line="$(grep '^JVM:' "$gradle_file" | head -1 || true)"
    if [[ "$line" =~ /Applications/Android\ Studio.app ]] || [[ "$line" =~ JetBrains ]]; then
        if path="$(detect_android_studio_jbr 2>/dev/null)"; then
            GRADLE_JVM_HOME="$path"
            echo "$path"
            return 0
        fi
    fi

    return 1
}

detect_gradlew_jvm() {
    local -a candidates=()
    local gradlew gradle_file path

    [[ -n "${MND_GRADLEW_PATH:-}" ]] && candidates+=("$MND_GRADLEW_PATH")
    candidates+=("$PWD/gradlew" "$PWD/android/gradlew")

    for gradlew in "${candidates[@]}"; do
        [[ -x "$gradlew" ]] || continue
        gradle_file="$WORKDIR/gradlew-version.txt"

        log "Analyse $gradlew -version..."
        if ! "$gradlew" -version > "$gradle_file" 2>&1; then
            warn "$gradlew -version a retourné une erreur."
            continue
        fi

        if path="$(parse_gradle_version_file "$gradle_file")"; then
            report_line "Gradle Wrapper JVM: $path"
            return 0
        fi
    done

    return 1
}

detect_flutter_java_home() {
    local flutter_bin doctor_file java_line java_path

    command -v flutter >/dev/null 2>&1 || return 1

    flutter_bin="$(command -v flutter)"
    doctor_file="$WORKDIR/flutter-doctor.txt"

    log "Analyse flutter doctor -v..."
    if ! "$flutter_bin" doctor -v > "$doctor_file" 2>&1; then
        warn "flutter doctor -v a retourné une erreur (continuation)."
    fi

    java_line="$(grep -i 'Java binary at:' "$doctor_file" | head -1 || true)"
    if [[ -n "$java_line" ]]; then
        java_path="$(echo "$java_line" | sed -E 's/.*Java binary at:[[:space:]]*//')"
        java_path="${java_path%% *}"
        if java_path="$(java_home_from_binary "$java_path")"; then
            FLUTTER_JAVA_HOME="$java_path"
            echo "$FLUTTER_JAVA_HOME"
            return 0
        fi
    fi

    return 1
}

detect_gradle_jvm() {
    local gradle_bin gradle_file path

    if path="$(detect_gradlew_jvm 2>/dev/null)"; then
        return 0
    fi

    command -v gradle >/dev/null 2>&1 || return 1

    gradle_bin="$(command -v gradle)"
    gradle_file="$WORKDIR/gradle-version.txt"

    log "Analyse gradle -version..."
    if ! "$gradle_bin" -version > "$gradle_file" 2>&1; then
        warn "gradle -version a retourné une erreur."
        return 1
    fi

    if path="$(parse_gradle_version_file "$gradle_file")"; then
        report_line "Gradle JVM: $path"
        return 0
    fi

    return 0
}

resolve_primary_java_home() {
    local home

    if [[ -n "$GRADLE_JVM_HOME" && -d "$GRADLE_JVM_HOME" ]]; then
        echo "$GRADLE_JVM_HOME"
        return 0
    fi

    if [[ -n "$FLUTTER_JAVA_HOME" && -d "$FLUTTER_JAVA_HOME" ]]; then
        echo "$FLUTTER_JAVA_HOME"
        return 0
    fi

    if [[ -n "$ANDROID_STUDIO_JBR" && -d "$ANDROID_STUDIO_JBR" ]]; then
        echo "$ANDROID_STUDIO_JBR"
        return 0
    fi

    if home="$(read_org_gradle_java_home 2>/dev/null)"; then
        echo "$home"
        return 0
    fi

    if [[ -n "${JAVA_HOME:-}" && -d "$JAVA_HOME" ]]; then
        echo "$JAVA_HOME"
        return 0
    fi

    if home="$(detect_android_studio_jbr 2>/dev/null)"; then
        echo "$home"
        return 0
    fi

    return 1
}

collect_java_homes() {
    local -a homes=()
    local home jbr

    detect_gradle_jvm || true

    if jbr="$(detect_android_studio_jbr 2>/dev/null)"; then
        homes+=("$jbr")
        report_line "Android Studio JBR: $jbr"
    fi

    if home="$(detect_flutter_java_home 2>/dev/null)"; then
        homes+=("$home")
        report_line "Flutter Java: $home"
    fi

    if [[ -n "$GRADLE_JVM_HOME" ]]; then
        homes+=("$GRADLE_JVM_HOME")
        report_line "Gradle JVM: $GRADLE_JVM_HOME"
    fi

    if home="$(read_org_gradle_java_home 2>/dev/null)"; then
        homes+=("$home")
        report_line "org.gradle.java.home: $home"
    fi

    if [[ -n "${JAVA_HOME:-}" && -d "$JAVA_HOME" ]]; then
        homes+=("$JAVA_HOME")
        report_line "JAVA_HOME: $JAVA_HOME"
    fi

    if command -v /usr/libexec/java_home >/dev/null 2>&1; then
        while IFS= read -r home; do
            [[ -n "$home" && -d "$home" ]] && homes+=("$home")
        done < <(/usr/libexec/java_home -V 2>&1 | sed -n 's/^[[:space:]]*[0-9].*:[[:space:]]*//p' | tr -d ')')
    fi

    DETECTED_JAVA_HOMES=()
    while IFS= read -r home; do
        [[ -n "$home" ]] && DETECTED_JAVA_HOMES+=("$home")
    done < <(printf '%s\n' "${homes[@]}" | awk '!seen[$0]++')

    if primary="$(resolve_primary_java_home 2>/dev/null)"; then
        PRIMARY_JAVA_HOME="$primary"
        report_line "Primary JVM (Gradle/Android): $PRIMARY_JAVA_HOME"
    else
        PRIMARY_JAVA_HOME=""
        warn "Aucun JDK Gradle/Android prioritaire détecté."
    fi

    if ((${#DETECTED_JAVA_HOMES[@]} == 0)); then
        warn "Aucun JDK détecté automatiquement."
    else
        log "JDK détectés (${#DETECTED_JAVA_HOMES[@]}) :"
        for home in "${DETECTED_JAVA_HOMES[@]}"; do
            log "  - $home"
        done
    fi
}

find_java_bin_for_tests() {
    local home

    if home="$(resolve_primary_java_home 2>/dev/null)" && [[ -x "$home/bin/java" ]]; then
        echo "$home/bin/java"
        return 0
    fi

    if [[ -n "$FLUTTER_JAVA_HOME" && -x "$FLUTTER_JAVA_HOME/bin/java" ]]; then
        echo "$FLUTTER_JAVA_HOME/bin/java"
        return 0
    fi

    if [[ -n "$ANDROID_STUDIO_JBR" && -x "$ANDROID_STUDIO_JBR/bin/java" ]]; then
        echo "$ANDROID_STUDIO_JBR/bin/java"
        return 0
    fi

    if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
        echo "$JAVA_HOME/bin/java"
        return 0
    fi

    if command -v java >/dev/null 2>&1; then
        command -v java
        return 0
    fi

    return 1
}

find_javac_bin_for_tests() {
    local java_bin javac_bin home

    java_bin="$(find_java_bin_for_tests)" || return 1
    home="$(cd "$(dirname "$java_bin")/.." && pwd)"
    javac_bin="$home/bin/javac"

    [[ -x "$javac_bin" ]] && echo "$javac_bin" && return 0
    command -v javac 2>/dev/null || return 1
}

find_keytool_for_truststore() {
    local home keytool_bin

    if home="$(resolve_primary_java_home 2>/dev/null)"; then
        keytool_bin="$home/bin/keytool"
        [[ -x "$keytool_bin" ]] && echo "$keytool_bin" && return 0
    fi

    command -v keytool 2>/dev/null || return 1
}

report_java_environment() {
    report_line ""
    report_line "=== Java Environment ==="
    collect_java_homes
    report_line ""
}
