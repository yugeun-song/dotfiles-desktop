#!/usr/bin/env bash
#
# Installs the desktop configuration into place.
#
# Files are copied, not linked, so nothing here runs until this is re-run.
# `install.sh --check` names what is behind and exits 1.
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

CHECK=0
DRIFT=0
case "${1:-}" in
    --check) CHECK=1 ;;
    "")      ;;
    *)       echo "usage: ${0##*/} [--check]" >&2; exit 2 ;;
esac

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

(( CHECK )) || acquire_sudo

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

    if (( CHECK )); then
        if [[ -L "$to" ]]; then
            echo "DRIFT   $to is still a link"; DRIFT=1
        elif [[ ! -e "$to" ]]; then
            echo "DRIFT   $to is missing"; DRIFT=1
        elif ! diff -rq "$from" "$to" >/dev/null 2>&1; then
            echo "DRIFT   $to is behind $from"; DRIFT=1
        fi
        return 0
    fi

    # A link left by an older version of this script. Removing it is the whole
    # conversion; what replaces it is the same content as a real file.
    [[ -L "$to" ]] && rm -f "$to"
    # Reporting a no-op is the point: a fix committed but never installed is
    # what cost a session, and silence is what hid it. Checked after the link
    # is gone, because diff follows one.
    if [[ -e "$to" ]] && diff -rq "$from" "$to" >/dev/null 2>&1; then
        echo "unchanged $to"
        return 0
    fi
    mkdir -p "$(dirname "$to")"
    if [[ -d "$from" ]]; then
        [[ -e "$to" && ! -d "$to" ]] && rm -f "$to"
        mkdir -p "$to"
        cp -a -- "$from/." "$to/"
        # A file the repository no longer has is one a stale binding can still
        # reach, so it goes. Only inside this directory: local.lua and
        # monitor_settings.lua live a level up and are not ours to delete.
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

    if (( CHECK )); then
        if [[ ! -e "$to" ]]; then
            echo "absent  $to would be seeded"
        elif ! diff -rq "$from" "$to" >/dev/null 2>&1; then
            echo "owned   $to differs; the program owns it, so $from is not what runs"
        fi
        return 0
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
            echo "  whatever owns it has rewritten it; copy it back into $from to keep the change"
        fi
        return 0
    fi
    mkdir -p "$(dirname "$to")"
    cp -a "$from" "$to"
    echo "seeded $to"
}

# config/ before hyprland.lua, and a reload afterwards.
#
# Hyprland reloads the moment a file it has loaded is written, and only files
# it has loaded. hyprland.lua was mirrored first once, its reload ran while the
# module it had just started requiring was not copied yet, the load failed
# before the keybinds, and the session sat in emergency mode with three binds
# and an error overlay. The new module's arrival changed nothing, because a
# file the compositor has never loaded is not one it watches. So the modules
# land first, and the explicit reload below makes the final state what is on
# disk whatever the watcher saw halfway through the copy.
# Where config/monitors.lua remembers the description of each output it has
# seen, so a disabled panel still gets its scale. The module cannot create the
# directory itself, and the reload below is its first chance to write there.
(( CHECK )) || mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
mirror "$SRC/hypr/config"            "$CONFIG/hypr/config"
mirror "$SRC/hypr/scripts"           "$CONFIG/hypr/scripts"
# The one file under hypr/ that is not in the repository: this machine's
# output settings, copied from monitor_settings_example.lua and edited.
# Mirrored when it exists, mentioned when it does not; the policy runs on
# its defaults without it.
if [[ -f "$SRC/hypr/monitor_settings.lua" ]]; then
    mirror "$SRC/hypr/monitor_settings.lua" "$CONFIG/hypr/monitor_settings.lua"
elif (( ! CHECK )); then
    echo "no hypr/monitor_settings.lua: copy hypr/monitor_settings_example.lua to it for this machine's scales"
fi
mirror "$SRC/hypr/hyprland.lua"      "$CONFIG/hypr/hyprland.lua"
# Files this repository once installed and no longer does. The policy reads
# monitor_settings.lua now; a preset left behind would only mislead.
_retired_files=("$CONFIG/hypr/monitors.preset")
for _retired in "${_retired_files[@]}"; do
    [[ -e "$_retired" ]] || continue
    if (( CHECK )); then
        echo "DRIFT   $_retired is no longer used"; DRIFT=1
    else
        rm -f -- "$_retired" && echo "removed retired $_retired"
    fi
