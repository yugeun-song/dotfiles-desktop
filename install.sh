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

# Copy, every run, over whatever is there.
#
# For what this repository authors and nothing else writes: the Hyprland
# configuration, the scripts, the quickshell tree, the two commands in bin/.
# These used to be symlinked, because a link makes an edit live without running
# anything. What a link also does is make the installed path resolve back into
# the working tree, so anything that finds a sibling by walking up from its own
# location finds it in the repository rather than beside itself.
# hypr/scripts/auto_monitors.sh read ../monitors.preset that way and the preset
# was never installed at all; nothing reported it, the panel would simply have
# come up at scale 1.
#
# Unlike seed() this overwrites. The repository is the source of truth here, so
# a difference at the destination is something to lose rather than to keep. The
# copy goes in place rather than being swapped in, because quickshell watches
# these files and reloads on a write: a directory replaced underneath it is a
# crash instead of a reload.
mirror() {
    local from="$1" to="$2" rel
    if [[ ! -e "$from" ]]; then
        echo "missing source: $from" >&2
        exit 1
    fi
    # A link left by an older version of this script. Removing it is the whole
    # conversion; what replaces it is the same content as a real file.
    [[ -L "$to" ]] && rm -f "$to"
    mkdir -p "$(dirname "$to")"
    if [[ -d "$from" ]]; then
        [[ -e "$to" && ! -d "$to" ]] && rm -f "$to"
        mkdir -p "$to"
        cp -a -- "$from/." "$to/"
        # A file the repository no longer has is one a stale binding can still
        # reach, so it goes. Only inside this directory: local.lua and
        # local.monitors live a level up and are not ours to delete.
        while IFS= read -r -d '' rel; do
            rel="${rel#./}"
            if [[ ! -e "$from/$rel" ]]; then
                rm -rf -- "${to:?}/$rel"
                echo "removed stale $to/$rel"
            fi
        done < <(cd -- "$to" && find . -mindepth 1 -print0)
    else
        # Written beside the target and moved onto it, so there is never a
        # moment when the path does not exist. Hyprland watches its config and
        # reads it the instant it changes: an rm followed by a cp gave it a
        # window in which the file was gone, and it put "cannot open
        # hyprland.lua: No such file or directory" on the screen.
        local tmp="$to.new-$$"
        cp -a -- "$from" "$tmp"
        mv -T -- "$tmp" "$to"
    fi
    echo "installed $to"
}

mirror "$SRC/quickshell/bar"         "$CONFIG/quickshell/bar"
# Copy, once, and then leave it alone.
#
# The rule this file follows: mirror what is authored here, seed what a program
# owns. Everything under hypr/ and quickshell/ is written by hand, so the
# repository wins on every run. The files below are not.
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

mirror "$SRC/hypr/hyprland.lua"      "$CONFIG/hypr/hyprland.lua"
mirror "$SRC/hypr/config"            "$CONFIG/hypr/config"
mirror "$SRC/hypr/scripts"           "$CONFIG/hypr/scripts"
mirror "$SRC/hypr/monitors.preset"  "$CONFIG/hypr/monitors.preset"
seed "$SRC/hypr/hypridle.conf"     "$CONFIG/hypr/hypridle.conf"
seed "$SRC/hypr/hyprlock.conf"     "$CONFIG/hypr/hyprlock.conf"
seed "$SRC/hypr/hyprpaper.conf"    "$CONFIG/hypr/hyprpaper.conf"
mirror "$SRC/bin/bar"               "$HOME/.local/bin/bar"
mirror "$SRC/bin/unlock"            "$HOME/.local/bin/unlock"

# The pointer, built rather than shipped.
#
# XCursor themes are bitmaps with the colour baked in, so a themed pointer is
# not something a setting can ask for. theme/cursor/tint-cursors.py recolours a
# packaged theme by luminance, which keeps every hotspot, size and alias the
# source had. The tint is read out of Theme.qml so the palette stays the only
# place the colour is written; hard-coding it here would be a second copy that
# drifts the first time the bar's blue changes.
#
# Failure is not fatal. A machine that cannot build it keeps whatever pointer it
# had, which is a worse-looking desktop and not a broken one.
cursor_tint=$(sed -n 's/.*accentSky:  *"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' \
              "$SRC/quickshell/bar/services/Theme.qml" | head -1)
if [[ -n "$cursor_tint" ]]; then
    if "$SRC/theme/cursor/tint-cursors.py" --from Oxygen_White \
           --name Spaceduck-Sky --tint "$cursor_tint" \
           --comment "Oxygen_White in the bar's sky blue"; then
        # Only after the theme exists, and only over its plain arrow. Both
        # colours come out of Theme.qml, so the pointer is drawn from the same
        # two the bar behind it uses.
        cursor_ink=$(sed -n 's/.*bg: *"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' \
                     "$SRC/quickshell/bar/services/Theme.qml" | head -1)
        "$SRC/theme/cursor/pointer.py" --theme Spaceduck-Sky \
            --fill "$cursor_tint" --outline "${cursor_ink:-#0f111b}" \
            || echo "install: the arrow stayed as the tint left it" >&2
    else
        echo "install: could not build the cursor theme; the pointer is unchanged" >&2
    fi
else
    echo "install: no accentSky in Theme.qml; the cursor theme was not built" >&2
fi
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

# The installed copies, not the repository. While these were symlinks the two
# were one inode and chmod-ing either worked; they are separate files now, and
# cp -a carries whatever mode the checkout had. A tree unpacked from an archive,
# or cloned with core.fileMode false, arrives at 644, and then the key bindings
# do nothing and the pills never fill while this script still reports success.
make_executable "$CONFIG/quickshell/bar/scripts" "the caps lock, input method, weather and alarm pills"
make_executable "$CONFIG/hypr/scripts" "the monitor, terminal and capture bindings"

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
