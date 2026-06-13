#!/usr/bin/env bash
#
# Construit un package .pkg macOS pour déploiement MDM (wrapper autour de l'archive).
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DIST_DIR="$SCRIPT_DIR/dist"
PKG_ID="com.macos-netskope-dev.pkg"
PKG_VERSION="${SCRIPT_VERSION}"
INSTALL_ROOT="/usr/local/share/macos-netskope-dev"
STAGING="$DIST_DIR/pkg-staging"
ARCHIVE_PATH=""
PKG_PATH=""

usage() {
    cat <<EOF
Usage: $(basename "$0")

1. Exécute scripts/build-release.sh si nécessaire
2. Crée dist/macos-netskope-dev-\${VERSION}.pkg

Le pkg installe les fichiers dans ${INSTALL_ROOT}.

EOF
}

require_commands pkgbuild tar shasum

main() {
    local tmp_dir version_file version_dir

    ARCHIVE_PATH="$DIST_DIR/mnd-${SCRIPT_VERSION}.tar.gz"

    if [[ ! -f "$ARCHIVE_PATH" ]]; then
        "$SCRIPT_DIR/scripts/build-release.sh"
    fi

    rm -rf "$STAGING"
    mkdir -p "$STAGING/usr/local/share"
    local tmp_extract
    tmp_extract="$(mktemp -d "${TMPDIR:-/tmp}/mnd-pkg.XXXXXX")"
    tar -xzf "$ARCHIVE_PATH" -C "$tmp_extract"
    version_dir="$(find "$tmp_extract" -maxdepth 1 -name 'mnd-*' -type d | head -1)"
    cp -R "$version_dir/." "$STAGING/usr/local/share/macos-netskope-dev/"
    rm -rf "$tmp_extract"

    PKG_PATH="$DIST_DIR/macos-netskope-dev-${SCRIPT_VERSION}.pkg"
    pkgbuild \
        --root "$STAGING" \
        --identifier "$PKG_ID" \
        --version "$PKG_VERSION" \
        --install-location "/" \
        "$PKG_PATH"

    rm -rf "$STAGING"

    echo "Package : $PKG_PATH"
    echo "Archive : $ARCHIVE_PATH"
}

main "$@"
