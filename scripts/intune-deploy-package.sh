#!/usr/bin/env bash
#
# Déploie l'archive macos-netskope-dev sur le poste (première installation Intune).
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/intune-log.sh
source "$SCRIPT_DIR/lib/intune-log.sh"

MND_INSTALL_DIR="${MND_INSTALL_DIR:-/usr/local/share/macos-netskope-dev}"
MND_VERIFY_CHECKSUM="${MND_VERIFY_CHECKSUM:-1}"
ARCHIVE_PATH=""
CHECKSUM_PATH=""

usage() {
    cat <<EOF
Usage: $(basename "$0") /chemin/vers/mnd-VERSION.tar.gz [checksum.sha256]

Extrait l'archive dans ${MND_INSTALL_DIR} et rend les scripts exécutables.
Vérifie le SHA256 si le fichier .sha256 est fourni ou adjacent (MND_VERIFY_CHECKSUM=1).
Doit s'exécuter en root.

EOF
}

verify_archive_checksum() {
    local archive="$1"
    local checksum_file="${2:-}"

    [[ "$MND_VERIFY_CHECKSUM" == "1" ]] || return 0

    if [[ -z "$checksum_file" ]]; then
        checksum_file="${archive}.sha256"
    fi

    [[ -f "$checksum_file" ]] || {
        intune_log_warn "Checksum absent : $checksum_file (déploiement sans vérification)"
        return 0
    }

    intune_log_info "Vérification SHA256 : $checksum_file"
    (
        cd "$(dirname "$archive")" || exit 1
        shasum -a 256 -c "$(basename "$checksum_file")"
    ) || {
        intune_log_error "Checksum invalide pour $(basename "$archive")"
        return 1
    }
}

main() {
    local tmp_dir version_file

    if [[ "$EUID" -ne 0 ]]; then
        intune_log_error "Ce script doit s'exécuter en root."
        exit 2
    fi

    ARCHIVE_PATH="${1:-}"
    CHECKSUM_PATH="${2:-}"
    [[ -f "$ARCHIVE_PATH" ]] || {
        usage
        exit 2
    }

    intune_ensure_log_dir
    verify_archive_checksum "$ARCHIVE_PATH" "$CHECKSUM_PATH" || exit 2

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/mnd-deploy.XXXXXX")"

    tar -xzf "$ARCHIVE_PATH" -C "$tmp_dir"
    version_file="$(find "$tmp_dir" -maxdepth 1 -name 'mnd-*' -type d | head -1)"
    [[ -n "$version_file" && -f "$version_file/install.sh" ]] || {
        intune_log_error "Archive invalide : install.sh introuvable."
        rm -rf "$tmp_dir"
        exit 2
    }

    mkdir -p "$MND_INSTALL_DIR"
    rm -rf "${MND_INSTALL_DIR:?}/"*
    cp -R "$version_file/." "$MND_INSTALL_DIR/"
    chmod +x "$MND_INSTALL_DIR/install.sh"
    chmod +x "$MND_INSTALL_DIR/scripts/"*.sh

    rm -rf "$tmp_dir"

    intune_log_info "Déployé dans $MND_INSTALL_DIR (version $(cat "$MND_INSTALL_DIR/VERSION" 2>/dev/null || echo unknown))"
}

main "$@"
