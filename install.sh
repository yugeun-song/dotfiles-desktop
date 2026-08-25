#!/usr/bin/env bash
#
# Links the desktop configuration into place.
#
# Nothing here needs privileges except the fontconfig file, which is offered
# separately because it belongs to the system rather than the user.
#
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"

link() {
    local from="$1" to="$2"
    if [[ ! -e "$from" ]]; then
        echo "missing source: $from" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$to")"
    if [[ -L "$to" && "$(readlink -f "$to")" == "$(readlink -f "$from")" ]]; then
        echo "already linked $to"
        return 0
    fi
    # fcitx5 saves its profile by rename()-ing a temp file over the target, and
    # rename() replaces the link rather than following it. What is left is a
    # real file holding the newest state, so backing it up and relinking the
    # repo copy would undo whatever was just changed. Only files are checked:
    # for a directory the rename happens inside it and the link survives.
    if [[ -f "$to" && ! -L "$to" && "$to" -nt "$from" ]]; then
        echo "left $to alone: it is a real file, newer than $from"
        echo "  something rewrote it in place; copy it into $from to keep it"
        return 0
    fi
    # The new link is created under a temporary name first, so a failure here
    # leaves the existing config where it is instead of removing it and then
    # failing to put anything back.
    local tmp="$to.new-$STAMP"
    ln -s "$from" "$tmp"
    if [[ -e "$to" || -L "$to" ]]; then
        mv "$to" "$to.bak-$STAMP"
        echo "kept existing config at $to.bak-$STAMP"
    fi
    mv -T "$tmp" "$to"
    echo "linked $to"
}

link "$SRC/quickshell/bar"         "$CONFIG/quickshell/bar"
link "$SRC/hypr/hyprland.lua"      "$CONFIG/hypr/hyprland.lua"
link "$SRC/hypr/config"            "$CONFIG/hypr/config"
link "$SRC/hypr/scripts"           "$CONFIG/hypr/scripts"
link "$SRC/hypr/hypridle.conf"     "$CONFIG/hypr/hypridle.conf"
link "$SRC/hypr/hyprlock.conf"     "$CONFIG/hypr/hyprlock.conf"
link "$SRC/hypr/hyprpaper.conf"    "$CONFIG/hypr/hyprpaper.conf"
link "$SRC/bin/bar"               "$HOME/.local/bin/bar"
link "$SRC/fcitx5/config"          "$CONFIG/fcitx5/config"
link "$SRC/fcitx5/profile"         "$CONFIG/fcitx5/profile"
link "$SRC/fcitx5/conf"            "$CONFIG/fcitx5/conf"
link "$SRC/gtk/gtk-3.0-settings.ini" "$CONFIG/gtk-3.0/settings.ini"
link "$SRC/gtk/gtk-4.0-settings.ini" "$CONFIG/gtk-4.0/settings.ini"

make_executable() {
    local dir="$1" consumer="$2" f found=0 failed=0
    for f in "$dir"/*.sh; do
        [[ -f "$f" ]] || continue
        found=1
        if ! chmod +x "$f"; then
            echo "could not make $f executable, so $consumer will not run" >&2
            failed=1
        fi
    done
    if (( ! found )); then
        echo "no scripts in $dir, so $consumer will not run" >&2
        return 1
    fi
    if (( failed )); then
        return 1
    fi
}

make_executable "$SRC/quickshell/bar/scripts" "the caps lock, input method, weather and alarm pills"
make_executable "$SRC/hypr/scripts" "the monitor, terminal and capture bindings"

echo
echo "the font chain is a system file and is not linked automatically:"
echo "  sudo install -Dm644 $SRC/fontconfig/local.conf /etc/fonts/local.conf"
echo "  sudo fc-cache -f"
