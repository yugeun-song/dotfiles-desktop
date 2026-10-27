#!/usr/bin/env bash
# bin/bar --once and the launcher's app-scope.sh, with stand-ins for
# quickshell and systemd-run: the bar starts without core files or a
# detailed log, and a program it starts gets the core limit back.
# The stand-ins expand their own variables.
# shellcheck disable=SC2016

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-desktop-bar.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

passed=0
failed=0
is() {
    if [[ $2 == "$3" ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); printf 'FAIL  bar: %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

mkdir -p "$WORK/bin" "$WORK/config" "$WORK/state" "$WORK/run"
: >"$WORK/config/shell.qml"
# What the bar would run: its own limits and what it hands on.
# bash, not sh: in POSIX mode ulimit counts 512-byte blocks. The arguments
# go to a file of their own.
printf '#!/bin/bash\necho "$*" >"%s/args"\necho "$(ulimit -S -c) ${BAR_APP_CORE_LIMIT-unset}"\n' "$WORK" >"$WORK/bin/qs"
# systemd-run --scope execs its command in place.
printf '#!/bin/sh\nwhile [ "$1" != -- ]; do shift; done\nshift\nexec "$@"\n' >"$WORK/bin/systemd-run"
chmod +x "$WORK/bin/"*
python3 -I -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$WORK/run/bus"

once() {
    env -i HOME="$WORK" PATH="$WORK/bin:/usr/bin:/bin" BAR_CONFIG_DIR="$WORK/config" XDG_STATE_HOME="$WORK/state" \
        bash -c "ulimit -S -c $1; exec bash '$REPO/bin/bar' --once"
}
is "the bar runs without core files and hands the old limit on" "$(once unlimited)" "0 unlimited"
is "a numeric limit is handed on as it was" "$(once 2048)" "0 2048"
once unlimited >/dev/null
is "no detailed log by default" "$(grep -o -- --no-detailed-logs "$WORK/args")" "--no-detailed-logs"
env -i HOME="$WORK" PATH="$WORK/bin:/usr/bin:/bin" BAR_CONFIG_DIR="$WORK/config" \
    XDG_STATE_HOME="$WORK/state" BAR_DETAILED_LOGS=1 bash "$REPO/bin/bar" --once >/dev/null
is "BAR_DETAILED_LOGS=1 keeps it" "$(grep -c -- --no-detailed-logs "$WORK/args")" "0"

probe='echo "$(ulimit -S -c) ${BAR_APP_CORE_LIMIT-unset}"'
# $1 the runtime directory: without its bus socket the program starts in the
# bar's own group instead of a scope.
scope() {
    env -i HOME="$WORK" PATH="$WORK/bin:/usr/bin:/bin" XDG_RUNTIME_DIR="$1" BAR_APP_CORE_LIMIT=unlimited \
        bash -c "ulimit -S -c 0; exec bash '$REPO/quickshell/bar/scripts/app-scope.sh' -- bash -c '$probe'" 2>/dev/null
}
is "a program started in its scope gets the limit back" "$(scope "$WORK/run")" "unlimited unset"
is "and so does one started in the bar's group" "$(scope "$WORK/none")" "unlimited unset"
is "a program started without the bar's variable keeps its limit" \
    "$(env -i PATH="$WORK/bin:/usr/bin:/bin" XDG_RUNTIME_DIR="$WORK/run" bash -c "ulimit -S -c 0; exec bash '$REPO/quickshell/bar/scripts/app-scope.sh' -- bash -c 'ulimit -S -c'" 2>/dev/null)" "0"

if (( failed )); then
    echo "FAIL  bar: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  bar: $passed checks"
