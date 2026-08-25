#!/usr/bin/env bash
# ============================================================================
# auto_monitors.sh
# Auto-switch between docked / undocked / external-only profiles based on
# which physical outputs Hyprland currently sees.
#
#   eDP-1 + HDMI-A-1  -> HDMI primary @1440p144 s1.0; eDP-1 turned off so
#                        the laptop panel stops drawing (panel state
#                        follows HDMI connection state, per user intent).
#   eDP-1 only        -> eDP primary @2880x1800@120 s1.5 (restored via
#                        hyprctl reload if coming from a docked state).
#   HDMI-A-1 only     -> HDMI primary @1440p144 s1.0.
#
# Lua-configProvider notes (Hyprland 0.55.0):
#   - hl.monitor({output=X, disabled=true}) is the only per-monitor off
#     primitive that actually works under lua. It is asymmetric: setting
#     disabled=false has no effect; the only way to re-enable is to let
#     `hyprctl reload` re-evaluate the unconditional hl.monitor calls in
#     custom/general.lua.
#   - The watcher does NOT re-spawn on reload (the hl.on hook in
#     custom/execs.lua fires on hyprland.start only, not on reload), so
#     calling reload from inside the undocked branch is safe.
#   - Park-then-disable ordering matters: the 0.55.0 layout validator sees
#     the coords of disabled monitors, and would warn if a disabled monitor
#     sits at 0x0 next to an active one. eDP is parked at 5000x0 first,
#     then HDMI placed at 0x0, then eDP disabled.
# ============================================================================

set -euo pipefail

EDP="eDP-1"
HDMI="HDMI-A-1"

EDP_RULE='{output="eDP-1",    mode="2880x1800@120", position="0x0",    scale="1.5"}'
HDMI_RULE='{output="HDMI-A-1", mode="2560x1440@144", position="0x0",    scale="1.0"}'
EDP_PARK='{output="eDP-1",    mode="2880x1800@120", position="5000x0", scale="1.5"}'
EDP_DISABLE='{output="eDP-1",  disabled=true}'

apply() {
    hyprctl eval "hl.monitor($1)" >/dev/null
}

mons_json=$(hyprctl monitors all -j)

have_edp=$(printf  '%s' "$mons_json" | jq -r --arg n "$EDP"  'any(.[]; .name == $n)')
have_hdmi=$(printf '%s' "$mons_json" | jq -r --arg n "$HDMI" 'any(.[]; .name == $n)')

if [[ "$have_hdmi" == "true" && "$have_edp" == "true" ]]; then
    apply "$EDP_PARK"
    apply "$HDMI_RULE"
    apply "$EDP_DISABLE"
elif [[ "$have_hdmi" == "true" ]]; then
    apply "$HDMI_RULE"
elif [[ "$have_edp" == "true" ]]; then
    edp_disabled=$(printf '%s' "$mons_json" | jq -r --arg n "$EDP" '.[] | select(.name == $n) | .disabled')
    if [[ "$edp_disabled" == "true" ]]; then
        hyprctl reload >/dev/null
    fi
    apply "$EDP_RULE"
fi
