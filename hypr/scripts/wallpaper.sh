#!/usr/bin/env bash
# Sets the wallpaper: one file, $DEST, read by hyprlock.conf directly and
# handed to hyprpaper over IPC (hyprpaper expands neither ~ nor $HOME).
# Non-PNG sources are converted so the .png name stays honest.
#
# Usage
#   wallpaper.sh <image>    make <image> the wallpaper
#   wallpaper.sh --reload   re-apply the file already in place
#   wallpaper.sh --show     print the path and who reads it

set -euo pipefail

DEST="$HOME/Pictures/Wallpapers/current.png"

die() { printf 'wallpaper: %s\n' "$*" >&2; exit 1; }

# hyprpaper caches by path, which never changes here, so unload before preload.
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
    # This hyprpaper build refuses unload/preload ("invalid hyprpaper request");
    # only wallpaper and listactive work, so the first two may fail.
    hyprctl hyprpaper unload all      >/dev/null 2>&1 || true
    hyprctl hyprpaper preload "$DEST" >/dev/null 2>&1 || true
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
        printf 'desktop   set over ipc by this script; hyprpaper.conf cannot name a path\n'
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

case "$(file -b --mime-type -- "$SRC")" in
    image/png)
        cp -- "$SRC" "$tmp"
        ;;
    image/*)
        if command -v magick >/dev/null 2>&1; then
            magick "$SRC" "png:$tmp"
        elif command -v convert >/dev/null 2>&1; then
            convert "$SRC" "png:$tmp"
        else
            die "$SRC is not a png and imagemagick is not installed to convert it"
        fi
        ;;
    *)
        die "$SRC is not an image"
        ;;
esac

chmod 644 -- "$tmp"
mv -T -- "$tmp" "$DEST"
trap - EXIT

reload
