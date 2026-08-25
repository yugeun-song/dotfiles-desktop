#!/usr/bin/env bash
#
# Tell the portal what the desktop looks like.
#
# On Wayland a GTK application does not read ~/.config/gtk-3.0/settings.ini
# first. It asks xdg-desktop-portal, and the portal answers from dconf, the
# key value store gsettings writes to. So the ini file can be perfectly
# correct and every GTK window still comes up in the wrong theme, because
# nothing it reads is the file.
#
# dconf is not a file this repository can link. It is a binary database in
# ~/.config/dconf/user, written by the running session. That is why these
# values are applied by a script at session start rather than deployed by
# install.sh: there is nothing to deploy.
#
# The values here must agree with gtk/gtk-3.0-settings.ini and
# gtk/gtk-4.0-settings.ini. Two places, one look; changing one without the
# other produces a desktop that disagrees with itself depending on which
# toolkit drew the window.

set -uo pipefail

command -v gsettings >/dev/null 2>&1 || {
    echo "gsettings-apply: gsettings is not installed, gtk applications will use their own defaults" >&2
    exit 0
}

set_key() {
    local schema="$1" key="$2" value="$3" current
    current=$(gsettings get "$schema" "$key" 2>/dev/null) || {
        echo "gsettings-apply: no such key: $schema $key" >&2
        return 0
    }
    # Written only when it differs. Every write wakes every application
    # listening for the change, and there is no reason to do that on a value
    # that is already right.
    [[ "$current" == "'$value'" || "$current" == "$value" ]] && return 0
    gsettings set "$schema" "$key" "$value" 2>/dev/null \
        || echo "gsettings-apply: could not set $key" >&2
}

I=org.gnome.desktop.interface

set_key "$I" gtk-theme      "Breeze-Dark"
set_key "$I" icon-theme     "breeze-dark"
set_key "$I" cursor-theme   "breeze_cursors"
set_key "$I" cursor-size    24
set_key "$I" font-name      "Inter 11"
set_key "$I" monospace-font-name "CaskaydiaCove Nerd Font Mono 11"
# The portal reports this as org.freedesktop.appearance color-scheme, which is
# what a GTK4 or libadwaita application actually looks at.
set_key "$I" color-scheme   "prefer-dark"
