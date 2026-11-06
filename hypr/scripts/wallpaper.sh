#!/usr/bin/env bash
# Sets the picture of the desktop, of the lock screen, or of both. Each side
# has its own file: hyprlock.conf names the lock's, $LOCK, and hyprpaper gets
# the desktop's, $DESK, over IPC from here (a path in hyprpaper.conf must
# exist at parse time). One picture for both is one file under both names, a
# hard link, so a later change to one side replaces only its name and the
# other keeps its picture. The lock's file keeps the name the one shared file
# had until 2026-11-03, so hyprlock.conf did not change; an install from
# before gets the desktop's file, the same picture, at its next change or
# --reload. Non-PNG sources are converted so the .png names stay honest, and
# the files are stored no larger than the lit outputs need (see below).
#
# A video (the user, 2026-11-05) gives its side two things: its first frame,
# stored as any picture under the side's name, which hyprpaper, hyprlock and
# lock-colours.py read as before; and a link beside it named .video, which
# the bar plays on the desktop (modules/VideoWallpaper.qml) and the Quickshell
# lock screen under its blur (lock-spec.py passes it on). The video starts on
# that same frame, so nothing jumps when it begins or is let go. Linked, not
# copied: a video is large, and moving or deleting it only ends its playing.
# A picture set on a side takes that side's link away.
#
# Usage
#   wallpaper.sh <image>                     both, one picture
#   wallpaper.sh --desktop <image>           the desktop alone
#   wallpaper.sh --lock <image>              the lock screen alone
#   wallpaper.sh --desktop <a> --lock <b>    each its own picture
# Each <image> may be a video instead.
#   wallpaper.sh --reload                    re-apply the desktop's file
#   wallpaper.sh --show                      print the files and who reads them
# A stored file may be the image, read as it was when the command began:
# `--lock <the desktop's file>` gives the lock the desktop's picture again,
# and each side naming the other's swaps them. It is linked, not converted.

set -euo pipefail

DIR="$HOME/Pictures/Wallpapers"
DESK="$DIR/current-desktop.png"
LOCK="$DIR/current-lockscreen.png"
DESK_VIDEO="$DIR/current-desktop.video"
LOCK_VIDEO="$DIR/current-lockscreen.video"
USAGE="usage: wallpaper.sh <image|video> | [--desktop <image|video>] [--lock <image|video>] | --reload | --show"

die() { printf 'wallpaper: %s\n' "$*" >&2; exit 1; }

# Written beside the file and renamed into place: hyprlock may read its file
# at any moment.
tmps=()
trap 'rm -f -- "${tmps[@]}"' EXIT

stored() { [[ "$1" -ef "$DESK" || "$1" -ef "$LOCK" ]]; }

# A second name for a picture already stored; a copy where the filesystem
# has no hard links.
link() {
    tmps+=("$2")
    ln -f -- "$1" "$2" 2>/dev/null || cp -f -- "$1" "$2"
}

# GNU mv refuses two names of one file: that picture is in place already,
# and only the spare name goes.
place() {
    if [[ "$1" -ef "$2" ]]; then rm -f -- "$1"; else mv -T -- "$1" "$2"; fi
}

# Stored at the size that covers every lit output, rotation included, and
# never enlarged: hyprpaper keeps a texture of the whole image per output and
# hyprlock decodes and blurs the file at every lock, so a 6000x4000 photo held
# 92 MiB per screen and loading it peaked at 250 MB. A larger screen connected
# later shows an enlarged copy until the wallpaper is set again.
fit=()
fitted=0
encode() {
    local size
    if (( ! fitted )); then
        size="$(hyprctl -j monitors 2>/dev/null | jq -r '
            [.[] | select(.disabled != true)
                 | if (.transform % 2) == 1 then [.height, .width] else [.width, .height] end]
            | if length == 0 then empty else "\(map(.[0]) | max)x\(map(.[1]) | max)" end' 2>/dev/null)" || size=""
        if [[ "$size" =~ ^[0-9]+x[0-9]+$ ]]; then fit=(-resize "${size}^>"); fi
        fitted=1
    fi
    tmps+=("$2")
    if [[ -n "$conv" ]]; then
        "$conv" "$1" -auto-orient "${fit[@]}" "png:$2"
    else
        cp -f -- "$1" "$2"
    fi
    chmod 644 -- "$2"
}

