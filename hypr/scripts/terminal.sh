#!/usr/bin/env bash
#
# Launches the first terminal emulator that is actually installed.
#
# The order is a preference, not a survey: kitty first because the shell
# configuration in dotfiles-terminal is written for it, then the rest in
# rough order of how likely they are to behave the same way. A machine that
# has none of them still gets a clear message instead of a keybind that
# silently does nothing.
#
#   terminal.sh              open a shell
#   terminal.sh -e cmd ...   run a command in a terminal
#
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
        # gnome-terminal and tilix want -- rather than -e for the command.
        gnome-terminal|tilix) exec "$term" -- "$@" ;;
        *)                    exec "$term" -e "$@" ;;
    esac
fi

exec "$term"
