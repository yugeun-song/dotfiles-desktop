#!/usr/bin/env bash
# Parse-check the Hyprland configuration without starting anything.
#
# `Hyprland --verify-config` runs exec blocks for real. Against a live session
# that means a second shell, a second watcher and a restarted input method,
# which is a strange price for a syntax check. So the check runs against a
# copy of the tree with the autostart module emptied out.
#
# Usage: verify-config.sh [config-dir]     (default: the directory above this)

set -euo pipefail

SRC="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ ! -f "$SRC/hyprland.lua" ]]; then
    printf 'verify-config: %s has no hyprland.lua\n' "$SRC" >&2
    exit 2
fi

if ! command -v Hyprland >/dev/null 2>&1; then
    printf 'verify-config: Hyprland is not installed\n' >&2
    exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# -L, because $SRC is normally ~/.config/hypr where install.sh put symlinks
# back to the repository. Without it $work/config is a link to the real
# tree, and emptying $work/config/execs.lua below writes straight through
# it and destroys the committed file.
cp -aL -- "$SRC/hyprland.lua" "$work/"
cp -aL -- "$SRC/config" "$work/"

# Emptied, not deleted: hyprland.lua treats a missing module as an error, and
# that error is the one thing this script must not invent.
printf -- '-- emptied by verify-config.sh\n' > "$work/config/execs.lua"

# A machine-local override is not part of what gets committed, so it is not
# what is being verified here.
rm -f -- "$work/local.lua"

out="$(Hyprland --verify-config -c "$work/hyprland.lua" 2>&1)" || true

# Everything before the banner is startup chatter about a compositor that is
# not going to run.
result="$(printf '%s\n' "$out" | sed -n '/Config parsing result/,$p' | tail -n +2)"

# A clean parse prints the words "config ok" and nothing else. Treating any
# output as a problem fails on success, which is a worse lie than the one
# this script exists to catch.
problems="$(printf '%s\n' "$result" | grep -v '^[[:space:]]*$' | grep -v '^config ok$' || true)"

if [[ -z "$problems" ]]; then
    printf 'config ok: %s\n' "$SRC"
    exit 0
fi

printf 'config has problems: %s\n\n%s\n' "$SRC" "$problems" >&2
exit 1
