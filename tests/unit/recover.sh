#!/usr/bin/env bash
# Tests bin/recover-desktop's handling of a display that is lit but shows
# nothing but black, and of a bar that is gone or does not answer: what it
# reads, and which repair it reaches for, in what order. Everything it talks
# to is a stub over files in a temporary directory (hyprctl, grim, qs,
# systemctl): no compositor, bar or user unit is touched. An output is a
# file out.NAME; dpms.NAME holds its DPMS state, mirror.NAME the id of the
# output it mirrors, black.NAME makes its picture black, saver.NAME puts the
# screensaver's layer on it, hang.NAME makes its capture never finish. The
# bar is drawn on every output but one with nobar.NAME, or with late.NAME
# until the script's two-second pause; bar-down, bar-notready and bar-hung
# keep it from answering, and a restart brings a working bar back unless
# bar-stuck is there. qs-warns has qs warn on stderr; layers-fail fails the
# layer list. FIX names the repair that clears the black: wake, relight or
# bar.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$REPO/bin/recover-desktop"
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

S="$WORK/state"
SIG=test_instance
mkdir -p "$WORK/bin" "$WORK/run/hypr/$SIG" "$WORK/drm/card0-eDP-1" "$WORK/drm/card0-HDMI-A-1"
printf '%s\nwayland-test\n' "$$" > "$WORK/run/hypr/$SIG/hyprland.lock"
echo connected > "$WORK/drm/card0-eDP-1/status"
echo connected > "$WORK/drm/card0-HDMI-A-1/status"

cat > "$WORK/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
S="$RECOVER_TEST_STATE"
echo "hyprctl $*" >> "$S/calls"
names() { for f in "$S"/out.*; do [[ -e "$f" ]] && echo "${f##*/out.}"; done; }
case "$1" in
    version) echo "Hyprland stub" ;;
    monitors)
        sep=""
        printf '['
        for n in $(names); do
            printf '%s{"name":"%s","disabled":false,"width":2880,"height":1800,"refreshRate":120.0,"x":0,"y":0,"scale":1.5,"dpmsStatus":%s,"mirrorOf":"%s"}' \
                "$sep" "$n" "$(cat "$S/dpms.$n" 2>/dev/null || echo true)" "$(cat "$S/mirror.$n" 2>/dev/null || echo none)"
            sep=","
        done
        printf ']\n'
        ;;
    layers)
        [[ -e "$S/layers-fail" ]] && exit 1
        sep=""
        printf '{'
        for n in $(names); do
            ns='{"namespace":"hyprpaper"}'
            [[ -e "$S/nobar.$n" || -e "$S/late.$n" ]] || ns="$ns"',{"namespace":"quickshell"}'
            [[ -e "$S/saver.$n" ]] && ns="$ns"',{"namespace":"quickshell:screensaver"}'
            printf '%s"%s":{"levels":{"3":[%s]}}' "$sep" "$n" "$ns"
            sep=","
        done
        printf '}\n'
        ;;
    dispatch)
        if [[ "$2" =~ action\ =\ \"(enable|disable)\",\ monitor\ =\ \"([^\"]+)\" ]]; then
            n="${BASH_REMATCH[2]}"
            if [[ "${BASH_REMATCH[1]}" == disable ]]; then
                echo false > "$S/dpms.$n"
                touch "$S/cycled.$n"
            else
                echo true > "$S/dpms.$n"
                [[ -e "$S/cycled.$n" && "${FIX:-}" == relight ]] && rm -f "$S/black.$n"
            fi
        elif [[ "$2" == *'action = "enable"'* ]]; then
            for n in $(names); do echo true > "$S/dpms.$n"; done
        fi
        echo ok
        ;;
    repl) echo true ;;
    *) echo ok ;;
esac
EOF

