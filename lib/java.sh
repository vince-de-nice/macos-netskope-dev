#!/usr/bin/env bash
# shellcheck shell=bash
#
# Détection des JDK/JVM utilisés par Flutter, Gradle et Android Studio.

FLUTTER_JAVA_HOME=""
ANDROID_STUDIO_JBR=""
DETECTED_JAVA_HOMES=()

detect_android_studio_jbr() {
    local -a candidates=(
        "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        "/Applications/Android Studio.app/Contents/jbr"
    )
    local path
    for path in "${candidates[@]}"; do
        if [[ -d "$path" && -x "$path/bin/java" ]]; then
            ANDROID_STUDIO_JBR="$path"
            echo "$path"
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
        if [[ -x "$java_path" ]]; then
            FLUTTER_JAVA_HOME="$(cd "$(dirname "$java_path")/.." && pwd)"
            echo "$FLUTTER_JAVA_HOME"
            return 0
        fi
    fi

    return 1
}

detect_gradle_jvm() {
    local gradle_bin gradle_file jvm_line

    command -v gradle >/dev/null 2>&1 || return 1

    gradle_bin="$(command -v gradle)"
    gradle_file="$WORKDIR/gradle-version.txt"

    log "Analyse gradle -version..."
    if ! "$gradle_bin" -version > "$gradle_file" 2>&1; then
        warn "gradle -version a retourné une erreur."
        return 1
    fi

    jvm_line="$(grep '^JVM:' "$gradle_file" | head -1 || true)"
    report_line "Gradle JVM: $jvm_line"

    # Exemple : JVM: 21.0.8 (JetBrains s.r.o. 21.0.8+-14196175-b1038.72)
    if [[ "$jvm_line" =~ /Applications/Android\ Studio.app ]]; then
        detect_android_studio_jbr >/dev/null || true
    fi

    return 0
}

collect_java_homes() {
    local -a homes=()
    local home jbr

    if jbr="$(detect_android_studio_jbr 2>/dev/null)"; then
        homes+=("$jbr")
        report_line "Android Studio JBR: $jbr"
    fi

    if home="$(detect_flutter_java_home 2>/dev/null)"; then
        homes+=("$home")
        report_line "Flutter Java: $home"
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
    local home java_bin

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

report_java_environment() {
    report_line ""
    report_line "=== Java Environment ==="
    collect_java_homes
    report_line ""
}