done
unset _retired _retired_files
if (( ! CHECK )); then
    if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 && echo "reloaded the running compositor" \
            || echo "could not reload the running compositor; run: hyprctl reload" >&2
    else
        echo "no compositor reachable from here; a running session picks this up at its next hyprctl reload"
    fi
fi
seed "$SRC/hypr/hypridle.conf"     "$CONFIG/hypr/hypridle.conf"
seed "$SRC/hypr/hyprlock.conf"     "$CONFIG/hypr/hyprlock.conf"
seed "$SRC/hypr/hyprpaper.conf"    "$CONFIG/hypr/hyprpaper.conf"
mirror "$SRC/bin/bar"               "$HOME/.local/bin/bar"
mirror "$SRC/bin/unlock"            "$HOME/.local/bin/unlock"

if (( CHECK )); then
    (( DRIFT )) && { echo; echo "run ./install.sh to apply"; exit 1; }
    echo "everything installed is current"
    exit 0
fi

# The session's units: the target the compositor starts, the watch that stops
# it, and one service per long-running program. Mirrored like the rest of what
# this repository authors, not linked: systemd reads user units at login, and a
# symlink into a working tree is a unit that disappears whenever that tree is
# not where it was. The reasoning for each unit is in its own file.
#
# daemon-reload afterwards, or systemd keeps serving the unit list it read at
# login and the new files are not there yet. What is already running is left
# alone: a unit that is active keeps its old process until the target is
# restarted, and the input method among them costs every open window its
# input context when it restarts. The next login, or scripts/session-start.sh,
# picks the new units up.
for _unit in "$SRC"/systemd/user/*; do
    mirror "$_unit" "$CONFIG/systemd/user/$(basename "$_unit")"
done
unset _unit

# A unit this repository once shipped and no longer does would stay installed
# and could still run: nothing sweeps that directory, which is shared with the
# units other packages enable there. So every unit here carries a first-line
# marker, and a file wearing the marker with no source left is removed.
for _installed in "$CONFIG"/systemd/user/*.service "$CONFIG"/systemd/user/*.target; do
    [[ -f "$_installed" ]] || continue
    [[ -e "$SRC/systemd/user/$(basename "$_installed")" ]] && continue
    [[ "$(head -n 1 "$_installed" 2>/dev/null)" == "# dotfiles-desktop" ]] || continue
    if (( CHECK )); then
        echo "DRIFT   $_installed is no longer in the repository"; DRIFT=1
    else
        rm -f -- "$_installed" && echo "removed retired $_installed"
    fi
done
unset _installed

# fcitx5's D-Bus activation, pointed at the unit. Same directory precedence as
# every XDG data file: the copy under the home directory wins over /usr/share.
mirror "$SRC/dbus/services/org.fcitx.Fcitx5.service" \
       "${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/org.fcitx.Fcitx5.service"

# The pointer, built rather than shipped.
#
# XCursor themes are bitmaps with the colour baked in, so a themed pointer is
# not something a setting can ask for. theme/cursor/tint-cursors.py recolours a
# packaged theme by luminance, keeping every hotspot, size and alias the source
# had, and theme/cursor/pointer.py then redraws the plain arrow over the result.
#
# One colour feeds both, and it is pointer.py's rather than Theme.qml's.
#
# The arrow was asked for in the colours of a particular drawing, and for a
# while it alone carried them while the rest of the theme still followed the
# bar. That is visible in the only way that matters: the pointer changed colour
# on its way onto a link and changed back on the way off. A cursor theme is one
# object to whoever is looking at it, so it gets one colour, and the drawn arrow
# is where that colour is written down.
#
# Failure is not fatal. A machine that cannot build it keeps whatever pointer it
# had, which is a worse-looking desktop and not a broken one.
cursor_tint=$(sed -n 's/^FILL = "\(#[0-9a-fA-F]\{6\}\)".*/\1/p' \
              "$SRC/theme/cursor/pointer.py" | head -1)
