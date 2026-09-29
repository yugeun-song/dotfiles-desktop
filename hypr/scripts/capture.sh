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
# Every shot goes to both clipboard and file, under a name no other shot has.
#
# One overlay at a time: two overlays both grab the pointer and the desktop
# looks frozen. The overlay modes take a lock (flock, non-blocking) before
# anything else, so a key pressed again while a capture prepares or waits for
# the drag does nothing. The lock ends when the overlay closes, and nothing
# that outlives the script may inherit it: a resident wl-copy that inherited
# it kept every later press out until another program took the clipboard.
# Hyprland sends this script's stdout and stderr to /dev/null, so every
# failure is also a notification.
# ============================================================================

set -uo pipefail

# Overlay colours, overridable from the environment. slurp draws its size
# readout in the border colour at a font size compiled into render.c.
SLURP_FONT="${SLURP_FONT:-CaskaydiaCove Nerd Font}"
SLURP_BORDER="${SLURP_BORDER:-#ECF0C1ff}"   # foreground, and the readout
SLURP_FILL="${SLURP_FILL:-#7AA2F733}"       # accent at low alpha, inside the box
SLURP_DIM="${SLURP_DIM:-#0F111B99}"         # background at high alpha, outside it

# Every step that runs under the lock has a deadline, so no hang keeps later
# presses out for good. grim waits for the compositor to draw a frame; an
# overlay nobody finishes closes after two minutes.
GRAB_TIMEOUT=5
OVERLAY_TIMEOUT=120

MODE="${1:-region}"
DEST="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
printf -v STAMP '%(%Y-%m-%d_%H.%M.%S)T' -1
# The frames are whole screens: kept private and in RAM.
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    RUN="$XDG_RUNTIME_DIR/capture"
else
    RUN="/tmp/capture-$UID"
fi
LOCKED=0
PART=""
OUT=""

# Anything that may outlive the script starts here: detached, and with fd 9
# (the lock) closed. $1 is its stdin.
spawn() {
    local input="$1"
    shift
    "$@" <"$input" >/dev/null 2>&1 9>&- &
    disown 2>/dev/null || true
}

# Time-limited: notify-send blocks forever without a notification server.
notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    spawn /dev/null timeout 2 notify-send "$@"
}

die() {
    release_lock
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

take_lock() {
    exec 9>"$RUN/lock" || die "cannot open $RUN/lock"
    # Silent: a press while a capture is on screen, or about to be, is a
    # repeat and not an error.
    if ! flock -n 9; then
        echo "capture: a capture is already in progress" >&2
        exit 0
    fi
    LOCKED=1
}

# Unlocked explicitly rather than by closing the fd: a copy of it left in any
# child would otherwise keep the lock.
release_lock() {
    (( LOCKED )) || return 0
    flock -u 9 2>/dev/null
    exec 9>&-
    LOCKED=0
}

cleanup() {
    [[ -n "$PART" ]] && rm -f -- "$PART"
    rm -f -- "$RUN"/*."$$".* 2>/dev/null
}
trap cleanup EXIT

# Files of runs killed before their trap could run. The pid in the name says
# whose they are; a live run's files are left alone.
sweep() {
    local f
    for f in "$RUN"/*.*.* "$DEST"/.Screenshot.*.png; do
        [[ -e "$f" && "${f##*/}" =~ \.([0-9]+)\. ]] || continue
        kill -0 "${BASH_REMATCH[1]}" 2>/dev/null || rm -f -- "$f"
    done
}

# grim can exit 0 and write an empty file.
is_png() {
    [[ -s "$1" && "$(od -An -tx1 -N8 -- "$1" 2>/dev/null | tr -d ' \n')" == 89504e470d0a1a0a ]]
}

# Written under a hidden name, then linked into place: a file manager or sync
# client never sees half a PNG, and two shots in the same second never
# overwrite each other.
begin_shot() {
    PART="$DEST/.Screenshot.$$.png"
    rm -f -- "$PART"
}

publish() {
    local base="$DEST/Screenshot_$STAMP" dst n=1
    is_png "$PART" || die "the capture produced no PNG"
    dst="$base.png"
    until ln -T -- "$PART" "$dst" 2>/dev/null; do
        [[ -e "$dst" || -L "$dst" ]] || die "cannot save into $DEST"
        (( ++n < 100 )) || die "too many shots named Screenshot_$STAMP"
        dst="${base}_$n.png"
    done
    rm -f -- "$PART"
    PART=""
    OUT="$dst"
}

finish() {
    # wl-copy stays resident as the clipboard owner.
    command -v wl-copy >/dev/null 2>&1 && spawn "$OUT" wl-copy --type image/png
    echo "$OUT"
    notify "Screenshot" "${OUT/#$HOME/~}"
}