cat > "$WORK/bin/grim" <<'EOF'
#!/usr/bin/env bash
S="$RECOVER_TEST_STATE"
echo "grim $*" >> "$S/calls"
while (( $# )); do [[ "$1" == -o ]] && { out="$2"; shift; }; shift; done
[[ -e "$S/hang.$out" ]] && exec /usr/bin/sleep 10
printf 'P6\n2 1\n255\n'
if [[ -e "$S/black.$out" ]]; then printf '\0\0\0\0\0\0'; else printf '\x10\x20\x30\x40\x50\x60'; fi
EOF

# qs -p PATH ipc show | qs -p PATH ipc call TARGET FUNCTION ARGS; a hung bar
# never answers, and the script's timeout ends the wait.
cat > "$WORK/bin/qs" <<'EOF'
#!/usr/bin/env bash
S="$RECOVER_TEST_STATE"
echo "qs $*" >> "$S/calls"
[[ -e "$S/qs-warns" ]] && echo '  WARN: Detected locale "C" with character encoding "ANSI_X3.4-1968", which is not UTF-8.' >&2
[[ -e "$S/bar-down" ]] && { echo "No running instances for \"$2/shell.qml\""; exit 255; }
[[ -e "$S/bar-hung" ]] && exec /usr/bin/sleep 10
[[ -e "$S/bar-notready" ]] && { echo "Not ready to accept queries yet."; exit 0; }
if [[ "$4" == show ]]; then
    printf 'target shell\n  function reload(): void\ntarget screensaver\n  function wake(): void\n'
    exit 0
fi
[[ "$6" == wake && -e "$S/old-bar" ]] && { echo "Function wake not found"; exit 0; }
[[ "${FIX:-}" == wake ]] && rm -f "$S"/black.* "$S"/saver.*
exit 0
EOF

cat > "$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
S="$RECOVER_TEST_STATE"
echo "systemctl $*" >> "$S/calls"
case "$*" in
    *"show hyprland-session.target -p Wants --value"*) echo "bar.service hyprpaper.service" ;;
    *is-active*) echo active ;;
    *"restart bar.service"*)
        [[ "${FIX:-}" == bar ]] && rm -f "$S"/black.* "$S"/saver.*
        [[ -e "$S/bar-stuck" ]] || rm -f "$S/bar-down" "$S/bar-hung" "$S/bar-notready" "$S"/nobar.*
        ;;
esac
exit 0
EOF