is_video() { [[ "$(file -b --mime-type -- "$1")" == video/* ]]; }

# A video's first frame, as a picture for encode().
frame() {
    tmps+=("$2")
    ffmpeg -loglevel error -nostdin -y -i "$1" -frames:v 1 -an -f image2 -c:v png "$2" \
        || die "could not read a frame of $1"
}

prepare() {
    if stored "$1"; then
        link "$1" "$2"
    elif is_video "$1"; then
        frame "$1" "$2.frame.png"
        encode "$2.frame.png" "$2"
    else
        encode "$1" "$2"
    fi
}

# The video a source brings: itself, or the one a stored picture's side
# plays, so a stored file handed to the other side takes its video along.
video_of() {
    if [[ "$1" -ef "$DESK" && -e "$DESK_VIDEO" ]]; then readlink -f -- "$DESK_VIDEO"
    elif [[ "$1" -ef "$LOCK" && -e "$LOCK_VIDEO" ]]; then readlink -f -- "$LOCK_VIDEO"
    elif ! stored "$1" && is_video "$1"; then readlink -f -- "$1"
    fi
}

# Renamed into place as the pictures are; none for a picture.
set_video() {
    if [[ -n "$2" ]]; then
        tmps+=("$1.new-$$")
        ln -sfn -- "$2" "$1.new-$$"
        mv -T -- "$1.new-$$" "$1"
    else
        rm -f -- "$1"
    fi
}

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
    hyprctl hyprpaper wallpaper ",$DESK" >/dev/null || die "hyprpaper would not set $DESK"

    # wallpaper answers an empty line either way; confirm via listactive.
    if ! hyprctl hyprpaper listactive 2>/dev/null | grep -qF "$DESK"; then
        die "hyprpaper accepted $DESK but is not showing it"
    fi
    printf 'wallpaper: desktop %s\n' "$DESK"
}

show() {
    local side path
    for side in desktop lock; do
        if [[ $side == desktop ]]; then path=$DESK; else path=$LOCK; fi
        if [[ -f "$path" ]]; then
            printf '%-9s %s (%s bytes)\n' "$side" "$path" "$(stat -c %s -- "$path")"
        else
            printf '%-9s %s (missing)\n' "$side" "$path"
        fi
        if [[ -e "${path%.png}.video" ]]; then
            printf '%-9s plays %s\n' "" "$(readlink -f -- "${path%.png}.video")"
        elif [[ -L "${path%.png}.video" ]]; then
            printf '%-9s its video is gone: %s\n' "" "$(readlink -- "${path%.png}.video")"
        fi
    done
    printf 'readers   the desktop over ipc from this script, hyprpaper.conf naming no path;\n'
    printf '          the lock from hypr/hyprlock.conf, which names its path\n'
    if [[ "$DESK" -ef "$LOCK" ]]; then
        printf 'pictures  one, under both names\n'
    elif [[ -e "$LOCK" && ! -e "$DESK" ]]; then
        printf "pictures  one: the lock's file serves the desktop until a change or --reload\n"
    elif [[ -e "$LOCK" ]]; then
        printf 'pictures  two\n'
    fi
}

case "${1-}" in
    --show|--reload|-h|--help)
        (( $# == 1 )) || die "$1 takes nothing else"
        case "$1" in
            --show) show ;;
            --reload)
                # An install from before 2026-11-03: see the top.
                if [[ -e "$LOCK" && ! -e "$DESK" ]]; then
                    link "$LOCK" "$DESK.new-$$"
                    place "$DESK.new-$$" "$DESK"
                fi
                [[ -f "$DESK" ]] || die "$DESK does not exist yet"
                reload
                ;;
            *) printf '%s\n' "$USAGE" ;;
        esac
        exit 0
        ;;
esac

desk_src="" lock_src="" both_src=""
while (( $# )); do
    case "$1" in
        --desktop|--lock)
            [[ -n "${2-}" && "${2-}" != --* ]] || die "$1 needs an image"
            if [[ "$1" == --desktop ]]; then
                [[ -z "$desk_src" ]] || die "--desktop given twice"
                desk_src=$2
            else
                [[ -z "$lock_src" ]] || die "--lock given twice"
                lock_src=$2
            fi
            shift 2
            ;;
        -*) die "unknown option $1; $USAGE" ;;
        *)
            [[ -z "$both_src" ]] || die "one image for both, or --desktop and --lock; $USAGE"
            both_src=$1
            shift
            ;;
    esac
done
if [[ -n "$both_src" ]]; then
    [[ -z "$desk_src$lock_src" ]] || die "an image for both, or --desktop and --lock, not both forms"
    desk_src=$both_src lock_src=$both_src
fi
[[ -n "$desk_src$lock_src" ]] || die "$USAGE"

conv=$(command -v magick || command -v convert || true)
for src in "$desk_src" "$lock_src"; do
    [[ -n "$src" ]] || continue
    [[ -f "$src" ]] || die "no such file: $src"
    stored "$src" && continue
    mime="$(file -b --mime-type -- "$src")"
    if [[ "$mime" == video/* ]]; then
        command -v ffmpeg >/dev/null 2>&1 || die "$src is a video and ffmpeg is not installed to read its first frame"
        continue
    fi
    [[ "$mime" == image/* ]] || die "$src is not an image or a video"
    [[ -n "$conv" || "$mime" == image/png ]] || die "$src is not a png and imagemagick is not installed to convert it"
done

# The desktop keeps what it shows. On an install from before 2026-11-03 that
# is the lock's file, about to change, so the desktop takes it under its own
# name, and hyprpaper is moved onto that name: it reads the path again for a
# screen connected later, which would otherwise show the lock's new picture.
if [[ -z "$desk_src" && -e "$LOCK" && ! -e "$DESK" ]]; then
    desk_src=$LOCK
fi

mkdir -p -- "$DIR"

# Read before anything is renamed, as the pictures are.
desk_video="" lock_video=""
if [[ -n "$desk_src" ]]; then desk_video=$(video_of "$desk_src"); fi
if [[ -n "$lock_src" ]]; then lock_video=$(video_of "$lock_src"); fi

# Both prepared before either is renamed: a failure changes neither side, and
# a stored file given as the image is read as it was.
if [[ -n "$desk_src" ]]; then prepare "$desk_src" "$DESK.new-$$"; fi
if [[ -n "$lock_src" ]]; then
    if [[ -n "$desk_src" && "$lock_src" -ef "$desk_src" ]]; then
        link "$DESK.new-$$" "$LOCK.new-$$"
    else
        prepare "$lock_src" "$LOCK.new-$$"
    fi
fi
if [[ -n "$desk_src" ]]; then
    place "$DESK.new-$$" "$DESK"
    set_video "$DESK_VIDEO" "$desk_video"
fi
if [[ -n "$lock_src" ]]; then
    place "$LOCK.new-$$" "$LOCK"
    set_video "$LOCK_VIDEO" "$lock_video"
    printf 'wallpaper: lock %s%s\n' "$LOCK" "${lock_video:+ playing $lock_video}"
fi
if [[ -n "$desk_src" ]]; then
    reload
    [[ -n "$desk_video" ]] && printf 'wallpaper: desktop plays %s\n' "$desk_video"
    # The bar plays the desktop's video and reads the link at this word; in
    # the background, so a bar that does not answer never holds this up.
    if command -v qs >/dev/null 2>&1; then
        qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar" ipc call wallpaper changed >/dev/null 2>&1 &
    fi
fi
