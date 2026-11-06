#!/usr/bin/env bash
# Runs hypr/scripts/wallpaper.sh in a temporary HOME with stand-ins for
# hyprctl (one 2880x1800 screen, hyprpaper's IPC kept in files), hyprpaper,
# pidof and magick (a copy, so each stored file is told by its bytes). The
# desktop and the lock screen take a picture together or each alone; one
# picture is one file under both names; a stored file given as the image is
# read as it was, so the two can swap; a refused command leaves both as they
# were; and an install from before 2026-11-03, with its one shared file,
# keeps both pictures. A video gives its side its first frame as the picture
# and a .video link beside it; a picture takes the link away, and a stored
# file handed to the other side brings its video along.
# The stand-ins expand their own variables.
# shellcheck disable=SC2016

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-desktop-wallpaper.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); printf 'FAIL  wallpaper: %s\n' "$*"; }
expect() {
    local what=$1
    shift
    if "$@"; then pass; else fail "$what"; fi
}

W="$WORK/home/Pictures/Wallpapers"
DESK="$W/current-desktop.png"
LOCK="$W/current.png"

mkdir -p "$WORK/bin"
# listactive answers at once: the script waits up to 5 s for a silent one.
cat >"$WORK/bin/hyprctl" <<EOF
#!/bin/sh
case "\$*" in
    "-j monitors") echo '[{"width":2880,"height":1800,"transform":0,"disabled":false}]' ;;
    "hyprpaper listactive") cat "$WORK/active" 2>/dev/null; exit 0 ;;
    "hyprpaper wallpaper "*) echo "eDP-1: \${3#,}" >"$WORK/active"; echo "\$3" >>"$WORK/ipc" ;;
    *) exit 1 ;;
esac
EOF
# A picture named broken fails to convert, after the other side's is ready.
cat >"$WORK/bin/magick" <<EOF
#!/bin/sh
echo "\$*" >>"$WORK/magick"
case "\$1" in *broken*) exit 1 ;; esac
for last; do :; done
cp "\$1" "\${last#png:}"
EOF
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/pidof"
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/hyprpaper"
chmod +x "$WORK/bin/"*

# Five 1x1 pictures of different colours, so their files differ.
python3 - "$WORK" <<'PYEOF'
import struct
import sys
import zlib


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


