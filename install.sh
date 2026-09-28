#!/usr/bin/env bash
#
# Installs the desktop configuration. Files are copied, not linked, so nothing
# edited here runs until this is re-run. --check lists what is behind, exit 1.
#
# /etc/fonts/local.conf and /etc/tuigreet/config.toml need sudo; it is asked
# for once, up front. Printing them as manual steps meant they never ran.
#
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"
FONTCONF=/etc/fonts/local.conf
GREETERCONF=/etc/tuigreet/config.toml

# sudo is acquired before any write and kept alive in the background, since a
# cold run can outlast the timestamp. Without it only the /etc files are skipped.
SUDO_OK=0
SUDO_KEEPALIVE=

CHECK=0
DRIFT=0
case "${1:-}" in
    --check) CHECK=1 ;;
    "")      ;;
    *)       echo "usage: ${0##*/} [--check]" >&2; exit 2 ;;
esac

# tuigreet/config.toml means nothing to another greeter, so it is installed
# only when greetd's command is tuigreet and tuigreet is installed.
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

# Checked before any write or prompt: mirroring reloads the running compositor,
# and a module that throws sends the session to emergency mode. Only exit 1
# (does not load) aborts; other codes mean the check could not run, e.g. no
# Hyprland yet on a first install.
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

# For what this repository authors: overwritten on every run. Not symlinked,
# because a link resolves back into the working tree. A directory is updated
# file by file, never swapped whole: quickshell crashes if its directory is
# replaced underneath it.
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

    # Converts a link from an older install. The no-op is reported so an
    # uninstalled fix is visible; checked after unlinking because diff follows links.
    [[ -L "$to" ]] && rm -f "$to"
    if [[ -e "$to" ]] && diff -rq "$from" "$to" >/dev/null 2>&1; then
        echo "unchanged $to"
        return 0
    fi
    mkdir -p "$(dirname "$to")"
    if [[ -d "$from" ]]; then
        [[ -e "$to" && ! -d "$to" ]] && rm -f "$to"
        mkdir -p "$to"
        # Write beside and rename over. bash reads a running script lazily, so
        # overwriting session-watch.sh in place corrupts it mid-run; Hyprland
        # reloads on write and could read a half-copied module. New files go
        # in before changed ones: quickshell reloads on every write, and a
        # module updated to use a component that has not landed yet fails
        # that reload (harmless, it reloads again, but it logs an error).
        local pass
        for pass in new changed; do
            while IFS= read -r -d '' rel; do
                rel="${rel#./}"
                if [[ -d "$from/$rel" && ! -L "$from/$rel" ]]; then
                    mkdir -p "$to/$rel"
                    continue
                fi
                if [[ "$pass" == new && -e "$to/$rel" ]] || [[ "$pass" == changed && ! -e "$to/$rel" ]]; then
                    continue
                fi
                # Only files that differ are rewritten: every write is a
                # reload for quickshell and Hyprland.
                if [[ "$pass" == changed ]] && cmp -s -- "$from/$rel" "$to/$rel"; then
                    continue
                fi
                mkdir -p "$(dirname "$to/$rel")"
                cp -a -- "$from/$rel" "$to/$rel.new-$$"
                mv -T -- "$to/$rel.new-$$" "$to/$rel"
            done < <(cd -- "$from" && find . -mindepth 1 -print0)
        done
        # Prune files the repository dropped. Only inside this directory:
        # local.lua and the monitor settings sit a level up.
        while IFS= read -r -d '' rel; do
            rel="${rel#./}"
            if [[ ! -e "$from/$rel" ]]; then
                rm -rf -- "${to:?}/$rel"
                echo "removed stale $to/$rel"
            fi
        done < <(cd -- "$to" && find . -mindepth 1 -print0)
    else
        # Rename, not rm+cp: Hyprland reads its config the instant it changes
        # and errors on a momentarily missing hyprland.lua.
        local tmp="$to.new-$$"
        cp -a -- "$from" "$tmp"
        mv -T -- "$tmp" "$to"
    fi
    echo "installed $to"
}

mirror "$SRC/quickshell/bar"         "$CONFIG/quickshell/bar"
# For what a program owns: copied once, never overwritten. fcitx5, KDE and GTK
# save by rename() over the target, which replaces a symlink rather than
# following it. To take a change back, copy it into the repository; to push one
# out, delete the installed file and re-run.
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
    # A link from an older install becomes a real file.
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

# config/ before hyprland.lua, then an explicit reload. Hyprland reloads on
# writes to files it has already loaded only, so a hyprland.lua that requires a
# not-yet-copied module leaves the session in emergency mode.
# The state dir is where monitors.lua caches output descriptions; the module
# cannot create it.
(( CHECK )) || mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
mirror "$SRC/hypr/config"            "$CONFIG/hypr/config"
mirror "$SRC/hypr/scripts"           "$CONFIG/hypr/scripts"
# The tracked preset, and the untracked per-machine deviations if this
# checkout has any; the policy runs on defaults without either. Before the
# preset existed the installed monitor_settings.lua was one machine's own
# file: one that differs from the preset becomes the local file (which wins
# per field), so its values survive the change instead of being mirrored
# over; an existing local file is kept and the old one backed up beside it.
_old_settings="$CONFIG/hypr/monitor_settings.lua"
_local_settings="$CONFIG/hypr/monitor_settings.local.lua"
if [[ -f "$_old_settings" ]] && ! cmp -s "$SRC/hypr/monitor_settings.lua" "$_old_settings" \
   && ! cmp -s "$SRC/hypr/monitor_settings_example.lua" "$_old_settings" 2>/dev/null \
   && [[ ! -f "$SRC/hypr/monitor_settings.local.lua" ]]; then
    if (( CHECK )); then
        echo "DRIFT   $_old_settings is a per-machine file from before the preset; install moves it to $_local_settings"; DRIFT=1
    elif [[ -f "$_local_settings" ]]; then
        cp -a -- "$_old_settings" "$_local_settings.bak-$STAMP"
        echo "kept the old $_old_settings as $_local_settings.bak-$STAMP (a local file already exists)"
    else
        mv -- "$_old_settings" "$_local_settings"
        echo "moved the old $_old_settings to $_local_settings: its values still win over the preset"
    fi
