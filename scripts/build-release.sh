#!/usr/bin/env bash
#
# Construit une archive versionnée pour déploiement Intune / MDM.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DIST_DIR="$SCRIPT_DIR/dist"
ARCHIVE_NAME="gct-${SCRIPT_VERSION}"
STAGING_DIR="$DIST_DIR/$ARCHIVE_NAME"

usage() {
    cat <<EOF
Usage: $(basename "$0")

Crée dist/${ARCHIVE_NAME}.tar.gz et dist/${ARCHIVE_NAME}.tar.gz.sha256

EOF
}

require_commands tar shasum

clean_staging() {
    rm -rf "$STAGING_DIR"
}

copy_tree() {
    mkdir -p "$STAGING_DIR"

    cp "$SCRIPT_DIR/install.sh" "$STAGING_DIR/"
    cp "$SCRIPT_DIR/LICENSE" "$STAGING_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/CHANGELOG.md" "$STAGING_DIR/" 2>/dev/null || true

    cp -R "$SCRIPT_DIR/lib" "$STAGING_DIR/"
    cp -R "$SCRIPT_DIR/docs" "$STAGING_DIR/"
    cp -R "$SCRIPT_DIR/scripts" "$STAGING_DIR/"

    chmod +x "$STAGING_DIR/install.sh"
    chmod +x "$STAGING_DIR/scripts/"*.sh
}

write_version_file() {
    cat > "$STAGING_DIR/VERSION" <<EOF
${SCRIPT_VERSION}
EOF
}

main() {
    local archive_path checksum_path

    usage >/dev/null 2>&1 || true

    mkdir -p "$DIST_DIR"
    clean_staging
    copy_tree
    write_version_file

    archive_path="$DIST_DIR/${ARCHIVE_NAME}.tar.gz"
    checksum_path="$archive_path.sha256"

    tar -C "$DIST_DIR" -czf "$archive_path" "$ARCHIVE_NAME"
    shasum -a 256 "$archive_path" | awk '{print $1 "  '"$(basename "$archive_path")"'"}' > "$checksum_path"

    clean_staging

    echo "Archive  : $archive_path"
    echo "Checksum : $checksum_path"
    echo
    cat "$checksum_path"
}

main "$@"
