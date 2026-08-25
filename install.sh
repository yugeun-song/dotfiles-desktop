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
    [[ -e "$from" ]] || return 0
    mkdir -p "$(dirname "$to")"
    if [[ -e "$to" || -L "$to" ]]; then
        mv "$to" "$to.bak-$STAMP"
        echo "kept existing config at $to.bak-$STAMP"
    fi
    ln -s "$from" "$to"
    echo "linked $to"
}

link "$SRC/quickshell/bar"         "$CONFIG/quickshell/bar"
link "$SRC/hypr/custom"            "$CONFIG/hypr/custom"
link "$SRC/fcitx5/profile"         "$CONFIG/fcitx5/profile"
link "$SRC/fcitx5/conf"            "$CONFIG/fcitx5/conf"
link "$SRC/gtk/gtk-3.0-settings.ini" "$CONFIG/gtk-3.0/settings.ini"
link "$SRC/gtk/gtk-4.0-settings.ini" "$CONFIG/gtk-4.0/settings.ini"

chmod +x "$SRC/quickshell/bar/scripts/"*.sh 2>/dev/null || true

echo
echo "the font chain is a system file and is not linked automatically:"
echo "  sudo install -Dm644 $SRC/fontconfig/local.conf /etc/fonts/local.conf"
echo "  sudo fc-cache -f"
