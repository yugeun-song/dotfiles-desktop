#!/usr/bin/env bash
#
# Runs a program in its own systemd scope, so it outlives the bar.
#
# Quickshell.execDetached double-forks, which reparents to init but never
# leaves the control group, so the program stayed in bar.service's -- right for
# the pill helpers, and what closed every launcher window on `bar --restart`.
#
# systemd-run --scope moves itself into a transient unit and then execs, so this
# stays one process: environment, working directory and descriptors all cross
# unchanged and only the control group differs.
#
#   app-scope.sh -- kitty -e btop
#
set -uo pipefail

# A failed exec ends a non-interactive shell, and the fallbacks below are the
# whole point of this script. With execfail set, exec returns instead.
shopt -s execfail

[[ "${1:-}" == "--" ]] && shift

if [[ $# -eq 0 ]]; then
    echo "app-scope.sh: no command given" >&2
    exit 2
fi

# Every way out that starts nothing goes through this, so a click always leaves
# something behind: stderr for the journal, and a notification because that is
# not where anyone looks first. Guarded the way hypr/scripts/launch.sh is.
give_up() {
    echo "app-scope.sh: $1" >&2
    if command -v notify-send >/dev/null 2>&1; then
        ( timeout 2 notify-send -u critical "Nothing started" "$1" >/dev/null 2>&1 & )
    fi
    exit 127
}

# Looked up here rather than left to systemd-run, which resolves the program
# after this script has been replaced -- a stale .desktop entry was one journal
# line and a click that did nothing. type -P, not command -v: it answers with a
# file on disk, so a builtin, a directory and a non-executable all come back no.
type -P -- "$1" >/dev/null 2>&1 || give_up "not installed: $1"

# Tested before the exec, because there is no after: systemd-run reports a scope
# it could not create and a program that exited badly with the same status. Two
# messages, because the two are fixed in different places -- no systemd at all,
# or a bar started outside a user session.
scoped=1
if ! command -v systemd-run >/dev/null 2>&1; then
    echo "app-scope.sh: systemd-run is not installed" >&2
    scoped=0
elif [[ -z "${XDG_RUNTIME_DIR:-}" || ! -S "$XDG_RUNTIME_DIR/bus" ]]; then
    echo "app-scope.sh: no user bus socket at ${XDG_RUNTIME_DIR:-<XDG_RUNTIME_DIR unset>}/bus" >&2
    scoped=0
fi

if (( scoped )); then
    # The slice is PartOf the session target, so the session still ends these;
    # only bar.service stops being able to. --expand-environment=no because a
    # literal ${...} in a .desktop Exec line belongs to the program. No --unit,
    # so two copies cannot collide. --collect, so a killed scope leaves nothing.
    exec systemd-run --user --scope --collect --quiet \
        --slice=app-hyprland.slice --expand-environment=no -- "$@"
    echo "app-scope.sh: systemd-run went away between the test and the exec" >&2
fi

# Started anyway: the bar's control group only costs the program at the next
# `bar --restart`, and a click that did nothing is worse and harder to see.
echo "app-scope.sh: starting $* inside the bar's control group" >&2
exec "$@"

# Only reached when the program is there and still cannot be run at all.
give_up "could not run: $*"
