#!/bin/sh
set -u

IDLE_QML="$HOME/.config/quickshell/ii/services/Idle.qml"
STATE_JSON="$HOME/.local/state/quickshell/states.json"
CONFIG_JSON="$HOME/.config/illogical-impulse/config.json"

heal_state() {
    [ -f "$STATE_JSON" ] && [ -w "$STATE_JSON" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    cur=$(jq -r '.idle.inhibit' "$STATE_JSON" 2>/dev/null) || return 0
    [ "$cur" = "true" ] && return 0
    dir=$(dirname "$STATE_JSON")
    [ -w "$dir" ] || return 0
    tmp=$(mktemp "$dir/.states.json.heal.XXXXXX") || return 0
    if jq '.idle = (.idle // {}) | .idle.inhibit = true' "$STATE_JSON" > "$tmp" 2>/dev/null \
         && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
        chmod --reference="$STATE_JSON" "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$STATE_JSON"
    else
        rm -f "$tmp"
    fi
}

heal_idle_file() {
    [ -f "$IDLE_QML" ] && [ -r "$IDLE_QML" ] && [ -w "$IDLE_QML" ] || return 0
    if grep -Eq '^[[:space:]]*inhibit:[[:space:]]*false[[:space:]]*$' "$IDLE_QML"; then
        sed -i -E 's/^([[:space:]]*inhibit:[[:space:]]*)false([[:space:]]*)$/\1true\2/' "$IDLE_QML"
    fi
}

heal_config() {
    [ -f "$CONFIG_JSON" ] && [ -w "$CONFIG_JSON" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    cur_gps=$(jq -r '.bar.weather.enableGPS' "$CONFIG_JSON" 2>/dev/null) || return 0
    cur_city=$(jq -r '.bar.weather.city' "$CONFIG_JSON" 2>/dev/null) || return 0
    [ "$cur_gps" = "false" ] && [ "$cur_city" = "Seoul" ] && return 0
    dir=$(dirname "$CONFIG_JSON")
    [ -w "$dir" ] || return 0
    pre=$(jq -cS . "$CONFIG_JSON" 2>/dev/null) || return 0
    tmp=$(mktemp "$dir/.config.json.heal.XXXXXX") || return 0
    if jq '.bar = (.bar // {}) | .bar.weather = (.bar.weather // {}) | .bar.weather.enableGPS = false | .bar.weather.city = "Seoul"' \
          "$CONFIG_JSON" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
        post=$(jq -cS . "$CONFIG_JSON" 2>/dev/null) || { rm -f "$tmp"; return 0; }
        if [ "$pre" != "$post" ]; then
            rm -f "$tmp"
            return 0
        fi
        chmod --reference="$CONFIG_JSON" "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$CONFIG_JSON"
    else
        rm -f "$tmp"
    fi
}

heal_state
heal_idle_file
heal_config
exit 0
