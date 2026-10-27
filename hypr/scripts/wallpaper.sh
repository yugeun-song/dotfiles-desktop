#!/usr/bin/env bash
# Sets the wallpaper: one file, $DEST, read by hyprlock.conf directly and
# handed to hyprpaper over IPC (a path in hyprpaper.conf must exist at parse time).
# Non-PNG sources are converted so the .png name stays honest, and the file is
# stored no larger than the lit outputs need (see below).
#
# Usage
#   wallpaper.sh <image>    make <image> the wallpaper
#   wallpaper.sh --reload   re-apply the file already in place
#   wallpaper.sh --show     print the path and who reads it

set -euo pipefail

DEST="$HOME/Pictures/Wallpapers/current.png"

die() { printf 'wallpaper: %s\n' "$*" >&2; exit 1; }

# hyprpaper 0.8 re-reads the file on every wallpaper request; its IPC has no preload.
reload() {
    command -v hyprpaper >/dev/null 2>&1 || {
        printf 'wallpaper: hyprpaper is not installed, nothing is drawing the desktop\n' >&2
        return 0
    }
    pidof hyprpaper >/dev/null 2>&1 || {
        printf 'wallpaper: hyprpaper is not running, it will pick this up at next start\n' >&2
        return 0
    }
    # As ExecStartPost this races hyprpaper's IPC socket: wait up to 5 s, then
    # send anyway so the check below reports a slow start.
    for _ in $(seq 20); do
        hyprctl hyprpaper listactive >/dev/null 2>&1 && break
        sleep 0.25
    done
    hyprctl hyprpaper wallpaper ",$DEST" >/dev/null || die "hyprpaper would not set $DEST"

    # wallpaper answers an empty line either way; confirm via listactive.
    if ! hyprctl hyprpaper listactive 2>/dev/null | grep -qF "$DEST"; then
        die "hyprpaper accepted $DEST but is not showing it"
    fi
    printf 'wallpaper: %s\n' "$DEST"
}

case "${1-}" in
    --show)
        printf 'path      %s\n' "$DEST"
        [[ -f "$DEST" ]] && printf 'size      %s\n' "$(stat -c %s "$DEST") bytes" || printf 'size      missing\n'
        printf 'desktop   set over ipc by this script; hyprpaper.conf names no path\n'
        printf 'lock      hypr/hyprlock.conf names this path directly\n'
        exit 0
        ;;
    --reload)
        [[ -f "$DEST" ]] || die "$DEST does not exist yet"
        reload
        exit 0
        ;;
    "")
        die "usage: wallpaper.sh <image> | --reload | --show"
        ;;
esac

SRC="$1"
[[ -f "$SRC" ]] || die "no such file: $SRC"

mkdir -p -- "$(dirname -- "$DEST")"

# Atomic rename: hyprlock may read the file at any moment.
tmp="$DEST.new-$$"
trap 'rm -f -- "$tmp"' EXIT

mime="$(file -b --mime-type -- "$SRC")"
[[ "$mime" == image/* ]] || die "$SRC is not an image"

# Stored at the size that covers every lit output, rotation included, and
# never enlarged: hyprpaper keeps a texture of the whole image per output and
# hyprlock decodes and blurs the file at every lock, so a 6000x4000 photo held
# 92 MiB per screen and loading it peaked at 250 MB. A larger screen connected
# later shows an enlarged copy until the wallpaper is set again.
size="$(hyprctl -j monitors 2>/dev/null | jq -r '
    [.[] | select(.disabled != true)
         | if (.transform % 2) == 1 then [.height, .width] else [.width, .height] end]
    | if length == 0 then empty else "\(map(.[0]) | max)x\(map(.[1]) | max)" end' 2>/dev/null)" || size=""
fit=()
[[ "$size" =~ ^[0-9]+x[0-9]+$ ]] && fit=(-resize "${size}^>")

if command -v magick >/dev/null 2>&1; then
    magick "$SRC" -auto-orient "${fit[@]}" "png:$tmp"
elif command -v convert >/dev/null 2>&1; then
    convert "$SRC" -auto-orient "${fit[@]}" "png:$tmp"
elif [[ "$mime" == image/png ]]; then
    cp -- "$SRC" "$tmp"
else
    die "$SRC is not a png and imagemagick is not installed to convert it"
fi

chmod 644 -- "$tmp"
mv -T -- "$tmp" "$DEST"
trap - EXIT

reload
