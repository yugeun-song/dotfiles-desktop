#!/usr/bin/env bash
# Runs hypr/scripts/lock.sh with stand-ins for hyprlock, hyprctl, qs and
# fcitx5-remote, in a temporary HOME and runtime directory.
#   - No fitted config: hyprlock locks, started with SIGUSR2 ignored (the
#     bar's refresh of its island, LockIsland.qml, once reached a hyprlock
#     that had not set its handler yet, and the signal's default action ended
#     it, so the lock key locked nothing, 2026-11-02).
#   - A fitted config and a Quickshell lock that says it holds the session:
#     hyprlock never runs, and the spec and the sign are gone after.
#   - A Quickshell lock that never says so: it is ended and hyprlock locks.
#   - A lock screen this session's lock.sh holds: nothing starts. A locker
#     found elsewhere by name (a nested compositor's) does not stop the lock.
#   - A Quickshell lock that outlives the unlock: it is ended.
#   - The see-through lock (--glass): the compositor's session_lock_xray on
#     before it locks and off once it ends, the bar told before the lock
#     takes a key, the Quickshell lock started as that lock; off for every
#     other lock; without it, the lock screen; and off before hyprlock when
#     the Quickshell lock does not hold.
# The island's files of an earlier lock must be gone before either locker
# starts and after it ends.
# The stand-ins expand their own variables.
# shellcheck disable=SC2016

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-desktop-lock.XXXXXX")
cleanup() {
    [[ -f "$WORK/holder.pid" ]] && kill -KILL "$(cat "$WORK/holder.pid")" 2>/dev/null
    rm -rf -- "$WORK"
}
trap cleanup EXIT

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); printf 'FAIL  lock: %s\n' "$*"; }

mkdir -p "$WORK/bin" "$WORK/run" "$WORK/config/hypr/scripts" "$WORK/config/quickshell/bar"
cp "$REPO/hypr/scripts/lock.sh" "$REPO/hypr/scripts/lock-fit.sh" "$REPO/hypr/scripts/lock-spec.py" \
    "$WORK/config/hypr/scripts/"
cp "$REPO/hypr/hyprlock.conf" "$WORK/config/hypr/hyprlock.conf"
: >"$WORK/config/quickshell/bar/lock.qml"
# lock-colours.py is left out: without it the fitted copy keeps the beige.

# What the stand-ins were asked, in order: the compositor's option, the bar's
# word, the locker started.
events() { cat "$WORK/events" 2>/dev/null; }

# The hyprlock stand-in records what it inherited (the shell keeps a signal
# that was ignored on entry ignored) and what it found.
cat >"$WORK/bin/hyprlock" <<EOF
#!/bin/sh
echo hyprlock >>"$WORK/events"
grep '^SigIgn:' /proc/\$\$/status >"$WORK/sigign"
ulimit -S -c >"$WORK/hyprlock-core"
ls "$WORK/run" >"$WORK/run-at-start"
EOF
printf '#!/bin/sh\necho 1\n' >"$WORK/bin/fcitx5-remote"
# hyprctl: "locked" answers from $WORK/locked (false by default); "-j
# monitors all" lists one screen when $WORK/monitors exists; setting
# session_lock_xray answers ok unless $WORK/no-xray exists, as a compositor
# without the option would not.
cat >"$WORK/bin/hyprctl" <<EOF
#!/bin/sh
case "\$*" in
    locked) cat "$WORK/locked" 2>/dev/null || echo false ;;
    "-j monitors all") [ -e "$WORK/monitors" ] && echo '[{"name": "eDP-1", "width": 2880, "height": 1800, "disabled": false}]' ;;
    *"session_lock_xray = true"*) [ -e "$WORK/no-xray" ] && exit 0; echo "xray true" >>"$WORK/events"; echo ok ;;
    *"session_lock_xray = false"*) [ -e "$WORK/no-xray" ] && exit 0; echo "xray false" >>"$WORK/events"; echo ok ;;
esac
exit 0
EOF
# qs: the bar's IPC calls succeed; the lock is run as $WORK/qs-mode says:
#   hold    write LOCK_READY, wait a little, end (an unlock);
#   mute    never write it, stay until killed;
#   linger  write it and stay until killed, as one that missed its end.
cat >"$WORK/bin/qs" <<EOF
#!/bin/sh
case "\$*" in
    *lock.qml*) ;;
    *"ipc call keys glass"*) echo "bar glass" >>"$WORK/events"; exit 0 ;;
    *) exit 0 ;;
