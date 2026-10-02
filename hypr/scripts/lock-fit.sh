#!/usr/bin/env bash
# Writes the config lock.sh locks with and prints its path: every widget block
# of hyprlock.conf once per output, its lengths scaled by that output's fit, so
# the time and the field cover the share of each screen they cover on the
# reference output (see hyprlock.conf).
#
# fit is the number Theme.fit and config/monitors.lua use, the square root of
# the area over the reference's, kept between 1 and 2, but counted in the
# pixels hyprlock draws rather than in logical ones: hyprlock fills each
# output's own pixels and ignores the compositor scale. Counted so, the
# 2880x1800 panel gets 1.19 and the same share as the desk monitor; the bar,
# floored on the panel's 1920x1200 logical size, is drawn there at 1 times
# the 1.5 scale, a larger share. A screen with fewer pixels than the
# reference keeps the reference sizes, as in the bar: below them the
# smallest labels shrink past reading.
#
# Every output Hyprland knows and every other connector of the GPU gets a copy,
# so a screen plugged in while locked still shows the time and the field; one
# with no known mode gets the reference sizes. A block that names its monitor
# was sized for that screen and is copied as written. Fails, printing no path,
# when hyprlock.conf declares no $fit_reference or Hyprland does not answer;
# lock.sh then runs hyprlock on hyprlock.conf as written.
#
# Usage: lock-fit.sh [config] [output]

set -uo pipefail

CONF="${1:-$HOME/.config/hypr/hyprlock.conf}"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
OUT="${2:-$RT/hyprlock-fit.conf}"

# Theme.qml minFit/maxFit and config/monitors.lua FIT_MIN/FIT_MAX; keep in step.
FIT_MIN=1
FIT_MAX=2

fail() { printf 'lock-fit: %s\n' "$*" >&2; exit 1; }

[[ -r "$CONF" ]] || fail "cannot read $CONF"

ref=""
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*\$fit_reference[[:space:]]*=[[:space:]]*([0-9]+)x([0-9]+) ]]; then
        ref="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
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
function scaled(key, v, f,    n, i, p, r, out) {
    n = split(v, p, ",")
    out = ""
    for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", p[i])
        if (p[i] ~ /^-?[0-9]+(\.[0-9]+)?(px)?$/ && !(key ~ /rounding$/ && p[i] + 0 < 0)) {
            r = round((p[i] + 0) * f)
            p[i] = (p[i] + 0 > 0 && r < 1) ? 1 : r
        }
        out = out (i > 1 ? ", " : "") p[i]
    }
    return out
}

function emit(    j, k, key, pinned, named, indent) {
    for (j = 2; j < nb; j++)
        if (keyof(bare_[j]) == "monitor") {
            named = 1
            if (valof(bare_[j]) != "")
                pinned = 1
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
                printf "%s%s = %s\n", indent, key, scaled(key, valof(bare_[j]), fits[k])
            else
                print block[j]
        }
    }
}

BEGIN {
    split(ENVIRON["FIT_REF"], r, " ")
    refarea = r[1] * r[2]
    fmin = ENVIRON["FIT_MIN"] + 0
    fmax = ENVIRON["FIT_MAX"] + 0
    n = split(ENVIRON["FIT_OUTPUTS"], rows, "\n")
    for (i = 1; i <= n; i++) {
        if (split(rows[i], o, " ") != 3 || (o[1] in seen))
            continue
        seen[o[1]] = 1
        names[++count] = o[1]
        area = o[2] * o[3]
        f = area > 0 ? sqrt(area / refarea) : 1
        fits[count] = f < fmin ? fmin : (f > fmax ? fmax : f)
        modes[count] = area > 0 ? o[2] "x" o[3] : "no mode"
    }
    split("background label input-field shape image", t, " ")
    for (i in t)
        widget[t[i]] = 1
    split("font_size position size outline_thickness border_size rounding dots_rounding blur_size shadow_size", t, " ")
    for (i in t)
        length_key[t[i]] = 1

    printf "# Written by lock-fit.sh from %s at every lock; edit that file instead.\n", ENVIRON["FIT_CONF"]
    for (i = 1; i <= count; i++)
        printf "# %s %s fit %.3f\n", names[i], modes[i], fits[i]
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
if FIT_CONF="$CONF" FIT_REF="$ref" FIT_OUTPUTS="$outputs" FIT_MIN="$FIT_MIN" FIT_MAX="$FIT_MAX" \
    awk "$PROGRAM" "$CONF" >"$tmp" && [[ -s "$tmp" ]] && mv -f "$tmp" "$OUT"; then
    printf '%s\n' "$OUT"
else
    rm -f "$tmp"
    fail "could not write $OUT"
fi