# Every output at its own density, before the overlay exists: a frame taken
# after it races the overlay's removal and can contain it. One grim per
# output, run together, instead of one for the whole layout, which is drawn
# at the highest scale: that enlarged and blurred the lower-scale outputs and
# took longer (70 ms against 40 ms on two screens).
grab_frames() {
    local i name x y scale busy=0 pids=() failed=()
    NAMES=() XS=() YS=() SCALES=() FWS=() FHS=()
    while read -r name x y scale; do
        NAMES+=("$name") XS+=("$x") YS+=("$y") SCALES+=("$scale")
    done < <(timeout "$GRAB_TIMEOUT" hyprctl -j monitors 2>/dev/null | jq -r \
        '.[] | select(.disabled != true and (.mirrorOf // "none") == "none")
             | "\(.name) \(.x) \(.y) \(.scale)"' 2>/dev/null)
    (( ${#NAMES[@]} )) || die "hyprctl listed no outputs"

    for i in "${!NAMES[@]}"; do
        timeout "$GRAB_TIMEOUT" grim -t ppm -o "${NAMES[i]}" "$RUN/frame.$$.$i.ppm" \
            </dev/null >/dev/null 2>&1 &
        pids+=("$!")
    done
    # Another program's slurp or hyprpicker would fight ours for the
    # pointer. Checked while grim runs, so it costs no time.
    pgrep -u "$UID" -x 'slurp|hyprpicker' >/dev/null 2>&1 && busy=1
    for i in "${!pids[@]}"; do
        wait "${pids[i]}" || failed+=("${NAMES[i]}")
    done
    (( busy )) && die "another selection is already open"
    (( ${#failed[@]} )) && die "grim could not capture ${failed[*]}"

    # grim writes "P6\n<w> <h>\n255\n". The size is of the frame as shown,
    # rotation included.
    local magic w h
    for i in "${!NAMES[@]}"; do
        magic="" w="" h=""
        { read -r magic && read -r w h; } 2>/dev/null <"$RUN/frame.$$.$i.ppm"
        [[ "$magic" == P6 && "$w" =~ ^[1-9][0-9]*$ && "$h" =~ ^[1-9][0-9]*$ ]] \
            || die "grim wrote a bad frame for ${NAMES[i]}"
        FWS+=("$w") FHS+=("$h")
    done
}

# Returns 1 when there is nothing to capture: cancelled with Esc, a click
# without a drag, or the overlay closed from outside.
select_region() {
    local err="$RUN/slurp.$$.err" rc
    # stdin is /dev/null: slurp reads predefined boxes from a stdin that is
    # not a terminal, and would wait on an open pipe before showing anything.
    SEL=$(timeout -k 2 "$OVERLAY_TIMEOUT" slurp -d -f '%x %y %w %h' \
        -F "$SLURP_FONT" \
        -c "$SLURP_BORDER" \
        -s "$SLURP_FILL" \
        -b "$SLURP_DIM" \
        -w 2 \
        </dev/null 2>"$err")
    rc=$?
    release_lock
    case "$rc" in
        0) ;;
        124)
            notify "Screenshot cancelled" "No selection within $OVERLAY_TIMEOUT seconds"
            return 1
            ;;
        *)
            # slurp says "selection cancelled" for Esc and also when the
            # compositor connection drops; either way there is no shot.
            grep -q 'selection cancelled' "$err" 2>/dev/null && return 1
            (( rc >= 128 )) && return 1
            die "slurp failed: $(head -n 1 "$err" 2>/dev/null)"
            ;;
    esac
    SX="" SY="" SW="" SH=""
    read -r SX SY SW SH <<<"$SEL"
    [[ "$SX" =~ ^-?[0-9]+$ && "$SY" =~ ^-?[0-9]+$ && "$SW" =~ ^[0-9]+$ && "$SH" =~ ^[0-9]+$ ]] \
        || die "could not read the selection: $SEL"
    (( SW >= 2 && SH >= 2 ))
}

# slurp gives logical coordinates; each frame is in its output's physical
# pixels. A selection inside one output is cut from that frame as it is. One
# spanning outputs is assembled at the highest density among them, like grim
# does, with black where no output lies.
cut_selection() {
    local i plan args=()
    plan=$(for i in "${!NAMES[@]}"; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$RUN/frame.$$.$i.ppm" \
            "${XS[i]}" "${YS[i]}" "${SCALES[i]}" "${FWS[i]}" "${FHS[i]}"
    done | awk -v sx="$SX" -v sy="$SY" -v sw="$SW" -v sh="$SH" '
        function floor(v) { return (v >= 0 || v == int(v)) ? int(v) : int(v) - 1 }
        function ceil(v)  { return (v <= 0 || v == int(v)) ? int(v) : int(v) + 1 }
        function round(v) { return floor(v + 0.5) }
        function max(a, b) { return a > b ? a : b }
        function min(a, b) { return a < b ? a : b }
        # Rounded outward, so a fraction of a pixel never trims the shot.
        function crop(i,   px0, py0, px1, py1) {
            px0 = max(0, floor((ix0[i] - ox[i]) * r[i] + 1e-6))
            py0 = max(0, floor((iy0[i] - oy[i]) * r[i] + 1e-6))
            px1 = min(fw[i], ceil((ix1[i] - ox[i]) * r[i] - 1e-6))
            py1 = min(fh[i], ceil((iy1[i] - oy[i]) * r[i] - 1e-6))
            cw = px1 - px0; ch = py1 - py0
            return cw "x" ch "+" px0 "+" py0
        }
        BEGIN { FS = "\t" }
        {
            n++; f[n] = $1; ox[n] = $2; oy[n] = $3; fw[n] = $5; fh[n] = $6
            ow[n] = round($5 / $4); oh[n] = round($6 / $4)
            r[n] = $5 / ow[n]
        }
        END {
            for (i = 1; i <= n; i++) {
                x0 = max(sx, ox[i]); y0 = max(sy, oy[i])
                x1 = min(sx + sw, ox[i] + ow[i]); y1 = min(sy + sh, oy[i] + oh[i])
                if (x1 <= x0 || y1 <= y0) continue
                hit[++hits] = i
                ix0[i] = x0; iy0[i] = y0; ix1[i] = x1; iy1[i] = y1
                if (r[i] > R) R = r[i]
            }
            if (!hits) exit 3
            i = hit[1]
            if (hits == 1 && ix0[i] == sx && iy0[i] == sy && ix1[i] == sx + sw && iy1[i] == sy + sh) {
                print f[i]; print "-crop"; print crop(i); print "+repage"
                exit 0
            }
            print "-size"; print round(sw * R) "x" round(sh * R); print "xc:black"
            for (k = 1; k <= hits; k++) {
                i = hit[k]
                tx0 = round((ix0[i] - sx) * R); ty0 = round((iy0[i] - sy) * R)
                tw = round((ix1[i] - sx) * R) - tx0; th = round((iy1[i] - sy) * R) - ty0
                c = crop(i)
                print "("; print f[i]; print "-crop"; print c; print "+repage"
                if (cw != tw || ch != th) { print "-resize"; print tw "x" th "!" }
                print ")"; print "-geometry"; print "+" tx0 "+" ty0; print "-composite"
            }
        }')
    case $? in
        0) ;;
        3) die "the selection lies on no captured output" ;;
        *) die "could not plan the crop" ;;
    esac
    mapfile -t args <<<"$plan"
    begin_shot
    timeout 30 magick "${args[@]}" "png:$PART" 2>/dev/null \
        || die "could not cut the selection out of the frames"
}

case "$MODE" in
    screen|region|region-edit|window|color) ;;
    *)
        sed -n '4,10p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'
        exit 2
        ;;
