#!/usr/bin/env bash
#
# Set the wallpaper.
#
# One image, at one path. hyprpaper.conf preloads it and hyprlock.conf draws
# it blurred, both by that same literal path, which is what keeps the desktop
# and the lock screen from drifting apart. Changing the wallpaper therefore
# means replacing the file, not editing two configurations.
#
# The name ends in .png because both configurations name it that way. A source
# in another format is converted rather than copied under a lying extension:
# hyprlock decodes by content and would cope, but the next person reading the
# configuration should not have to find that out.
#
# Usage
#   wallpaper.sh <image>    make <image> the wallpaper
#   wallpaper.sh --reload   re-apply the file already in place
#   wallpaper.sh --show     print the path and who reads it

set -euo pipefail

DEST="${XDG_DATA_HOME:-$HOME/.local/share}/wallpapers/current.png"

die() { printf 'wallpaper: %s\n' "$*" >&2; exit 1; }

# hyprpaper caches by path, and the path never changes here. Preloading again
# without unloading first hands back the old image, so the desktop keeps the
# previous wallpaper until the next login and the lock screen does not: they
# would disagree, which is the one thing this file exists to prevent.
reload() {
    command -v hyprpaper >/dev/null 2>&1 || {
        printf 'wallpaper: hyprpaper is not installed, nothing is drawing the desktop\n' >&2
        return 0
    }
    pidof hyprpaper >/dev/null 2>&1 || {
        printf 'wallpaper: hyprpaper is not running, it will pick this up at next start\n' >&2
        return 0
    }
    # unload and preload are refused by this build ("invalid hyprpaper request")
    # and only listactive and wallpaper are answered, so failures from the
    # first two are not treated as failures. wallpaper alone loads the file,
    # which is the whole job.
    hyprctl hyprpaper unload all      >/dev/null 2>&1 || true
    hyprctl hyprpaper preload "$DEST" >/dev/null 2>&1 || true
    hyprctl hyprpaper wallpaper ",$DEST" >/dev/null || die "hyprpaper would not set $DEST"

    # Verified rather than assumed. wallpaper answers with an empty line
    # whether or not it worked, so the only way to know is to ask.
    if ! hyprctl hyprpaper listactive 2>/dev/null | grep -qF "$DEST"; then
        die "hyprpaper accepted $DEST but is not showing it"
    fi
    printf 'wallpaper: %s\n' "$DEST"
}

case "${1-}" in
    --show)
        printf 'path      %s\n' "$DEST"
        [[ -f "$DEST" ]] && printf 'size      %s\n' "$(stat -c %s "$DEST") bytes" || printf 'size      missing\n'
        printf 'desktop   hypr/hyprpaper.conf\n'
        printf 'lock      hypr/hyprlock.conf\n'
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

# Written beside the target and renamed into place. hyprlock reads this file
# at the moment the screen locks, and a half-written one there is a lock
# screen with no background at the exact moment you cannot fix it.
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
