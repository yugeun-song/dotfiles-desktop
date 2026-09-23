#!/usr/bin/env bash
# Launches the first installed terminal, kitty first (dotfiles-terminal targets it).
#
#   terminal.sh              open a shell
#   terminal.sh -e cmd ...   run a command in a terminal
set -uo pipefail

TERMINALS=(
    kitty
    ghostty
    wezterm
    alacritty
    foot
    konsole
    gnome-terminal
    tilix
    terminator
    urxvt
    xterm
    st
)

pick() {
    local t
    for t in "${TERMINALS[@]}"; do
        command -v "$t" >/dev/null 2>&1 && { printf '%s' "$t"; return 0; }
    done
    return 1
}

term=$(pick) || {
    msg="no terminal emulator installed (looked for: ${TERMINALS[*]})"
    echo "$msg" >&2
    command -v notify-send >/dev/null 2>&1 && ( timeout 2 notify-send -u critical "No terminal" "$msg" & )
    exit 1
}

if [[ "${1:-}" == "-e" ]]; then
    shift
    case "$term" in
        # These take -- rather than -e.
        gnome-terminal|tilix) exec "$term" -- "$@" ;;
        *)                    exec "$term" -e "$@" ;;
    esac
fi

exec "$term"
