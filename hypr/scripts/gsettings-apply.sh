#!/usr/bin/env bash
# On Wayland GTK asks xdg-desktop-portal, which answers from dconf, not from
# settings.ini. dconf is a binary database, so it is set here at session start
# instead of being installed. Keep in step with gtk/gtk-{3,4}.0-settings.ini.

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
    # Only on change: every write wakes every listening application.
    [[ "$current" == "'$value'" || "$current" == "$value" ]] && return 0
    gsettings set "$schema" "$key" "$value" 2>/dev/null \
        || echo "gsettings-apply: could not set $key" >&2
}

I=org.gnome.desktop.interface

# Only where the theme is installed: a name GTK cannot find falls back to
# Adwaita with a warning per program, and leaves whatever was set before.
if [[ -d /usr/share/themes/Breeze-Dark || -d "$HOME/.themes/Breeze-Dark" || -d "${XDG_DATA_HOME:-$HOME/.local/share}/themes/Breeze-Dark" ]]; then
    set_key "$I" gtk-theme  "Breeze-Dark"
else
    echo "gsettings-apply: Breeze-Dark is not installed, gtk applications keep their theme" >&2
fi
if [[ -d /usr/share/icons/breeze-dark || -d "${XDG_DATA_HOME:-$HOME/.local/share}/icons/breeze-dark" ]]; then
    set_key "$I" icon-theme "breeze-dark"
else
    echo "gsettings-apply: breeze-dark icons are not installed, gtk applications keep their icons" >&2
fi
# From hypr/config/env.lua via the session environment, so the cursor has one
# source of truth; env.lua leaves the theme unset when its build is missing,
# and then GTK keeps the system default like everything else.
[[ -n "${XCURSOR_THEME:-}" ]] && set_key "$I" cursor-theme "$XCURSOR_THEME"
set_key "$I" cursor-size    "${XCURSOR_SIZE:-24}"
set_key "$I" font-name      "Inter 11"
set_key "$I" monospace-font-name "CaskaydiaCove Nerd Font Mono 11"
# Surfaces as the portal's org.freedesktop.appearance color-scheme (GTK4/libadwaita).
set_key "$I" color-scheme   "prefer-dark"
