#!/usr/bin/env bash
# Writes the config lock.sh locks with and prints its path: every widget block
# of hyprlock.conf once per output, its lengths scaled to that output and its
# text coloured against that output's wallpaper (lock-colours.py).
#
# The sizes keep, on every screen, the proportions the user chose on the
# 2880x1800 panel (2026-10-24; $fit_reference and $fit_scale in
# hyprlock.conf), as shares of the screen rather than as pixels: text and
# heights take the panel's share of the screen's height, widths and sideways
# offsets its share of the width. A 16:9 screen thus gets the panel's layout
# spread wider, not taller shapes. A screen narrower than the panel's 16:10
# scales by its width alone, and one wider stretches the shapes by at most
# STRETCH_MAX, so an ultrawide gets no banners. A block with a "fit: even"
# comment line is never stretched, its widths and offsets scaled as its
# heights: the card keeps the bar's grown island's proportions, and its
# controls stay over it. Counted in the pixels hyprlock draws, since it
# ignores the compositor scale. This is not the bar's factor (Theme.fit,
# floored at 1): at that floor the 2560x1440 desk monitor drew the shapes
# the user found too large.
#
# Every output Hyprland knows and every other connector of the GPU gets a
# copy, so a screen plugged in while locked still shows the time and the
# field; one with no known mode gets the sizes as written. A block that names
# its monitor was sized for that screen and is copied as written. Fails,
# printing no path, when hyprlock.conf declares no $fit_reference or Hyprland
# does not answer; lock.sh then locks on hyprlock.conf as written.
#
# Usage: lock-fit.sh [config] [output]

set -uo pipefail

HERE=$(dirname -- "${BASH_SOURCE[0]}")
CONF="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprlock.conf}"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
OUT="${2:-$RT/hyprlock-fit.conf}"

STRETCH_MAX=1.25

fail() { printf 'lock-fit: %s\n' "$*" >&2; exit 1; }

[[ -r "$CONF" ]] || fail "cannot read $CONF"

ref="" scale=1
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*\$fit_reference[[:space:]]*=[[:space:]]*([0-9]+)x([0-9]+) ]]; then
        ref="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    elif [[ $line =~ ^[[:space:]]*\$fit_scale[[:space:]]*=[[:space:]]*([0-9]+(\.[0-9]+)?)[[:space:]]*$ ]]; then
        scale=${BASH_REMATCH[1]}
    fi
done <"$CONF"
[[ -n "$ref" ]] || fail "$CONF declares no \$fit_reference, so it runs as written"

