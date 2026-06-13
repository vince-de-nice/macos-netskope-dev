#!/usr/bin/env bash
# shellcheck shell=bash
#
# Exécution par un administrateur au nom d'un développeur (--as-user).

INSTALL_AS_USER=""
REMAINING_ARGS=()

preparse_as_user() {
    INSTALL_AS_USER=""
    REMAINING_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --as-user)
                INSTALL_AS_USER="${2:-}"
                [[ -n "$INSTALL_AS_USER" ]] ||
                    die "Option --as-user requiert le login macOS du développeur."
                shift 2
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

resolve_user_home() {
    local username="$1"
    local home=""

    if [[ "$EUID" -eq 0 ]]; then
        home="$(dscl . -read "/Users/$username" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    else
        home="$(eval echo "~$username" 2>/dev/null || true)"
    fi

    [[ -z "$home" ]] && home="/Users/$username"
    [[ -d "$home" ]] || return 1
    echo "$home"
}

maybe_reexec_as_user() {
    local target_home

    [[ -n "$INSTALL_AS_USER" ]] || return 0
    [[ "$(whoami)" == "$INSTALL_AS_USER" ]] && return 0

    target_home="$(resolve_user_home "$INSTALL_AS_USER")" ||
        die "Utilisateur introuvable ou répertoire home absent : $INSTALL_AS_USER"

    log "Exécution au nom de : $INSTALL_AS_USER (home: $target_home)"

    if [[ "$EUID" -eq 0 ]]; then
        exec sudo -u "$INSTALL_AS_USER" \
            env HOME="$target_home" USER="$INSTALL_AS_USER" LOGNAME="$INSTALL_AS_USER" \
            "$SCRIPT_DIR/install.sh" "${REMAINING_ARGS[@]}"
    fi

    exec sudo -u "$INSTALL_AS_USER" \
        env HOME="$target_home" USER="$INSTALL_AS_USER" LOGNAME="$INSTALL_AS_USER" \
        "$SCRIPT_DIR/install.sh" "${REMAINING_ARGS[@]}"
}

guard_root_install() {
    if [[ "$EUID" -eq 0 && -z "$INSTALL_AS_USER" ]]; then
        die "Installation en root interdite.

Ce script configure le compte utilisateur courant (~/.gradle, ~/.zshrc, git global, etc.).
Relancez de l'une des façons suivantes :

  • En tant que développeur (recommandé) :
      ./install.sh --all --netskope --yes

  • En tant qu'admin, pour un développeur :
      sudo ./install.sh --as-user <login> --all --netskope --yes

Voir docs/ADMIN.md pour le guide administrateur."
    fi
}