esac
echo "lock glass=\$LOCK_GLASS" >>"$WORK/events"
echo \$\$ >"$WORK/qs.pid"
echo "\$LOCK_SPEC" >"$WORK/qs-spec"
ulimit -S -c >"$WORK/qs-core"
ls "$WORK/run" >"$WORK/qs-run-at-start"
case "\$(cat "$WORK/qs-mode" 2>/dev/null)" in
    hold) echo 1 >"\$LOCK_READY"; sleep 0.3; exit 0 ;;
    mute) exec sleep 30 ;;
    linger) echo 1 >"\$LOCK_READY"; exec sleep 30 ;;
esac
exit 1
EOF
chmod +x "$WORK/bin/"*

stale() {
    for part in lead trail mark; do
        echo stale >"$WORK/run/hyprlock-island-$part"
    done
    echo '{"lead": "x"}' >"$WORK/run/lock-island.json"
}

run_lock() {
    rm -f -- "$WORK/sigign" "$WORK/run-at-start" "$WORK/qs-spec" "$WORK/qs-run-at-start" "$WORK/events"
    stale
    env -i HOME="$WORK" PATH="$WORK/bin:/usr/bin" XDG_RUNTIME_DIR="$WORK/run" XDG_CONFIG_HOME="$WORK/config" \
        USER=test LOCK_WAIT="${LOCK_WAIT:-40}" timeout 20 bash "$WORK/config/hypr/scripts/lock.sh" "$@" >/dev/null 2>&1
}

islands_gone() {
    ! compgen -G "$WORK/run/hyprlock-island-*" >/dev/null && [[ ! -e "$WORK/run/lock-island.json" ]]
}