esac

[[ -d "$RUN" ]] || mkdir -m 700 "$RUN" 2>/dev/null
[[ -d "$RUN" && -O "$RUN" && ! -L "$RUN" ]] || die "cannot use $RUN"
mkdir -p "$DEST" || die "cannot create $DEST"
sweep

case "$MODE" in
    screen)
        need grim hyprctl jq
        out=$(timeout "$GRAB_TIMEOUT" hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty' 2>/dev/null)
        [[ -n "$out" ]] || die "could not determine the focused monitor"
        begin_shot
        timeout "$GRAB_TIMEOUT" grim -o "$out" "$PART" </dev/null >/dev/null 2>&1 \
            || die "grim could not capture $out"
        publish
        finish
        ;;

    region|region-edit)
        need grim slurp magick hyprctl jq
        [[ "$MODE" == region-edit ]] && need swappy
        take_lock
        grab_frames
        select_region || exit 0
        cut_selection
        publish
        [[ "$MODE" == region-edit ]] && spawn /dev/null swappy -f "$OUT"
        finish
        ;;

    window)
        need grim hyprctl jq
        geom=$(timeout "$GRAB_TIMEOUT" hyprctl activewindow -j 2>/dev/null \
            | jq -r 'select(.at and .size) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)
        [[ "$geom" =~ ^-?[0-9]+,-?[0-9]+\ [0-9]+x[0-9]+$ ]] || die "no focused window"
        begin_shot
        timeout "$GRAB_TIMEOUT" grim -g "$geom" "$PART" </dev/null >/dev/null 2>&1 \
            || die "grim could not capture the window"
        publish
        finish
        ;;

    color)
        need hyprpicker wl-copy
        take_lock
        pgrep -u "$UID" -x 'slurp|hyprpicker' >/dev/null 2>&1 && die "another selection is already open"
        # No -a: hyprpicker's own wl-copy would inherit the lock, and this
        # script copies anyway.
        hex=$(timeout -k 2 "$OVERLAY_TIMEOUT" hyprpicker -n </dev/null 2>/dev/null)
        rc=$?
        release_lock
        case "$rc" in
            0) ;;
            2) exit 0 ;;   # Esc
            124)
                notify "Colour pick cancelled" "No pick within $OVERLAY_TIMEOUT seconds"
                exit 0
                ;;
            *)
                (( rc >= 128 )) && exit 0
                die "hyprpicker failed (exit $rc)"
                ;;
        esac
        [[ -n "$hex" ]] || exit 0
        spawn /dev/null wl-copy -- "$hex"
        echo "$hex"
        notify "Colour picked" "$hex"
        ;;
esac