if [[ -n "$cursor_tint" ]]; then
    if "$SRC/theme/cursor/tint-cursors.py" --from Oxygen_White \
           --name Spaceduck-Sky --tint "$cursor_tint" \
           --comment "Oxygen_White recoloured to the drawn pointer's blue"; then
        # Only after the theme exists, and only over its plain arrow. No colours
        # passed: they are pointer.py's own, and the tint above already came
        # from there.
        "$SRC/theme/cursor/pointer.py" --theme Spaceduck-Sky \
            || echo "install: the arrow stayed as the tint left it" >&2
        # And the drag shapes, which lose the contest against a busy window at
        # the size the rest of the theme is drawn at. Reasoning in the script.
        "$SRC/theme/cursor/emphasise.py" --theme Spaceduck-Sky \
            || echo "install: the drag cursors were left at theme size" >&2
    else
        echo "install: could not build the cursor theme; the pointer is unchanged" >&2
    fi
else
    echo "install: no FILL in pointer.py; the cursor theme was not built" >&2
fi
seed "$SRC/fcitx5/config"          "$CONFIG/fcitx5/config"
seed "$SRC/fcitx5/profile"         "$CONFIG/fcitx5/profile"
seed "$SRC/fcitx5/conf"            "$CONFIG/fcitx5/conf"
seed "$SRC/gtk/gtk-3.0-settings.ini" "$CONFIG/gtk-3.0/settings.ini"
seed "$SRC/gtk/gtk-4.0-settings.ini" "$CONFIG/gtk-4.0/settings.ini"
seed "$SRC/kde/kdeglobals"        "$CONFIG/kdeglobals"
seed "$SRC/kde/kded6rc"           "$CONFIG/kded6rc"
seed "$SRC/kde/baloofilerc"      "$CONFIG/baloofilerc"

# The other half of turning Baloo off; the reasoning is in kde/baloofilerc.
#
# Removing the unit's enabling symlink is separate from the config key because
# they fail differently. The key is read through an ExecCondition, so it stops
# the daemon but leaves systemd starting and immediately stopping a unit at
# every login. Disabling stops that, and does nothing if the unit was never
# enabled, which is the usual case on a machine that has not run Plasma.
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable kde-baloo.service >/dev/null 2>&1 || true
fi

# KDE's crash reporter, which on this desktop crashes on every crash it is told
# about, including its own.
#
# It is a Qt GUI program started from a systemd user unit, so it has no wayland
# display and Qt ends it with qFatal. That abort is itself a coredump, which
# starts it again. One quickshell crash produced a hundred and thirty of its
# cores and 1.1 GB under /var/lib/systemd/coredump before anyone noticed, and the
# only thing in the notification area was "has encountered a fatal error".
#
# The socket is what launches it, so the socket is what has to go; disabling the
# service alone leaves the socket to start it. Nothing here reads its reports:
# they go to a Plasma dialog and to KDE's Sentry, and the machine keeps the cores
# themselves, which coredumpctl reads without any of this.
#
# All of it is a no-op where drkonqi was never installed, which is the case a
# fresh machine from packages/install-target.txt is in.
if command -v systemctl >/dev/null 2>&1; then
    for _u in drkonqi-coredump-launcher.socket \
              drkonqi-coredump-pickup.service \
              drkonqi-coredump-cleanup.timer \
              drkonqi-sentry-postman.path \
              drkonqi-sentry-postman.timer; do
        systemctl --user disable --now "$_u" >/dev/null 2>&1 || true
        systemctl --user mask "$_u" >/dev/null 2>&1 || true
    done
    unset _u
fi
seed "$SRC/kde/SpaceduckDark.colors" "$HOME/.local/share/color-schemes/SpaceduckDark.colors"

if (( ! CHECK )); then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null \
            || echo "  could not reload the user manager; the units apply at the next login" >&2
        # hypridle runs under the unit its package ships; enabling is what
        # hooks it to graphical-session.target, and it is idempotent.
        systemctl --user enable hypridle.service >/dev/null 2>&1 \
            || echo "  could not enable hypridle.service; the screen will not lock" >&2
    fi
fi

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
make_executable "$CONFIG/hypr/scripts" "the session, terminal and capture bindings"

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