# ---- no fitted config: hyprlock -------------------------------------------
run_lock
code=$?
if [[ $code -eq 0 ]]; then pass; else fail "lock.sh exited $code with a hyprlock that exits 0"; fi
if [[ -s "$WORK/sigign" ]]; then
    pass
    mask=$(awk '{print $2}' "$WORK/sigign")
    # SIGUSR2 is signal 12, bit 11 of the mask.
    if (( (16#$mask >> 11) & 1 )); then pass; else fail "hyprlock started with SIGUSR2 not ignored (SigIgn $mask)"; fi
else
    fail "the hyprlock stand-in never ran"
fi
if [[ "$(cat "$WORK/hyprlock-core" 2>/dev/null)" == 0 ]]; then pass; else fail "hyprlock may leave a core file with the password in it"; fi
if [[ ! -e "$WORK/qs-spec" ]]; then pass; else fail "the Quickshell lock ran without a spec"; fi
if grep -q -E '^(hyprlock-island-|lock-island.json)' "$WORK/run-at-start" 2>/dev/null; then
    fail "the island's files of an earlier lock were still there as hyprlock started"
else
    pass
fi
if islands_gone; then pass; else fail "the island's files outlived the lock"; fi

# ---- the Quickshell lock holds the session --------------------------------
touch "$WORK/monitors"
echo hold >"$WORK/qs-mode"
run_lock
code=$?
if [[ $code -eq 0 ]]; then pass; else fail "lock.sh exited $code after the Quickshell lock ended well"; fi
if [[ -s "$WORK/qs-spec" && "$(cat "$WORK/qs-spec")" == "$WORK/run/lock-spec.json" ]]; then pass
else fail "the Quickshell lock was not given the spec ($(cat "$WORK/qs-spec" 2>/dev/null))"; fi
if [[ "$(cat "$WORK/qs-core" 2>/dev/null)" == 0 ]]; then pass; else fail "the Quickshell lock may leave a core file with the password in it"; fi
if grep -qx lock-spec.json "$WORK/qs-run-at-start" 2>/dev/null; then pass; else fail "no spec was written before the lock"; fi
if [[ ! -e "$WORK/sigign" ]]; then pass; else fail "hyprlock ran although the Quickshell lock held the session"; fi
if [[ ! -e "$WORK/run/lock-spec.json" && ! -e "$WORK/run/lock-ready" ]]; then pass; else fail "the spec or the sign outlived the lock"; fi
if grep -q -E '^(hyprlock-island-|lock-island.json)' "$WORK/qs-run-at-start" 2>/dev/null; then
    fail "the island's files of an earlier lock were still there as the Quickshell lock started"
else
    pass
fi
if islands_gone; then pass; else fail "the island's files outlived the Quickshell lock"; fi
if [[ "$(events | tr '\n' '|')" == "xray false|lock glass=0|" ]]; then pass
else fail "the lock screen did not lock with the desktop out of sight under it ($(events | tr '\n' '|'))"; fi

# ---- the see-through lock -----------------------------------------------------
run_lock --glass
code=$?
if [[ $code -eq 0 ]]; then pass; else fail "lock.sh --glass exited $code after the Quickshell lock ended well"; fi
if [[ "$(events | tr '\n' '|')" == "xray true|bar glass|lock glass=1|xray false|" ]]; then pass
else fail "the see-through lock was not the desktop drawn under it, the bar told, then the lock, then the desktop hidden again ($(events | tr '\n' '|'))"; fi
if [[ ! -e "$WORK/sigign" ]]; then pass; else fail "hyprlock ran although the see-through lock held the session"; fi

touch "$WORK/no-xray"
run_lock --glass
if [[ "$(events)" == "lock glass=0" ]]; then pass
else fail "without the compositor's option the see-through lock was not the lock screen ($(events | tr '\n' '|'))"; fi
rm -f -- "$WORK/no-xray"

# ---- one that never says it holds the session -----------------------------
echo mute >"$WORK/qs-mode"
LOCK_WAIT=5 run_lock
if [[ -s "$WORK/sigign" ]]; then pass; else fail "hyprlock did not lock after the Quickshell lock never held the session"; fi
if ! kill -0 "$(cat "$WORK/qs.pid" 2>/dev/null)" 2>/dev/null; then pass
else fail "the Quickshell lock that never held the session was left running"; fi
# The see-through lock's hyprlock draws the lock screen: the desktop goes out
# of sight under it first.
LOCK_WAIT=5 run_lock --glass
if [[ "$(events | tr '\n' '|')" == "xray true|bar glass|lock glass=1|xray false|hyprlock|xray false|" ]]; then pass
else fail "hyprlock took over the see-through lock with the desktop still drawn under it ($(events | tr '\n' '|'))"; fi

# ---- a lock screen of this session already running ------------------------
# Held as lock.sh holds its guard while it waits on its locker.
flock -o "$WORK/run/lock.sh.lock" sleep 30 &
echo $! >"$WORK/holder.pid"
sleep 0.2
echo hold >"$WORK/qs-mode"
run_lock
if [[ ! -e "$WORK/sigign" && ! -e "$WORK/qs-spec" ]]; then pass; else fail "a second lock screen started beside a running one"; fi
kill -KILL "$(cat "$WORK/holder.pid")" 2>/dev/null
wait "$(cat "$WORK/holder.pid")" 2>/dev/null
rm -f -- "$WORK/holder.pid"

# ---- a locker elsewhere is none of this session's -------------------------
# Found by name, one in a nested compositor (a test's) once kept the lock key
# from locking anything (2026-11-05): this session locks all the same.
cp "$(command -v sleep)" "$WORK/bin/hyprlock-holder"
( exec -a hyprlock "$WORK/bin/hyprlock-holder" 30 ) &
echo $! >"$WORK/holder.pid"
sleep 0.2
echo hold >"$WORK/qs-mode"
run_lock
if [[ -s "$WORK/qs-spec" ]]; then pass; else fail "a locker of another compositor kept this session from locking"; fi
kill -KILL "$(cat "$WORK/holder.pid")" 2>/dev/null
wait "$(cat "$WORK/holder.pid")" 2>/dev/null
rm -f -- "$WORK/holder.pid"

# ---- one that outlives the unlock -----------------------------------------
echo linger >"$WORK/qs-mode"
echo false >"$WORK/locked"
start=$SECONDS
run_lock
if (( SECONDS - start < 15 )); then pass; else fail "lock.sh waited on a Quickshell lock that outlived the unlock"; fi
if ! kill -0 "$(cat "$WORK/qs.pid" 2>/dev/null)" 2>/dev/null; then pass
else fail "the Quickshell lock that outlived the unlock was left running"; fi

if (( failed )); then
    printf 'FAIL  lock: %d of %d checks failed\n' "$failed" "$((passed + failed))"
    exit 1
fi
printf 'PASS  lock: %d checks\n' "$passed"
