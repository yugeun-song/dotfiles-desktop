#!/usr/bin/env bash
#
# Installs the desktop configuration into place.
#
# Files are copied, not linked, so nothing here runs until this is re-run.
# `install.sh --check` names what is behind and exits 1.
#
# Two files need privileges, both under /etc because they belong to the system
# rather than to a user: the font chain, and the greeter's appearance. They
# used to be printed as commands to run afterwards, and they were never run, so
# the machine kept the configuration of the dotfiles this repository replaced.
# They are installed here now, and the privilege is asked for once at the start
# rather than in the middle.
#
# The greeter one is conditional: see greeter_is_tuigreet.
#
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"
FONTCONF=/etc/fonts/local.conf
GREETERCONF=/etc/tuigreet/config.toml

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

# Whether this machine's greeter is the one tuigreet/config.toml describes.
#
# Asked rather than assumed, because that file is only correct for tuigreet:
# its colour names, its animation and its widget layout mean nothing to any
# other greeter, and writing it where something else reads its configuration
# would be worse than leaving the appearance alone. greetd names the greeter it
# runs on one line, and that line is the answer.
#
# Three things have to hold: greetd configured, the command it runs being
# tuigreet, and tuigreet actually installed. Any of them missing and the file
# is skipped with a word about why.
greeter_is_tuigreet() {
    [[ -r /etc/greetd/config.toml ]] || return 1
    grep -qE '^[[:space:]]*command[[:space:]]*=.*\btuigreet\b' /etc/greetd/config.toml || return 1
    command -v tuigreet >/dev/null 2>&1
}

acquire_sudo() {
    local want=0
    if [[ ! -f "$FONTCONF" ]] || ! cmp -s "$SRC/fontconfig/local.conf" "$FONTCONF"; then
        want=1
    fi
    if greeter_is_tuigreet \
       && { [[ ! -f "$GREETERCONF" ]] || ! cmp -s "$SRC/tuigreet/config.toml" "$GREETERCONF"; }; then
        want=1
    fi
    if (( ! want )); then
        echo "system files already installed"
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is not installed, so the system files cannot be written" >&2
        return 0
    fi
    if sudo -v 2>/dev/null; then
        SUDO_OK=1
        ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
        SUDO_KEEPALIVE=$!
    else
        echo "no sudo, so the system files are left alone" >&2
    fi
}

cleanup() {
    [[ -n "$SUDO_KEEPALIVE" ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null
    return 0
}
trap cleanup EXIT

# Parse-checked before anything is written and before the password prompt, so a
# refusal touches nothing. The mirrors below reload the running compositor, and
# a module that throws while loading takes the session to emergency mode.
#
# Only exit 1 stops the install. Anything else is the check not running, usually
# because Hyprland is not installed yet -- the state of a first run.
if (( ! CHECK )) && [[ -x "$SRC/hypr/scripts/verify-config.sh" ]]; then
    _verify=0
    "$SRC/hypr/scripts/verify-config.sh" "$SRC/hypr" >/dev/null || _verify=$?
    case "$_verify" in
        0) ;;
        1) echo "install: the Hyprland configuration does not load; nothing was copied" >&2; exit 1 ;;
        *) echo "install: could not verify the Hyprland configuration; copying it unchecked" >&2 ;;
    esac
    unset _verify
fi

(( CHECK )) || acquire_sudo

# Copy, every run, over whatever is there.
#
# For what this repository authors and nothing else writes. These were symlinks
# once, which made the installed path resolve back into the working tree: the
# old monitor script walked up from its own location and read the repository's
# preset rather than the installed one, which was never installed at all.
#
# Unlike seed() this overwrites -- the repository is the source of truth here.
# The copy goes in place rather than being swapped in, because quickshell
# reloads on a write and a directory replaced underneath it crashes instead.
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
        # One file at a time, each written beside its target and renamed over
        # it, the same way the single-file branch below works and for two more
        # reasons. bash reads a running script incrementally, so a script that
        # is blocked in a command -- session-watch.sh in inotifywait -- and
        # is overwritten in place picks up reading from the new file's bytes
        # at its old offset, and did: "unexpected EOF while looking for
        # matching quote". And Hyprland reloads on the write of any module it
        # has loaded, so an in-place copy could hand it a half-written file.
        # A rename is one file, whole, or the old one.
        while IFS= read -r -d '' rel; do
            rel="${rel#./}"
            if [[ -d "$from/$rel" && ! -L "$from/$rel" ]]; then
                mkdir -p "$to/$rel"
            else
                mkdir -p "$(dirname "$to/$rel")"
                cp -a -- "$from/$rel" "$to/$rel.new-$$"
                mv -T -- "$to/$rel.new-$$" "$to/$rel"
            fi
        done < <(cd -- "$from" && find . -mindepth 1 -print0)
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
# owns. fcitx5, KDE and GTK all save by writing a temp file beside the target
# and rename()-ing it over, and rename() replaces a symlink rather than
# following it -- so the first change made in a settings window turns the link
# into a real file and the repository quietly stops being what runs.
#
# Seeding says what is true: this is where the settings start, and the program
# owns them after. To take a change back, copy the file into the repository; to
# push one out, delete it and run this again.
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
# At the top of the home directory on purpose, not on PATH: it is typed from
# a text console after the desktop has gone dark, where "~/recover-desktop"
# is the one path that needs no memory of where anything is installed.
mirror "$SRC/bin/recover-desktop"   "$HOME/recover-desktop"
# The three commands are single files, which mirror() skips when the content
# matches, mode or no mode, and make_executable below only walks the script
# directories. A checkout that arrived at 644 would install commands nobody
# can run.
(( CHECK )) || chmod +x "$HOME/.local/bin/bar" "$HOME/.local/bin/unlock" "$HOME/recover-desktop" 2>/dev/null || true

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
for _installed in "$CONFIG"/systemd/user/*.service "$CONFIG"/systemd/user/*.target "$CONFIG"/systemd/user/*.slice; do
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
# not something a setting can ask for. tint-cursors.py recolours a packaged
# theme by luminance, keeping every hotspot and alias, and pointer.py redraws
# the plain arrow over the result.
#
# One colour feeds both, and it is pointer.py's rather than Theme.qml's: while
# the arrow alone carried a different one, the pointer changed colour on its way
# onto a link and back on the way off. A cursor theme is one object to whoever
# is looking at it.
#
# Failure is not fatal: the machine keeps whatever pointer it had.
cursor_tint=$(sed -n 's/^FILL = "\(#[0-9a-fA-F]\{6\}\)".*/\1/p' \
              "$SRC/theme/cursor/pointer.py" | head -1)
