#!/usr/bin/env bash
# Fires a quickshell global shortcut:  shell-global.sh launcher|powerMenu
#
# A release bind (needed for bare Super) delivers hl.dsp.global as a release
# only, which press-edge toggles ignore; hyprctl dispatch sends press+release.
set -uo pipefail

name="${1:-}"
if [[ -z "$name" ]]; then
    echo "shell-global.sh: no shortcut name given" >&2
    exit 2
fi

exec hyprctl dispatch "hl.dsp.global(\"quickshell:${name}\")"
