#!/usr/bin/env bash
#
# Déploie l'archive gradle-corporate-truststore sur le poste (première installation Intune).
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/intune-log.sh
source "$SCRIPT_DIR/lib/intune-log.sh"

GCT_INSTALL_DIR="${GCT_INSTALL_DIR:-/usr/local/share/gradle-corporate-truststore}"
ARCHIVE_PATH=""

usage() {
    cat <<EOF
Usage: $(basename "$0") /chemin/vers/gct-VERSION.tar.gz

Extrait l'archive dans ${GCT_INSTALL_DIR} et rend les scripts exécutables.
Doit s'exécuter en root.

EOF
}

main() {
    local tmp_dir version_file

    if [[ "$EUID" -ne 0 ]]; then
        intune_log_error "Ce script doit s'exécuter en root."
        exit 2
    fi

    ARCHIVE_PATH="${1:-}"
    [[ -f "$ARCHIVE_PATH" ]] || {
        usage
        exit 2
    }

    intune_ensure_log_dir
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/gct-deploy.XXXXXX")"

    tar -xzf "$ARCHIVE_PATH" -C "$tmp_dir"
    version_file="$(find "$tmp_dir" -maxdepth 1 -name 'gct-*' -type d | head -1)"
    [[ -n "$version_file" && -f "$version_file/install.sh" ]] || {
        intune_log_error "Archive invalide : install.sh introuvable."
        rm -rf "$tmp_dir"
        exit 2
    }

    mkdir -p "$GCT_INSTALL_DIR"
    rm -rf "${GCT_INSTALL_DIR:?}/"*
    cp -R "$version_file/." "$GCT_INSTALL_DIR/"
    chmod +x "$GCT_INSTALL_DIR/install.sh"
    chmod +x "$GCT_INSTALL_DIR/scripts/"*.sh

    rm -rf "$tmp_dir"

    intune_log_info "Déployé dans $GCT_INSTALL_DIR (version $(cat "$GCT_INSTALL_DIR/VERSION" 2>/dev/null || echo unknown))"
}

main "$@"
