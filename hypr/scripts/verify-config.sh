#!/usr/bin/env bash
# Parse-check the Hyprland configuration without starting anything.
#
# `Hyprland --verify-config` runs exec blocks for real. Against a live session
# that means a second shell, a second watcher and a restarted input method,
# which is a strange price for a syntax check. So the check runs against a
# copy of the tree with the autostart module emptied out.
#
# It catches a module that does not parse and one that throws while loading. It
# cannot catch a Lua error inside a bind callback, because nothing here presses
# the key -- so a callback whose body can fail needs its own pcall and its own
# fallback. monitor_settings.lua is machine-local and not read here.
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

# -L follows a link instead of copying it. That mattered while ~/.config/hypr
# held symlinks into the working tree: emptying execs.lua below would have
# truncated the real file. A no-op now, kept because the argument returns the
# moment anything is linked again.
cp -aL -- "$SRC/hyprland.lua" "$work/"
cp -aL -- "$SRC/config" "$work/"

# Emptied, not deleted: hyprland.lua treats a missing module as an error, and
# that error is the one thing this script must not invent.
printf -- '-- emptied by verify-config.sh\n' > "$work/config/execs.lua"

# A machine-local override is not part of what gets committed, so it is not
# what is being verified here.
rm -f -- "$work/local.lua"

# config/monitors.lua calls hl.timer while it loads, and hl.timer at load time
# segfaults `--verify-config`. The crash took the whole check with it, and this
# script answered "config ok" to everything, syntax errors included. Stubbed in
# the copy, appended to the module loaded first so error line numbers still
# match. Guarded: creating a missing module would hide the error about it.
if [[ -f "$work/config/env.lua" ]]; then
    printf '\nhl.timer = function() end\n' >> "$work/config/env.lua"
fi

# Bounded, because install.sh runs this before it copies anything: a wedge here
# would stop an install with no output. It has never taken a tenth of a second.
status=0
out="$(timeout 60 Hyprland --verify-config -c "$work/hyprland.lua" 2>&1)" || status=$?

# Everything before the banner is startup chatter about a compositor that is
# not going to run.
result="$(printf '%s\n' "$out" | sed -n '/Config parsing result/,$p' | tail -n +2)"

# No banner is not a pass. Hyprland prints it for every configuration it
# finishes reading, sound or broken, so its absence means the check did not run.
# Reporting ok there is how a syntax error got approved.
if [[ -z "$result" ]]; then
    printf 'verify-config: %s produced no parsing result (Hyprland exited %s); the check did not run\n' \
        "$SRC" "$status" >&2
    printf '%s\n' "$out" | tail -n 20 >&2
    exit 2
fi

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