if (( CHECK )); then
    :
elif [[ -n "$cursor_tint" ]]; then
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
mirror "$SRC/node/repl.js"           "$CONFIG/node/repl.js"
mirror "$SRC/node/node.sh"           "$CONFIG/profile.d/node.sh"
mirror "$SRC/iex/iex.exs"            "$HOME/.iex.exs"
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
if (( ! CHECK )) && command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable kde-baloo.service >/dev/null 2>&1 || true
fi

# KDE's crash reporter, which on this desktop crashes on every crash it is told
# about, including its own.
#
# It is a Qt GUI started from a systemd user unit, so it has no wayland display
# and Qt ends it with qFatal -- an abort that is itself a coredump, which starts
# it again. One quickshell crash left a hundred and thirty of its cores and
# 1.1 GB under /var/lib/systemd/coredump.
#
# The socket is what launches it, so the socket is what has to go. Nothing here
# reads its reports, and coredumpctl reads the cores without any of it. A no-op
# where drkonqi was never installed.
if (( ! CHECK )) && command -v systemctl >/dev/null 2>&1; then
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
# Reported, not fatal: under set -e a missing script directory would end the
# run here and skip the font chain below without a word about it.
if (( ! CHECK )); then
    make_executable "$CONFIG/quickshell/bar/scripts" "the caps lock, input method, weather and alarm pills, and every program the bar opens" || :
    make_executable "$CONFIG/hypr/scripts" "the session, terminal and capture bindings" || :
fi

if (( CHECK )); then
    if [[ ! -f "$FONTCONF" ]] || ! cmp -s "$SRC/fontconfig/local.conf" "$FONTCONF"; then
        echo "DRIFT   $FONTCONF is behind $SRC/fontconfig/local.conf"; DRIFT=1
    fi
    if greeter_is_tuigreet; then
        if [[ ! -f "$GREETERCONF" ]] || ! cmp -s "$SRC/tuigreet/config.toml" "$GREETERCONF"; then
            echo "DRIFT   $GREETERCONF is behind $SRC/tuigreet/config.toml"; DRIFT=1
        fi
    else
        echo "skip    $GREETERCONF: this machine's greeter is not tuigreet"
    fi
    (( DRIFT )) && { echo; echo "run ./install.sh to apply"; exit 1; }
    echo "everything installed is current"
    exit 0
fi

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

# The greeter's appearance. Only for tuigreet, and only when tuigreet is what
# greetd runs; see greeter_is_tuigreet.
if ! greeter_is_tuigreet; then
    echo "greeter: not tuigreet, so $GREETERCONF is left alone"
elif [[ -f "$GREETERCONF" ]] && cmp -s "$SRC/tuigreet/config.toml" "$GREETERCONF"; then
    echo "greeter: already current"
elif (( SUDO_OK )); then
    if [[ -f "$GREETERCONF" ]]; then
        sudo cp -a "$GREETERCONF" "$GREETERCONF.bak-$STAMP" \
            && echo "kept existing greeter config at $GREETERCONF.bak-$STAMP"
    fi
    if sudo install -Dm644 "$SRC/tuigreet/config.toml" "$GREETERCONF"; then
        echo "installed $GREETERCONF"
        # Nothing to reload: greetd starts a fresh tuigreet for every login, so
        # the next one reads this. A greeter already on screen keeps the old
        # colours until it is replaced.
    else
        echo "could not write $GREETERCONF" >&2
    fi
else
    echo "the greeter config was not installed. it is a system file:" >&2
    echo "  sudo install -Dm644 $SRC/tuigreet/config.toml $GREETERCONF" >&2
fi