# A disabled output (the panel under a shut lid) by its first, preferred mode.
outputs=$(timeout 2 hyprctl -j monitors all 2>/dev/null | jq -r '
    .[] | [.name,
           (if (.disabled | not) and .width > 0 and .height > 0 then "\(.width) \(.height)"
            else (((.availableModes[0] // "") | capture("^(?<w>[0-9]+)x(?<h>[0-9]+)") | "\(.w) \(.h)") // "0 0")
            end)] | join(" ")' 2>/dev/null)
[[ -n "$outputs" ]] || fail "Hyprland lists no output"

for c in /sys/class/drm/card*-*; do
    [[ -e "$c" ]] || continue
    c=${c##*/}
    outputs+=$'\n'"${c#*-} 0 0"
done

read -r -d '' PROGRAM <<'AWK'
function round(v) { return v < 0 ? -int(-v + 0.5) : int(v + 0.5) }

# The line without its comment; "##" is hyprlang's escaped "#".
function bare(line,    s) {
    s = line
    gsub(/##/, "\001", s)
    sub(/#.*/, "", s)
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    return s
}

function keyof(s,    e, k) {
    e = index(s, "=")
    if (e == 0)
        return ""
    k = substr(s, 1, e - 1)
    gsub(/[ \t]+$/, "", k)
    return k
}

function valof(s,    v) {
    v = substr(s, index(s, "=") + 1)
    gsub(/^[ \t]+|[ \t]+$/, "", v)
    return v
}

function opens(s) { return index(s, "=") == 0 && s ~ /\{$/ }

# A positive length never rounds away; -1 rounding means "as round as fits".
# The first of a position's or a size's two numbers is a width.
function scaled(key, v, f, fw,    n, i, p, r, g, out) {
    n = split(v, p, ",")
    out = ""
    for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", p[i])
        g = (i == 1 && n == 2 && (key == "position" || key == "size")) ? fw : f
        if (p[i] ~ /^-?[0-9]+(\.[0-9]+)?(px)?$/ && !(key ~ /rounding$/ && p[i] + 0 < 0)) {
            r = round((p[i] + 0) * g)
            p[i] = (p[i] + 0 > 0 && r < 1) ? 1 : r
        }
        out = out (i > 1 ? ", " : "") p[i]
    }
    return out
}

function emit(    j, k, key, pinned, named, even, indent) {
    for (j = 2; j < nb; j++) {
        if (keyof(bare_[j]) == "monitor") {
            named = 1
            if (valof(bare_[j]) != "")
                pinned = 1
        }
        if (block[j] ~ /^[ \t]*#[ \t]*fit:[ \t]*even[ \t]*$/)
            even = 1
    }
    if (pinned) {
        for (j = 1; j <= nb; j++)
            print block[j]
        return
    }
    for (k = 1; k <= count; k++) {
        if (k > 1)
            print ""
        print block[1]
        if (!named)
            printf "    monitor = %s\n", names[k]
        for (j = 2; j <= nb; j++) {
            key = keyof(bare_[j])
            match(block[j], /^[ \t]*/)
            indent = substr(block[j], 1, RLENGTH)
            if (key == "monitor")
                printf "%smonitor = %s\n", indent, names[k]
            else if (key in length_key)
                printf "%s%s = %s\n", indent, key, scaled(key, valof(bare_[j]), fits[k], even ? fits[k] : wides[k])
            else
                print block[j]
        }
    }
}

BEGIN {
    split(ENVIRON["FIT_REF"], r, " ")
    scale = ENVIRON["FIT_SCALE"] + 0
    smax = ENVIRON["FIT_STRETCH_MAX"] + 0
    n = split(ENVIRON["FIT_OUTPUTS"], rows, "\n")
    for (i = 1; i <= n; i++) {
        if (split(rows[i], o, " ") != 3 || (o[1] in seen))
            continue
        seen[o[1]] = 1
        names[++count] = o[1]
        if (o[2] > 0 && o[3] > 0) {
            fx = o[2] / r[1]
            fy = o[3] / r[2]
            u = (fx < fy ? fx : fy) * scale
            st = fx / fy
            st = st < 1 ? 1 : (st > smax ? smax : st)
            modes[count] = o[2] "x" o[3]
        } else {
            u = 1
            st = 1
            modes[count] = "no mode"
        }
        fits[count] = u
        wides[count] = u * st
    }
    split("background label input-field shape image", t, " ")
    for (i in t)
        widget[t[i]] = 1
    split("font_size position size outline_thickness border_size rounding dots_rounding blur_size shadow_size", t, " ")
    for (i in t)
        length_key[t[i]] = 1

    # lock-colours.py reads each output's size and factors from these lines.
    printf "# Written by lock-fit.sh from %s at every lock; edit that file instead.\n", ENVIRON["FIT_CONF"]
    for (i = 1; i <= count; i++)
        printf "# %s %s fit %.3f wide %.3f\n", names[i], modes[i], fits[i], wides[i]
    print ""
}

{ s = bare($0) }

!inwidget {
    if (depth == 0 && opens(s)) {
        type = s
        sub(/[ \t]*\{$/, "", type)
        if (type in widget) {
            inwidget = 1
            inner = 1
            nb = 0
            block[++nb] = $0
            bare_[nb] = s
            next
        }
    }
    if (opens(s))
        depth++
    else if (s == "}" && depth > 0)
        depth--
    print
    next
}

{
    block[++nb] = $0
    bare_[nb] = s
    if (opens(s))
        inner++
    else if (s == "}")
        inner--
    if (inner == 0) {
        emit()
        inwidget = 0
    }
}
AWK

# Renamed into place: a second lock started meanwhile reads a whole file.
tmp=$(mktemp "$OUT.XXXXXX") || fail "cannot write beside $OUT"
if ! FIT_CONF="$CONF" FIT_REF="$ref" FIT_SCALE="$scale" FIT_STRETCH_MAX="$STRETCH_MAX" FIT_OUTPUTS="$outputs" \
    awk "$PROGRAM" "$CONF" >"$tmp" || [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    fail "could not write $OUT"
fi

# The colours, per screen. Without them the copy keeps hyprlock.conf's own,
# the beige. Bounded, since the lock waits on it.
if FIT_INK_CACHE="${OUT%.conf}.ink" timeout 3 python3 "$HERE/lock-colours.py" "$tmp" >"$tmp.ink" \
    && [[ -s "$tmp.ink" ]]; then
    mv -f "$tmp.ink" "$tmp"
fi
rm -f "$tmp.ink"

if mv -f "$tmp" "$OUT"; then
    printf '%s\n' "$OUT"
else
    rm -f "$tmp"
    fail "could not write $OUT"
fi