for name, rgb in (("a", (200, 40, 40)), ("b", (40, 200, 40)), ("c", (40, 40, 200)),
                  ("d", (9, 9, 9)), ("e", (240, 240, 240))):
    with open(f"{sys.argv[1]}/{name}.png", "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(b"\x00" + bytes(rgb))) + chunk(b"IEND", b""))
PYEOF
echo "not a picture" >"$WORK/notes.txt"
cp "$WORK/c.png" "$WORK/broken.png"

run() {
    env -i HOME="$WORK/home" PATH="$WORK/bin:/usr/bin" bash "$REPO/hypr/scripts/wallpaper.sh" "$@" >"$WORK/out" 2>&1
}
fresh() {
    rm -rf -- "${WORK:?}/home" "$WORK/active" "$WORK/ipc" "$WORK/magick"
    mkdir -p "$W"
}
lines() { if [[ -f "$1" ]]; then wc -l <"$1"; else echo 0; fi; }
sent_last() { [[ "$(tail -n 1 "$WORK/ipc" 2>/dev/null)" == ",$1" ]]; }
refused() { if run "$@"; then fail "accepted: wallpaper.sh $*"; else pass; fi; }

fresh
if run "$WORK/a.png"; then pass; else fail "an image for both: $(cat "$WORK/out")"; fi
expect "an image for both did not reach the desktop" cmp -s "$DESK" "$WORK/a.png"
expect "an image for both did not reach the lock" cmp -s "$LOCK" "$WORK/a.png"
expect "one picture for both is not one file under both names" test "$DESK" -ef "$LOCK"
expect "one picture for both was converted twice" test "$(lines "$WORK/magick")" -eq 1
expect "the picture was not fitted to the screen" grep -qF -- '-resize 2880x1800^>' "$WORK/magick"
expect "hyprpaper was not given the desktop's file" sent_last "$DESK"

if run --desktop "$WORK/b.png"; then pass; else fail "--desktop: $(cat "$WORK/out")"; fi
expect "--desktop did not reach the desktop" cmp -s "$DESK" "$WORK/b.png"
expect "--desktop changed the lock" cmp -s "$LOCK" "$WORK/a.png"
expect "--desktop did not reach hyprpaper" sent_last "$DESK"

sent=$(lines "$WORK/ipc")
if run --lock "$WORK/c.png"; then pass; else fail "--lock: $(cat "$WORK/out")"; fi
expect "--lock did not reach the lock" cmp -s "$LOCK" "$WORK/c.png"
expect "--lock changed the desktop" cmp -s "$DESK" "$WORK/b.png"
expect "--lock alone reloaded hyprpaper" test "$(lines "$WORK/ipc")" -eq "$sent"

if run --desktop "$WORK/d.png" --lock "$WORK/e.png"; then pass; else fail "each its own: $(cat "$WORK/out")"; fi
expect "each its own: the desktop" cmp -s "$DESK" "$WORK/d.png"
expect "each its own: the lock" cmp -s "$LOCK" "$WORK/e.png"

converted=$(lines "$WORK/magick")
if run --desktop "$LOCK" --lock "$DESK"; then pass; else fail "a swap: $(cat "$WORK/out")"; fi
expect "a swap did not give the desktop the lock's picture" cmp -s "$DESK" "$WORK/e.png"
expect "a swap did not give the lock the desktop's picture" cmp -s "$LOCK" "$WORK/d.png"
expect "a stored file was converted again" test "$(lines "$WORK/magick")" -eq "$converted"

if run --lock "$DESK"; then pass; else fail "the desktop's file for the lock: $(cat "$WORK/out")"; fi
expect "the desktop's file for the lock is not one file under both names" test "$DESK" -ef "$LOCK"
# Both names one file already: GNU mv refuses that rename.
if run --desktop "$LOCK"; then pass; else fail "a picture both sides already show: $(cat "$WORK/out")"; fi

refused
refused --desktop
refused --desktop --lock "$WORK/a.png"
refused "$WORK/a.png" --lock "$WORK/b.png"
refused "$WORK/a.png" "$WORK/b.png"
refused --show extra
refused --bogus
refused --lock "$WORK/missing.png"
refused --desktop "$WORK/a.png" --lock "$WORK/notes.txt"
refused --desktop "$WORK/a.png" --lock "$WORK/broken.png"
expect "a refused command changed the desktop" cmp -s "$DESK" "$WORK/e.png"
expect "a refused command changed the lock" cmp -s "$LOCK" "$WORK/e.png"
expect "a command left a file behind" test "$(find "$W" -mindepth 1 | wc -l)" -eq 2

if run --show; then pass; else fail "--show: $(cat "$WORK/out")"; fi
expect "--show does not name the desktop's file" grep -qF "$DESK" "$WORK/out"
expect "--show does not name the lock's file" grep -qF "$LOCK" "$WORK/out"

# An install from before 2026-11-03: one file, read by both sides.
fresh
cp "$WORK/a.png" "$LOCK"
if run --lock "$WORK/b.png"; then pass; else fail "--lock on an older install: $(cat "$WORK/out")"; fi
expect "--lock on an older install took the desktop's picture" cmp -s "$DESK" "$WORK/a.png"
expect "--lock on an older install did not reach the lock" cmp -s "$LOCK" "$WORK/b.png"
expect "hyprpaper still reads the lock's file after --lock on an older install" sent_last "$DESK"

fresh
cp "$WORK/a.png" "$LOCK"
if run --reload; then pass; else fail "--reload on an older install: $(cat "$WORK/out")"; fi
expect "--reload did not give an older install's desktop its own name" test "$DESK" -ef "$LOCK"
expect "--reload did not give hyprpaper the desktop's file" sent_last "$DESK"

# ---- videos ----------------------------------------------------------------
DV="$W/current-desktop.video"
LV="$W/current.video"
plays() { [[ -L "$1" && "$(readlink -f -- "$1")" == "$(readlink -f -- "$2")" ]]; }
if command -v ffmpeg >/dev/null 2>&1 \
    && ffmpeg -loglevel error -nostdin -f lavfi -i color=c=red:s=64x36:d=1 -c:v libx264 -pix_fmt yuv420p "$WORK/clip.mp4" 2>/dev/null; then
    fresh
    if run "$WORK/clip.mp4"; then pass; else fail "a video for both: $(cat "$WORK/out")"; fi
    expect "a video for both stored no picture" test -s "$DESK"
    expect "a video's picture is not a png" test "$(file -b --mime-type -- "$DESK")" = image/png
    expect "a video for both is not one picture under both names" test "$DESK" -ef "$LOCK"
    expect "the desktop does not play the video" plays "$DV" "$WORK/clip.mp4"
    expect "the lock does not play the video" plays "$LV" "$WORK/clip.mp4"
    expect "hyprpaper was not given the video's picture" sent_last "$DESK"

    if run --show; then pass; else fail "--show with a video: $(cat "$WORK/out")"; fi
    expect "--show does not say what plays" grep -qF "plays $WORK/clip.mp4" "$WORK/out"

    if run --desktop "$WORK/a.png"; then pass; else fail "a picture after a video: $(cat "$WORK/out")"; fi
    expect "a picture left the desktop playing" test ! -e "$DV" -a ! -L "$DV"
    expect "a picture on the desktop stopped the lock's video" plays "$LV" "$WORK/clip.mp4"

    if run --desktop "$LOCK"; then pass; else fail "the lock's file for the desktop: $(cat "$WORK/out")"; fi
    expect "the lock's file did not bring its video to the desktop" plays "$DV" "$WORK/clip.mp4"

    if run --lock "$WORK/b.png"; then pass; else fail "a picture for the lock: $(cat "$WORK/out")"; fi
    expect "a picture left the lock playing" test ! -e "$LV" -a ! -L "$LV"
    expect "a picture on the lock stopped the desktop's video" plays "$DV" "$WORK/clip.mp4"

    # A file that says it is a video and holds none: refused, nothing changed.
    printf '\x00\x00\x00\x18ftypmp42' >"$WORK/hollow.mp4"
    head -c 4096 /dev/urandom >>"$WORK/hollow.mp4"
    if [[ "$(file -b --mime-type -- "$WORK/hollow.mp4")" == video/* ]]; then
        refused --desktop "$WORK/hollow.mp4"
        expect "a refused video changed the desktop's video" plays "$DV" "$WORK/clip.mp4"
    fi
    expect "a video command left a file behind" test "$(find "$W" -mindepth 1 | wc -l)" -eq 3
else
    printf 'SKIP  wallpaper: videos (no ffmpeg with libx264)\n'
fi

if (( failed )); then
    printf 'FAIL  wallpaper: %d of %d checks failed\n' "$failed" "$((passed + failed))"
    exit 1
fi
printf 'PASS  wallpaper: %d checks\n' "$passed"
