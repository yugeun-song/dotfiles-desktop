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

# The selection overlay, in the desktop's own colours. Overridable so a screen
# recording or a light background can be handled without editing this file.
#
# slurp's dimensions readout takes the border colour and a font size of 14 that
# is compiled into render.c, so the size cannot be set from here at all.
SLURP_FONT="${SLURP_FONT:-CaskaydiaCove Nerd Font}"
SLURP_BORDER="${SLURP_BORDER:-#ECF0C1ff}"   # foreground, and the readout
SLURP_FILL="${SLURP_FILL:-#7AA2F733}"       # accent at low alpha, inside the box
SLURP_DIM="${SLURP_DIM:-#0F111B99}"         # background at high alpha, outside it

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

# A capture that produced nothing, or produced something that is not an image,
# is a failure even when grim said otherwise.
# Cut the chosen region out of a frame that was captured earlier.
#
# slurp speaks logical coordinates and grim writes physical pixels. They are the
# same number only while every output is at scale 1. Rather than assume that,
# the ratio is measured: the width of the frame that came back over the width of
# the logical layout the compositor reports. On this machine that is 1 and the
# arithmetic is a no-op; on a scaled output it is what stops the crop landing in
# the wrong place.
crop_from_frame() {
    local frame="$1" geom="$2" out="$3"
    local x y w h ratio lw

    # slurp prints "<x>,<y> <w>x<h>"
    x="${geom%%,*}"
    y="${geom#*,}"; y="${y%% *}"
    w="${geom##* }"; w="${w%%x*}"
    h="${geom##*x}"

    [[ "$x$y$w$h" =~ ^[0-9-]+$ ]] || die "could not read the selection: $geom"

    # The logical width of everything, from the compositor rather than guessed.
    lw=$(hyprctl -j monitors 2>/dev/null \
         | jq -r '[.[] | (.x + (.width / .scale))] | max // empty') || lw=""
    if [[ -n "$lw" && "$lw" != "null" ]]; then
        ratio=$(magick identify -format '%w' "$frame" 2>/dev/null \
                | awk -v l="$lw" '{ printf "%.6f", (l > 0 ? $1 / l : 1) }')
    else
        ratio=1
    fi

    # Scaled, then rounded outward, so a half pixel never trims the edge off
    # what was asked for.
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
    verify_image "$FILE"
        finish "$FILE"
        ;;

    region|region-edit)
        need grim slurp magick
        selection_running && die "a selection is already in progress"
        # -c sets the border AND the dimensions text: render.c draws the
        # "1920x1080" readout with the border colour and a font size of 14 that
        # is compiled in, so the colour is the only half of its appearance that
        # can be chosen from here. #ECF0C1 is the desktop foreground, which is
        # the lightest thing in the palette and the one that stays readable over
        # whatever happens to be on screen behind the selection.
        #
        # -b dims everything outside the selection rather than leaving it at
        # slurp's default, so the rectangle reads as the subject.
        #
        # The screen is photographed BEFORE slurp draws anything. slurp exits
        # once it has printed the geometry, but exiting is not the compositor
        # having destroyed its surface and repainted underneath, and grim reads
        # through wlr-screencopy: read in that window and the shot contains
        # slurp's own rectangle, a border just inside the region over a
        # translucent fill. Every region capture taken here has one; it went
        # unnoticed only because the border was drawn in a dark colour on a dark
        # desktop. Waiting for the overlay to go is a guess about how long a
        # frame takes. Taking the picture first is not: the overlay cannot
        # appear in an image that was captured before it existed.
        #
        # It also freezes the screen for the duration of the drag, so an
        # animation no longer moves between choosing the region and getting it.
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
        # grim can exit 0 and leave nothing behind: two zero-byte files are in
        # the screenshots directory from exactly that. A file that is not a PNG
        # is not a screenshot, and finding out here is better than finding out
        # when it is opened.
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
