#!/usr/bin/env bash
# Parse-check the Hyprland config on a copy with execs.lua emptied, because
# `Hyprland --verify-config` runs exec calls for real.
# Catches parse and load-time errors, not errors inside bind callbacks (those
# need their own pcall). Machine-local monitor_settings.lua is not copied.
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

# -L: if the source is ever symlinked, emptying execs.lua must not hit the real file.
cp -aL -- "$SRC/hyprland.lua" "$work/"
cp -aL -- "$SRC/config" "$work/"

# Emptied, not deleted: hyprland.lua errors on a missing module.
printf -- '-- emptied by verify-config.sh\n' > "$work/config/execs.lua"

# The machine-local override is not part of the repo.
rm -f -- "$work/local.lua"

# hl.timer at load time segfaults --verify-config, and monitors.lua calls it.
# Stubbed at the end of env.lua (loaded first) so line numbers still match;
# guarded so a missing env.lua is still reported.
if [[ -f "$work/config/env.lua" ]]; then
    printf '\nhl.timer = function() end\n' >> "$work/config/env.lua"
fi

# Bounded: install.sh runs this first, and a hang would stall the install silently.
status=0
out="$(timeout 60 Hyprland --verify-config -c "$work/hyprland.lua" 2>&1)" || status=$?

# Everything before the banner is startup chatter.
result="$(printf '%s\n' "$out" | sed -n '/Config parsing result/,$p' | tail -n +2)"

# No banner means the check did not run (e.g. a crash); never report that as ok.
if [[ -z "$result" ]]; then
    printf 'verify-config: %s produced no parsing result (Hyprland exited %s); the check did not run\n' \
        "$SRC" "$status" >&2
    printf '%s\n' "$out" | tail -n 20 >&2
    exit 2
fi

# A clean parse prints exactly "config ok".
problems="$(printf '%s\n' "$result" | grep -v '^[[:space:]]*$' | grep -v '^config ok$' || true)"

if [[ -z "$problems" ]]; then
    printf 'config ok: %s\n' "$SRC"
    exit 0
fi

printf 'config has problems: %s\n\n%s\n' "$SRC" "$problems" >&2
exit 1
