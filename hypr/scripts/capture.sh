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
# Lines 4-10 are the usage text printed by the `*)` case below.
# Every shot goes to both clipboard and file. Only one slurp/hyprpicker at a
# time: two overlays both grab the pointer and the desktop looks frozen.
# ============================================================================

set -uo pipefail

# Overlay colours, overridable from the environment. slurp draws its size
# readout in the border colour at a font size compiled into render.c.
SLURP_FONT="${SLURP_FONT:-CaskaydiaCove Nerd Font}"
SLURP_BORDER="${SLURP_BORDER:-#ECF0C1ff}"   # foreground, and the readout
SLURP_FILL="${SLURP_FILL:-#7AA2F733}"       # accent at low alpha, inside the box
SLURP_DIM="${SLURP_DIM:-#0F111B99}"         # background at high alpha, outside it

MODE="${1:-region}"
DEST="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
STAMP="$(date '+%Y-%m-%d_%H.%M.%S')"
FILE="$DEST/Screenshot_$STAMP.png"

# Detached and time-limited: notify-send blocks forever without a notification
# server.
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

# slurp gives logical coordinates, grim physical pixels. The ratio is measured
# (frame width / logical layout width) instead of assuming scale 1.
crop_from_frame() {
    local frame="$1" geom="$2" out="$3"
    local x y w h ratio lw

    # slurp prints "<x>,<y> <w>x<h>"
    x="${geom%%,*}"
    y="${geom#*,}"; y="${y%% *}"
    w="${geom##* }"; w="${w%%x*}"
    h="${geom##*x}"

    [[ "$x$y$w$h" =~ ^[0-9-]+$ ]] || die "could not read the selection: $geom"

    lw=$(hyprctl -j monitors 2>/dev/null \
         | jq -r '[.[] | (.x + (.width / .scale))] | max // empty') || lw=""
    if [[ -n "$lw" && "$lw" != "null" ]]; then
        ratio=$(magick identify -format '%w' "$frame" 2>/dev/null \
                | awk -v l="$lw" '{ printf "%.6f", (l > 0 ? $1 / l : 1) }')
    else
        ratio=1
    fi

    # Rounded outward so a half pixel never trims the selection.
    read -r x y w h < <(awk -v r="$ratio" -v x="$x" -v y="$y" -v w="$w" -v h="$h" \
        'BEGIN { printf "%d %d %d %d", int(x*r), int(y*r), int(w*r + 0.5), int(h*r + 0.5) }')

    magick "$frame" -crop "${w}x${h}+${x}+${y}" +repage "$out" \
        || die "could not cut the region out of the frame"
    verify_image "$out"
}

verify_image() {
    local f="$1"
    [[ -s "$f" ]] || { rm -f "$f"; die "grim wrote an empty file"; }
    magick identify -quiet "$f" >/dev/null 2>&1 \
        || file -b "$f" | grep -qi '^PNG image' \
        || { rm -f "$f"; die "grim wrote something that is not a PNG"; }
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
        # wl-copy stays resident as clipboard owner; with stdio attached it
        # holds this script's output pipe open and callers hang.
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
        verify_image "$FILE"
        finish "$FILE"
        ;;

    region|region-edit)
        need grim slurp magick
        selection_running && die "a selection is already in progress"
        # The frame is captured BEFORE slurp runs, then cropped. Capturing
        # after slurp exits races the compositor removing its overlay, and the
        # shot contains slurp's own rectangle.
        frame=$(mktemp --suffix=.png) || die "could not make a temporary file"
        trap 'rm -f "$frame"' EXIT
        grim "$frame" || die "grim failed"
        verify_image "$frame"

        geom=$(slurp -d \
            -F "$SLURP_FONT" \
            -c "$SLURP_BORDER" \
            -s "$SLURP_FILL" \
            -b "$SLURP_DIM" \
            -w 2 \
            2>/dev/null) || exit 0     # cancelled with Esc, not an error
        [[ -n "$geom" ]] || exit 0
        crop_from_frame "$frame" "$geom" "$FILE"
        # grim can exit 0 and write an empty file.
        verify_image "$FILE"
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
        verify_image "$FILE"
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
