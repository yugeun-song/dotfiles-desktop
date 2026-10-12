#!/usr/bin/env bash
# Tests hypr/scripts/camera.sh, the camera keys, with stand-ins for
# camera-switch, notify-send and hyprctl: which copy of the helper it picks,
# what it shows for success and failure, Hyprland's notice when the
# notification server is gone, and that the helper never gets a terminal to
# ask a password on. The real helper is never run: the system copy's path
# points into a temporary directory and HOME is one too.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$REPO/hypr/scripts/camera.sh"
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home/.local/bin" "$WORK/system"
export HOME="$WORK/home" CAMERA_SWITCH_SYSTEM="$WORK/system/camera-switch"
export PATH="$WORK/bin:$PATH" STUB_LOG="$WORK/log" NOTIFY_FAIL=""

failed=0
passed=0
ok() {
    if [[ "$2" == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL  camera keys: %s: got [%s], want [%s]\n' "$1" "$2" "$3"
    fi
}

cat >"$WORK/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
[[ -n "$NOTIFY_FAIL" ]] && exit 1
printf 'notify-send %s\n' "$*" >>"$STUB_LOG"
EOF
cat >"$WORK/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >>"$STUB_LOG"
EOF
chmod +x "$WORK/bin/notify-send" "$WORK/bin/hyprctl"
# A stand-in that is not found falls through to the real program, which
# would put these test notices on the desktop: stop before anything runs.
for tool in notify-send hyprctl; do
    if [[ "$(command -v "$tool")" != "$WORK/bin/$tool" ]]; then
        echo "FAIL  camera keys: the $tool stand-in is not the one found"
        exit 1
    fi
done

# A stand-in helper: prints which copy it is, whether its stdin is a
# terminal (also into a file of its own), and the verb, then any further
# lines; exits with $2.
helper() {
    {
        printf '#!/usr/bin/env bash\nwho=%q code=%q lines=%q\n' "$1" "$2" "$3"
        cat <<'STUB'
[[ -t 0 ]] && tty=tty || tty=notty
echo "$tty" >"$STUB_LOG.stdin"
echo "$who $tty $1"
[[ -n "$lines" ]] && printf '%s\n' "$lines"
exit "$code"
STUB
    } >"$4"
    chmod +x "$4"
}

# notify runs detached; wait for its line.
logged() {
    local tries=50
    while (( tries-- > 0 )) && [[ ! -s "$STUB_LOG" ]]; do
        sleep 0.05
    done
    cat "$STUB_LOG" 2>/dev/null
    rm -f -- "$STUB_LOG"
}

"$SCRIPT" bogus 2>/dev/null; ok "an unknown verb" "$?" 2

"$SCRIPT" 2>/dev/null; ok "nothing installed: fails" "$?" 1
ok "nothing installed: says so, critically" "$(logged)" \
    "notify-send -u critical Camera switch camera-switch is not installed; ./install.sh puts it in place"

helper user 0 "ASUS FHD webcam: off" "$HOME/.local/bin/camera-switch"
"$SCRIPT" off 2>/dev/null; ok "the user copy: succeeds" "$?" 0
ok "the user copy: its lines" "$(logged)" "notify-send -u normal user notty off ASUS FHD webcam: off"
# A key's script has the compositor's tty for stdin; the helper must not.
# Read from what the helper wrote: the pty session's end hangs up the
# detached notice before it runs.
if command -v script >/dev/null 2>&1; then
    script -qec "$SCRIPT off" /dev/null >/dev/null 2>&1
    ok "on a terminal: none passed to the helper" "$(cat "$STUB_LOG.stdin")" notty
    rm -f -- "$STUB_LOG"
fi

helper system 0 "" "$CAMERA_SWITCH_SYSTEM"
"$SCRIPT" 2>/dev/null; ok "the system copy wins" "$?" 0
ok "the system copy wins: toggle by default" "$(logged)" "notify-send -u normal system notty toggle "

helper system 1 "ASUS FHD webcam: still on, unbind: uvcvideo offers no unbind" "$CAMERA_SWITCH_SYSTEM"
"$SCRIPT" off 2>/dev/null; ok "a camera left on: the helper's status" "$?" 1
ok "a camera left on: critical" "$(logged)" \
    "notify-send -u critical system notty off ASUS FHD webcam: still on, unbind: uvcvideo offers no unbind"

helper system 0 "a: off
b: off" "$CAMERA_SWITCH_SYSTEM"
NOTIFY_FAIL=1 "$SCRIPT" off 2>/dev/null
ok "no notification server: Hyprland's notice, lines joined" "$(logged)" \
    "hyprctl notify 1 8000 0 system notty off: a: off; b: off"

helper system 126 "" "$CAMERA_SWITCH_SYSTEM"
NOTIFY_FAIL=1 "$SCRIPT" on 2>/dev/null; ok "a dismissed password dialog: pkexec's status" "$?" 126
ok "a dismissed password dialog: an error notice" "$(logged)" "hyprctl notify 3 8000 0 system notty on"

if (( failed )); then
    echo "FAIL  camera keys: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  camera keys: $passed checks"
