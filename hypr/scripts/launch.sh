#!/usr/bin/env bash
#
# Runs the first candidate whose program is installed.
#
#   launch.sh 'dolphin' 'nautilus' 'thunar'
#   launch.sh 'code' 'codium' 'kitty -e nvim'
#
# A candidate is a whole command line; only its first word is tested. This
# exists so a keybinding on a machine that lacks the preferred program falls
# through to one it has, and a machine that has none of them says so instead
# of leaving a key that quietly does nothing.
set -uo pipefail

if [[ $# -eq 0 ]]; then
    echo "launch.sh: no candidates given" >&2
    exit 2
fi

for candidate in "$@"; do
    program="${candidate%% *}"
    [[ -n "$program" ]] || continue
    command -v "$program" >/dev/null 2>&1 || continue
    exec sh -c "$candidate"
done

msg="none of these are installed: $*"
echo "launch.sh: $msg" >&2
if command -v notify-send >/dev/null 2>&1; then
    ( timeout 2 notify-send -u critical "Nothing to launch" "$msg" >/dev/null 2>&1 & )
fi
exit 1
