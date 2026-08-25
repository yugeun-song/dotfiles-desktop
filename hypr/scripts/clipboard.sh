#!/usr/bin/env bash
#
# Picks an entry out of the clipboard history and puts it back on the
# clipboard.
#
# cliphist stores the history; it has no picker of its own. fuzzel is the
# nicer one when it is there, and a terminal running fzf works everywhere
# else, which matters because fuzzel arrives as somebody else's dependency
# and can leave the same way.
set -uo pipefail

if ! command -v cliphist >/dev/null 2>&1; then
    echo "clipboard.sh: cliphist is not installed" >&2
    exit 1
fi

if ! cliphist list 2>/dev/null | grep -q .; then
    command -v notify-send >/dev/null 2>&1 && \
        ( timeout 2 notify-send "Clipboard history" "nothing stored yet" >/dev/null 2>&1 & )
    exit 0
fi

if command -v fuzzel >/dev/null 2>&1; then
    cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy
    exit 0
fi

if command -v fzf >/dev/null 2>&1; then
    exec "$(dirname -- "${BASH_SOURCE[0]}")/terminal.sh" -e sh -c \
        'cliphist list | fzf --no-sort | cliphist decode | wl-copy'
fi

echo "clipboard.sh: no picker available (looked for fuzzel, fzf)" >&2
exit 1
