#!/usr/bin/env bash
# ============================================================================
# capture.sh - screenshots and colour picking
#
#   capture.sh screen        the focused monitor
#   capture.sh region        drag a rectangle
#   capture.sh window        the focused window
#   capture.sh region-edit   drag a rectangle, then open swappy to annotate
#   capture.sh color         pick a colour, hex on the clipboard
#
# Every shot goes to the clipboard and to a file, because which one you wanted
# is only obvious afterwards.
#
# Two guards that matter more than they look:
#
#   one selection at a time   slurp draws a fullscreen overlay that grabs the
#                             pointer. Starting a second leaves both waiting
#                             for a drag that can only reach one of them, and
#                             the desktop appears frozen.
#
#   tools checked up front    a missing grim means an empty file and a silent
#                             clipboard, which looks exactly like a shot of a
#                             black screen.
# ============================================================================

set -uo pipefail

MODE="${1:-region}"
DEST="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
STAMP="$(date '+%Y-%m-%d_%H.%M.%S')"
FILE="$DEST/Screenshot_$STAMP.png"

# notify-send blocks on a D-Bus reply. When no notification server owns
# org.freedesktop.Notifications it waits forever, and the screenshot waits
# with it. Detached and time limited, so a missing server costs nothing.
notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    ( timeout 2 notify-send "$@" >/dev/null 2>&1 & ) 2>/dev/null
    return 0
}

die() {
    echo "capture: $*" >&2
    notify -u critical "Screenshot failed" "$*"
    exit 1
}

need() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "$c is not installed"
    done
}

selection_running() {
    pgrep -x slurp >/dev/null 2>&1 || pgrep -x hyprpicker >/dev/null 2>&1
}

finish() {
    local f="$1"
    [[ -s "$f" ]] || die "produced an empty file"
    if command -v wl-copy >/dev/null 2>&1; then
        # wl-copy stays resident as the clipboard owner and inherits stdio.
        # Left attached it holds the pipe open, so anything reading this
        # script's output waits for the clipboard to be replaced, which
        # looks exactly like a hung screenshot.
        wl-copy --type image/png < "$f" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
    echo "$f"
    notify "Screenshot" "${f/#$HOME/~}"
}

mkdir -p "$DEST" || die "cannot create $DEST"

case "$MODE" in
    screen)
        need grim hyprctl jq
        out=$(hyprctl activeworkspace -j | jq -r '.monitor')
        [[ -n "$out" && "$out" != "null" ]] || die "could not determine the focused monitor"
        grim -o "$out" "$FILE" || die "grim failed"
        finish "$FILE"
        ;;

    region|region-edit)
        need grim slurp
        selection_running && die "a selection is already in progress"
        geom=$(slurp -d 2>/dev/null) || exit 0     # cancelled with Esc, not an error
        [[ -n "$geom" ]] || exit 0
        grim -g "$geom" "$FILE" || die "grim failed"
        if [[ "$MODE" == "region-edit" ]]; then
            need swappy
            swappy -f "$FILE" &
        fi
        finish "$FILE"
        ;;

    window)
        need grim hyprctl jq
        geom=$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
        [[ "$geom" == *x* && "$geom" != *null* ]] || die "no focused window"
        grim -g "$geom" "$FILE" || die "grim failed"
        finish "$FILE"
        ;;

    color)
        need hyprpicker wl-copy
        selection_running && die "a picker is already open"
        hex=$(hyprpicker -a -n 2>/dev/null) || die "hyprpicker failed"
        [[ -n "$hex" ]] || exit 0
        printf '%s' "$hex" | ( wl-copy >/dev/null 2>&1 & )
        echo "$hex"
        notify "Colour picked" "$hex"
        ;;

    *)
        sed -n '4,10p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'
        exit 2
        ;;
esac
