#!/usr/bin/env bash
#
# Links the desktop configuration into place.
#
# One file needs privileges: the font chain, which lives under /etc because it
# belongs to the system rather than to a user. It used to be printed as two
# commands to run afterwards, and it was never run, so the machine kept the
# font configuration of the dotfiles this repository replaced. It is installed
# here now, and the privilege for it is asked for once at the start rather than
# in the middle.
#
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"
FONTCONF=/etc/fonts/local.conf

# Asked for before anything is written, so a password prompt never appears
# halfway through with links already made and the rest still to do. Refreshed
# in the background because the timestamp expires on its own and this script
# can take longer than that on a cold cache.
#
# Failing here is not fatal: everything except the font chain is the user's own
# files. What cannot be installed is reported at the end.
SUDO_OK=0
SUDO_KEEPALIVE=

acquire_sudo() {
    if [[ -f "$FONTCONF" ]] && cmp -s "$SRC/fontconfig/local.conf" "$FONTCONF"; then
        echo "font chain already installed at $FONTCONF"
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is not installed, so $FONTCONF cannot be written" >&2
        return 0
    fi
    if sudo -v 2>/dev/null; then
        SUDO_OK=1
        ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
        SUDO_KEEPALIVE=$!
    else
        echo "no sudo, so $FONTCONF is left alone" >&2
    fi
}

cleanup() {
    [[ -n "$SUDO_KEEPALIVE" ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null
    return 0
}
trap cleanup EXIT

acquire_sudo

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

# What is still linked, and why. These four are written by hand and reloaded
# in place: hyprctl reload and a bar restart both read them straight off disk,
# and editing through a copy would mean running this script between every
# change. Nothing else writes to them, so the link cannot be replaced behind
# our back. Everything else below is seeded.
link "$SRC/quickshell/bar"         "$CONFIG/quickshell/bar"
# Copy, once, and then leave it alone.
#
# The rule this file follows: link what is authored here, seed what a program
# owns. Everything under hypr/ and quickshell/ is written by hand and reloaded
# in place, so a link is exactly right. The files below are not.
#
# fcitx5 and KDE both save by writing a temp file beside the target and
# rename()-ing it over, and rename() replaces a symlink rather than following
# it. The first change made in either settings window turns the link into a
# real file, and the repository quietly stops being what the machine reads.
# GTK's tooling does the same to settings.ini.
#
# Linking those pretends to a relationship that does not survive first contact.
# Seeding says what is true: this is where the settings start, and the program
# owns them from then on. To take a change back, copy the file into the
# repository; to push one out, delete the file and run this again.
seed() {
    local from="$1" to="$2"
    if [[ ! -e "$from" ]]; then
        echo "missing source: $from" >&2
        exit 1
    fi
    # A link left by an older version of this script. The content matches by
    # definition, so the only thing to do is turn it into the real file it
    # should have been, which is what makes the next in-place rewrite land
    # somewhere harmless.
    if [[ -L "$to" ]]; then
        rm -f "$to"
        mkdir -p "$(dirname "$to")"
        cp -a "$from" "$to"
        echo "unlinked and seeded $to"
        return 0
    fi
    if [[ -e "$to" ]]; then
        if diff -rq "$from" "$to" >/dev/null 2>&1; then
            echo "already seeded $to"
        else
            echo "left $to alone: it exists and differs from $from"
            echo "  fcitx5 owns it now; copy it back into $from to keep the change"
        fi
        return 0
    fi
    mkdir -p "$(dirname "$to")"
    cp -a "$from" "$to"
    echo "seeded $to"
}

link "$SRC/hypr/hyprland.lua"      "$CONFIG/hypr/hyprland.lua"
link "$SRC/hypr/config"            "$CONFIG/hypr/config"
link "$SRC/hypr/scripts"           "$CONFIG/hypr/scripts"
seed "$SRC/hypr/hypridle.conf"     "$CONFIG/hypr/hypridle.conf"
seed "$SRC/hypr/hyprlock.conf"     "$CONFIG/hypr/hyprlock.conf"
seed "$SRC/hypr/hyprpaper.conf"    "$CONFIG/hypr/hyprpaper.conf"
link "$SRC/bin/bar"               "$HOME/.local/bin/bar"
link "$SRC/bin/unlock"            "$HOME/.local/bin/unlock"
seed "$SRC/fcitx5/config"          "$CONFIG/fcitx5/config"
seed "$SRC/fcitx5/profile"         "$CONFIG/fcitx5/profile"
seed "$SRC/fcitx5/conf"            "$CONFIG/fcitx5/conf"
seed "$SRC/gtk/gtk-3.0-settings.ini" "$CONFIG/gtk-3.0/settings.ini"
seed "$SRC/gtk/gtk-4.0-settings.ini" "$CONFIG/gtk-4.0/settings.ini"
seed "$SRC/kde/kdeglobals"        "$CONFIG/kdeglobals"
seed "$SRC/kde/SpaceduckDark.colors" "$HOME/.local/share/color-schemes/SpaceduckDark.colors"

# hypr/config/execs.lua starts hyprland-session.target when the compositor
# comes up, and that target is the only thing that pulls graphical-session.target
# in. Without it the start fails, graphical-session.target never activates, and
# every service keyed to it -- the four xdg-desktop-portal implementations
# among them -- never starts. The visible result is a desktop that looks right
# until a file dialog or a screen share is needed.
#
# It is written here rather than linked from the repository on purpose. systemd
# reads user units at login, and a symlink pointing into a working tree is a
# unit that disappears whenever that tree is not where it was: before the
# repository has been cloned on a fresh machine, or after it is moved. Five
# lines are not worth putting the graphical session behind that.
install_session_target() {
    local dir="$CONFIG/systemd/user"
    local unit="$dir/hyprland-session.target"
    local body
    body=$(cat <<'UNIT'
[Unit]
Description=Hyprland session
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
UNIT
)
    if [[ -f "$unit" ]] && [[ "$(cat "$unit")" == "$body" ]]; then
        echo "already current $unit"
        return 0
    fi
    mkdir -p "$dir"
    printf '%s\n' "$body" > "$unit" || {
        echo "could not write $unit, so the graphical session will not come up" >&2
        return 1
    }
    echo "wrote $unit"
    # Without this systemd keeps serving the unit list it read at login and the
    # new file is not there yet.
    systemctl --user daemon-reload 2>/dev/null \
        || echo "  could not reload the user manager; the unit applies at the next login" >&2
}
install_session_target

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
if [[ -f "$FONTCONF" ]] && cmp -s "$SRC/fontconfig/local.conf" "$FONTCONF"; then
    echo "font chain: already current"
elif (( SUDO_OK )); then
    if [[ -f "$FONTCONF" ]]; then
        sudo cp -a "$FONTCONF" "$FONTCONF.bak-$STAMP" \
            && echo "kept existing font chain at $FONTCONF.bak-$STAMP"
    fi
    if sudo install -Dm644 "$SRC/fontconfig/local.conf" "$FONTCONF"; then
        echo "installed $FONTCONF"
        # Without this the new chain is on disk and nothing is using it.
        sudo fc-cache -f >/dev/null 2>&1 && echo "font cache rebuilt"
    else
        echo "could not write $FONTCONF" >&2
    fi
else
    echo "the font chain was not installed. it is a system file:" >&2
    echo "  sudo install -Dm644 $SRC/fontconfig/local.conf $FONTCONF" >&2
    echo "  sudo fc-cache -f" >&2
fi
