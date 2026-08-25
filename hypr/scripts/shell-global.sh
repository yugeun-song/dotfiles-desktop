#!/usr/bin/env bash
#
# Fires one of the shell's global shortcuts.
#
#   shell-global.sh launcher
#   shell-global.sh powerMenu
#
# Binding hl.dsp.global directly works from a press binding, but a release
# binding delivers the shortcut as a release, and a toggle written to act on
# the press edge then sees nothing at all. Going through hyprctl produces a
# full press and release, which is what "Super on its own opens the launcher"
# needs: that binding has to be on release, because a press binding carrying
# SUPER fires at the start of every Super combination.
set -uo pipefail

name="${1:-}"
if [[ -z "$name" ]]; then
    echo "shell-global.sh: no shortcut name given" >&2
    exit 2
fi

exec hyprctl dispatch "hl.dsp.global(\"quickshell:${name}\")"
