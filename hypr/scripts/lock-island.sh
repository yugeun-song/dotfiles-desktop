#!/bin/sh
# One of the lock screen island's three labels (hyprlock.conf): lead, trail
# or mark, as the bar wrote it while the screen is locked
# (quickshell/bar/services/LockIsland.qml). hyprlock runs this as the lock
# starts and again at each SIGUSR2 the bar sends, never on a timer.
#
# Without a file (no bar, or nothing written yet: lock.sh removes them
# before each lock) the leading place holds the lock and the trailing ones
# stay empty, as the island looked before it showed events.
# LOCK_ISLAND_RUN: the e2e suite's own directory instead of the session's.

dir=${LOCK_ISLAND_RUN:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}

case ${1:-} in
    lead|trail|mark) ;;
    *) exit 0 ;;
esac

file="$dir/hyprlock-island-$1"
if [ -s "$file" ]; then
    exec cat -- "$file"
fi

# md-lock (U+F033E) in UTF-8, the glyph the island always had.
if [ "$1" = lead ]; then
    printf '\363\260\214\276'
fi