fi
unset _old_settings _local_settings
mirror "$SRC/hypr/monitor_settings.lua" "$CONFIG/hypr/monitor_settings.lua"
if [[ -f "$SRC/hypr/monitor_settings.local.lua" ]]; then
    mirror "$SRC/hypr/monitor_settings.local.lua" "$CONFIG/hypr/monitor_settings.local.lua"
fi
mirror "$SRC/hypr/hyprland.lua"      "$CONFIG/hypr/hyprland.lua"
# Installed by older versions; removed so they cannot mislead.
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
# In ~ on purpose: typed from a text console where PATH may not be set up.
mirror "$SRC/bin/recover-desktop"   "$HOME/recover-desktop"
# mirror() ignores mode when content matches, and make_executable only walks
# the script directories, so a 644 checkout needs this.
(( CHECK )) || chmod +x "$HOME/.local/bin/bar" "$HOME/.local/bin/unlock" "$HOME/recover-desktop" 2>/dev/null || true

# Units are mirrored, then daemon-reload below. Running units are not
# restarted (restarting fcitx5 drops every window's input context); the next
# login or session-start.sh picks them up.
for _unit in "$SRC"/systemd/user/*; do
    mirror "$_unit" "$CONFIG/systemd/user/$(basename "$_unit")"
done
unset _unit

# The unit directory is shared with other packages, so only units whose first
# line is the "# dotfiles-desktop" marker and whose source is gone are removed.
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

# Overrides /usr/share's fcitx5 D-Bus activation to start the unit instead.
mirror "$SRC/dbus/services/org.fcitx.Fcitx5.service" \
       "${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/org.fcitx.Fcitx5.service"

# XCursor themes are bitmaps, so the colour is baked in at build time. The tint
# comes from pointer.py's FILL so the redrawn arrow and every other shape match.
# Failure is not fatal; the previous pointer stays.
cursor_tint=$(sed -n 's/^FILL = "\(#[0-9a-fA-F]\{6\}\)".*/\1/p' \
              "$SRC/theme/cursor/pointer.py" | head -1)
if (( CHECK )); then
    :
elif [[ -n "$cursor_tint" ]]; then
    if "$SRC/theme/cursor/tint-cursors.py" --from Oxygen_White \
           --name Spaceduck-Sky --tint "$cursor_tint" \
           --comment "Oxygen_White recoloured to the drawn pointer's blue"; then
        "$SRC/theme/cursor/pointer.py" --theme Spaceduck-Sky \
            || echo "install: the arrow stayed as the tint left it" >&2
        # Enlarges the drag shapes; reasoning in the script.
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
mirror "$SRC/spotify/spotify-launcher.conf" "$CONFIG/spotify-launcher.conf"
seed "$SRC/fcitx5/config"          "$CONFIG/fcitx5/config"
seed "$SRC/fcitx5/profile"         "$CONFIG/fcitx5/profile"
seed "$SRC/fcitx5/conf"            "$CONFIG/fcitx5/conf"
seed "$SRC/gtk/gtk-3.0-settings.ini" "$CONFIG/gtk-3.0/settings.ini"
seed "$SRC/gtk/gtk-4.0-settings.ini" "$CONFIG/gtk-4.0/settings.ini"
seed "$SRC/kde/kdeglobals"        "$CONFIG/kdeglobals"
seed "$SRC/kde/kded6rc"           "$CONFIG/kded6rc"
seed "$SRC/kde/baloofilerc"      "$CONFIG/baloofilerc"

# Baloo off, second half (see kde/baloofilerc): the config key only fails the
# unit's ExecCondition, so disable it to stop the start/stop at every login.
if (( ! CHECK )) && command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable kde-baloo.service >/dev/null 2>&1 || true
fi

# drkonqi runs from a user unit with no Wayland display, so Qt aborts it, and
# its own coredump launches it again (one crash left 1.1 GB of cores). Masked;
# coredumpctl still works. No-op where drkonqi is absent.
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
        # hypridle uses its packaged unit; enabling hooks it to
        # graphical-session.target.
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

# cp -a keeps the checkout's mode, and an archive or core.fileMode=false tree
# arrives at 644. Reported, not fatal, so set -e cannot skip the /etc steps.
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
        sudo fc-cache -f >/dev/null 2>&1 && echo "font cache rebuilt"
    else
        echo "could not write $FONTCONF" >&2
    fi
else
    echo "the font chain was not installed. it is a system file:" >&2
    echo "  sudo install -Dm644 $SRC/fontconfig/local.conf $FONTCONF" >&2
    echo "  sudo fc-cache -f" >&2
fi

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
        # No reload needed: greetd starts a fresh tuigreet per login.
    else
        echo "could not write $GREETERCONF" >&2
    fi
else
    echo "the greeter config was not installed. it is a system file:" >&2
    echo "  sudo install -Dm644 $SRC/tuigreet/config.toml $GREETERCONF" >&2
fi