cat > "$WORK/bin/dbus-update-activation-environment" <<'EOF'
#!/bin/sh
echo "dbus-update-activation-environment $*" >> "$RECOVER_TEST_STATE/calls"
EOF
# The script's pauses wait for real hardware; here they only cost time. The
# two seconds before the bar is asked again are when a late one shows.
cat > "$WORK/bin/sleep" <<'EOF'
#!/bin/sh
[ "$1" = 2 ] && rm -f "$RECOVER_TEST_STATE"/late.*
exit 0
EOF
chmod +x "$WORK"/bin/*

failed=0
passed=0
ok() {
    if [[ "$2" == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL  recover: %s: got [%s], want [%s]\n' "$1" "$2" "$3"
    fi
}

# fresh OUTPUT...: a new state with these outputs, lit and showing a picture.
fresh() {
    rm -rf -- "$S"
    mkdir -p "$S"
    : > "$S/calls"
    local n
    for n in "$@"; do
        : > "$S/out.$n"
        echo true > "$S/dpms.$n"
    done
}

# run [MODE]: the script against the stubs; its output in OUT, status in RC.
run() {
    OUT=$(env PATH="$WORK/bin:$PATH" RECOVER_TEST_STATE="$S" RECOVER_DRM_DIR="$WORK/drm" \
        XDG_RUNTIME_DIR="$WORK/run" HYPRLAND_INSTANCE_SIGNATURE="$SIG" BAR_CONFIG_DIR="$WORK/bar" \
        FIX="${FIX:-}" "$SCRIPT" "$@" 2>&1)
    RC=$?
}

count() { grep -c -- "$1" "$S/calls"; }
said() { grep -qF -- "$1" <<<"$OUT" && echo yes || echo no; }

# A desktop that shows a picture: nothing is woken, relit or restarted.
fresh eDP-1
run
ok "a working desktop exits 0" "$RC" 0
ok "and no display is woken" "$(count 'ipc call screensaver')" 0
ok "or relit" "$(count 'monitor = ')" 0
ok "or the bar restarted" "$(count 'restart bar.service')" 0
ok "and nothing is reported black" "$(said 'nothing but black')" no
ok "the bar is asked whether it answers" "$([[ $(count 'ipc show') -gt 0 ]] && echo yes)" yes
ok "and reported well" "$(said 'the bar answers and is drawn on every display')" yes

# A bar gone from one display is started anew, its start limit reset first.
fresh eDP-1 HDMI-A-1
touch "$S/nobar.HDMI-A-1"
run
ok "a bar missing from a display is reported" "$(said 'the bar is not drawn on: HDMI-A-1; starting it anew')" yes
ok "and the bar restarted once" "$(count 'restart bar.service')" 1
ok "after its start limit is reset" "$(grep -e 'reset-failed bar.service$' -e 'restart bar.service' "$S/calls" | awk '{print $3}' | tr '\n' ' ')" \
    "reset-failed restart "
ok "then found back" "$(said 'the bar answers and is drawn on every display again')" yes
ok "and the run exits 0" "$RC" 0

# A bar that is not running, one a reload left not ready, one that hangs:
# each is started anew, and the report says which it was.
for kind in down notready hung; do
    case "$kind" in
        down) why="(No running instances" ;;
        notready) why="(Not ready to accept queries yet.)" ;;
        hung) why="within 3 s" ;;
    esac
    fresh eDP-1
    touch "$S/bar-$kind"
    run
    ok "a bar that is $kind is reported" "$(said "the bar does not answer over IPC $why")" yes
    ok "a bar that is $kind is restarted" "$(count 'restart bar.service')" 1
    ok "a bar that is $kind is back" "$RC" 0
done

# A bar that shows on a display a moment late is left alone.
fresh eDP-1 HDMI-A-1
touch "$S/late.HDMI-A-1"
run
ok "a bar drawn a moment late is not restarted" "$(count 'restart bar.service')" 0
ok "nor said to be missing" "$(said 'starting it anew')" no

# Outputs that are no screen of their own need no bar: one that mirrors,
# and the compositor's own stand-ins.
fresh eDP-1 HDMI-A-1
echo 1 > "$S/mirror.eDP-1"
touch "$S/nobar.eDP-1"
run
ok "a mirroring display needs no bar" "$(count 'restart bar.service')" 0
fresh eDP-1 FALLBACK
touch "$S/nobar.FALLBACK"
run
ok "nor does a synthetic output" "$(count 'restart bar.service')" 0

# A restart that does not bring it back: said, and the run fails.
fresh eDP-1 HDMI-A-1
touch "$S/nobar.HDMI-A-1" "$S/bar-stuck"
run
ok "a bar the restart does not bring back is reported" "$(said 'the bar still is not drawn on: HDMI-A-1')" yes
ok "restarted only once" "$(count 'restart bar.service')" 1
ok "and the run exits 1" "$RC" 1

# --status reports the bar but starts nothing.
fresh eDP-1
touch "$S/nobar.eDP-1"
run --status
ok "--status reports a missing bar" "$(said 'the bar is not drawn on: eDP-1')" yes
ok "and restarts nothing" "$(count 'systemctl --user restart')" 0

# The screensaver's black: waking it is enough.
fresh eDP-1
touch "$S/black.eDP-1" "$S/saver.eDP-1"
FIX=wake run
ok "the screensaver's layer is reported" "$(said "the bar's screensaver black is up on: eDP-1")" yes
ok "a black display is reported" "$(said 'lit but showing nothing but black: eDP-1')" yes
ok "the screensaver is woken" "$(count 'ipc call screensaver wake')" 1
ok "which is enough: no modeset" "$(count 'monitor = ')" 0
ok "and no bar restart" "$(count 'restart bar.service')" 0
ok "the run ends with a picture" "$RC" 0

# A black the bar cannot lift: a modeset of that display, and only that one.
fresh eDP-1 HDMI-A-1
touch "$S/black.eDP-1"
FIX=relight run
ok "the screensaver is asked first" "$(count 'ipc call screensaver wake')" 1
ok "then the black display is relit" "$(count 'monitor = "eDP-1"')" 2
ok "off first" "$(grep -o 'action = "[a-z]*", monitor = "eDP-1"' "$S/calls" | head -1)" 'action = "disable", monitor = "eDP-1"'
ok "the other display is left alone" "$(count 'monitor = "HDMI-A-1"')" 0
ok "no bar restart after a modeset that worked" "$(count 'restart bar.service')" 0
ok "and it ends with a picture" "$RC" 0

# Neither works: the bar is restarted.
fresh eDP-1
touch "$S/black.eDP-1"
FIX=bar run
ok "the bar is restarted last" "$(count 'restart bar.service')" 1
ok "after the wake and the modeset" "$(grep -e 'screensaver wake' -e 'disable' -e 'restart bar.service' "$S/calls" | awk '{print $1}' | tr '\n' ' ')" \
    "qs hyprctl systemctl "
ok "the bar's start limit is reset first" "$(count 'reset-failed bar.service$')" 1
ok "and it ends with a picture" "$RC" 0

# Nothing works: every step is tried once, and the run says so and fails.
fresh eDP-1
touch "$S/black.eDP-1"
FIX="" run
ok "an unfixable black is reported" "$(said 'still nothing but black on: eDP-1')" yes
ok "every step is tried once" "$(count 'ipc call screensaver wake') $(count 'disable') $(count 'restart bar.service')" "1 1 1"
ok "and the run exits 1" "$RC" 1

# A bar that cannot be asked is started anew before the black is looked at;
# the new one is woken, and the modeset follows as before.
fresh eDP-1
touch "$S/black.eDP-1" "$S/bar-down"
FIX=relight run
ok "a bar that does not answer is restarted first" "$(grep -e 'restart bar.service' -e 'screensaver wake' "$S/calls" | awk '{print $1}' | tr '\n' ' ')" \
    "systemctl qs "
ok "and the modeset follows" "$(count 'disable')" 1
ok "it ends with a picture" "$RC" 0

# The black was the old bar's: the new bar took it along, so nothing is woken.
fresh eDP-1
touch "$S/black.eDP-1" "$S/saver.eDP-1" "$S/bar-down"
FIX=bar run
ok "a black the new bar took with it is not woken" "$(count 'ipc call screensaver')" 0
ok "nor relit" "$(count 'disable')" 0
ok "and the run ends with a picture" "$RC" 0

# A black nothing lifts, after the bar was already started anew for another
# reason: every step is tried, but not the same restart twice.
fresh eDP-1 HDMI-A-1
touch "$S/black.eDP-1" "$S/nobar.HDMI-A-1"
FIX="" run
ok "a bar started anew is not restarted again for the black" "$(count 'restart bar.service')" 1
ok "the wake and the modeset are still tried" "$(count 'ipc call screensaver wake') $(count 'disable')" "1 1"
ok "and the black is reported" "$(said 'still nothing but black on: eDP-1')" yes

# No answer to the layer list is no verdict on the bar.
fresh eDP-1
touch "$S/layers-fail"
run
ok "a failed layer list does not restart the bar" "$(count 'restart bar.service')" 0

# One the restart does not bring back: the wake fails, the modeset still
# comes, and the bar is not restarted a second time.
fresh eDP-1
touch "$S/black.eDP-1" "$S/bar-down" "$S/bar-stuck"
FIX=relight run
ok "a bar that still does not answer is reported" "$(said 'the bar did not answer over IPC')" yes
ok "the modeset still comes" "$(count 'disable')" 1
ok "with no second restart" "$(count 'restart bar.service')" 1
ok "the picture comes back" "$(said 'every display shows a picture again')" yes
ok "but the run exits 1 for the bar" "$RC" 1

# qs warning on stderr, as with no LANG set, still answered: the bar is
# neither restarted nor said to be silent.
fresh eDP-1
touch "$S/black.eDP-1" "$S/saver.eDP-1" "$S/qs-warns"
FIX=wake run
ok "a warning from qs is no failure to answer" "$(said 'did not answer') $(said 'does not answer')" "no no"
ok "nor a reason to restart the bar" "$(count 'restart bar.service')" 0
ok "and the wake still works" "$RC" 0

# A bar from before wake: lift stands in for it.
fresh eDP-1
touch "$S/black.eDP-1" "$S/saver.eDP-1" "$S/old-bar"
FIX=wake run
ok "an older bar is asked to lift instead" "$(count 'ipc call screensaver lift 300')" 1
ok "and no modeset is needed" "$(count 'disable')" 0

# --status reads but changes nothing.
fresh eDP-1
touch "$S/black.eDP-1"
FIX=wake run --status
ok "--status reports the black" "$(said 'lit but showing nothing but black: eDP-1')" yes
ok "and wakes nothing" "$(count 'ipc call')" 0
ok "and dispatches nothing" "$(count 'dispatch')" 0

# A display with DPMS off is never captured: its screencopy never ends.
fresh eDP-1
echo false > "$S/dpms.eDP-1"
run --status
ok "an output with DPMS off is not captured" "$(count 'grim')" 0

# A session not on screen (a text console): one capture times out, then
# none is tried again for the rest of the run.
fresh eDP-1
touch "$S/hang.eDP-1"
run
ok "an unreadable display is reported" "$(said 'could not read what these show')" yes
ok "and not captured again" "$(count 'grim')" 1
ok "nor taken for black" "$(count 'ipc call screensaver')" 0

# --relight: the repairs, then a modeset of every lit display.
fresh eDP-1 HDMI-A-1
run --relight
ok "--relight relights the panel" "$(count 'disable", monitor = "eDP-1')" 1
ok "and the external" "$(count 'disable", monitor = "HDMI-A-1')" 1
ok "and leaves them lit" "$(cat "$S/dpms.eDP-1") $(cat "$S/dpms.HDMI-A-1")" "true true"
ok "--relight does not advise itself" "$(said 'recover-desktop --relight')" no

if (( failed )); then
    echo "FAIL  recover: $failed of $((passed + failed)) checks failed"
    exit 1
fi
echo "PASS  recover: $passed checks"
