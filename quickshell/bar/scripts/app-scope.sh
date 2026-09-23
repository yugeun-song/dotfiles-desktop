#!/usr/bin/env bash
# Runs a program in its own systemd scope so `bar --restart` does not kill it
# (a double fork never leaves bar.service's cgroup). systemd-run --scope execs
# in place: env, cwd and fds are unchanged.
#   app-scope.sh -- kitty -e btop
set -uo pipefail

# Let a failed exec return so the fallbacks below run.
shopt -s execfail

[[ "${1:-}" == "--" ]] && shift

if [[ $# -eq 0 ]]; then
    echo "app-scope.sh: no command given" >&2
    exit 2
fi

# Every path that starts nothing ends here: journal plus a notification.
give_up() {
    echo "app-scope.sh: $1" >&2
    if command -v notify-send >/dev/null 2>&1; then
        ( timeout 2 notify-send -u critical "Nothing started" "$1" >/dev/null 2>&1 & )
    fi
    exit 127
}

# Check before exec: systemd-run's own failure would only reach the journal.
# type -P matches executable files only (no builtins or directories).
type -P -- "$1" >/dev/null 2>&1 || give_up "not installed: $1"

# Checked up front: after exec, a failed scope and a failing program share one
# exit status.
scoped=1
if ! command -v systemd-run >/dev/null 2>&1; then
    echo "app-scope.sh: systemd-run is not installed" >&2
    scoped=0
elif [[ -z "${XDG_RUNTIME_DIR:-}" || ! -S "$XDG_RUNTIME_DIR/bus" ]]; then
    echo "app-scope.sh: no user bus socket at ${XDG_RUNTIME_DIR:-<XDG_RUNTIME_DIR unset>}/bus" >&2
    scoped=0
fi

if (( scoped )); then
    # The slice is PartOf the session target, so logout still ends these.
    # --expand-environment=no: a literal ${...} in Exec belongs to the program.
    exec systemd-run --user --scope --collect --quiet \
        --slice=app-hyprland.slice --expand-environment=no -- "$@"
    echo "app-scope.sh: systemd-run went away between the test and the exec" >&2
fi

# Better inside the bar's cgroup than not started at all.
echo "app-scope.sh: starting $* inside the bar's control group" >&2
exec "$@"

give_up "could not run: $*"
