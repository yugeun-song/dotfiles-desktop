#!/usr/bin/env bash
# Tests bin/recover-desktop's handling of a display that is lit but shows
# nothing but black: what it reads, and which repair it reaches for, in what
# order. Everything it talks to is a stub over files in a temporary
# directory (hyprctl, grim, qs, systemctl): no compositor, bar or user unit
# is touched. An output is a file out.NAME; dpms.NAME holds its DPMS state,
# black.NAME makes its picture black, saver.NAME puts the screensaver's
# layer on it, hang.NAME makes its capture never finish. FIX names the
# repair that clears the black: wake, relight or bar.

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
            printf '%s{"name":"%s","disabled":false,"width":2880,"height":1800,"refreshRate":120.0,"x":0,"y":0,"scale":1.5,"dpmsStatus":%s}' \
                "$sep" "$n" "$(cat "$S/dpms.$n" 2>/dev/null || echo true)"
            sep=","
        done
        printf ']\n'
        ;;
    layers)
        sep=""
        printf '{'
        for n in $(names); do
            ns='"quickshell"'
            [[ -e "$S/saver.$n" ]] && ns="$ns"'},{"namespace":"quickshell:screensaver"'
            printf '%s"%s":{"levels":{"3":[{"namespace":%s}]}}' "$sep" "$n" "$ns"
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

# qs -p PATH ipc call TARGET FUNCTION ARGS
cat > "$WORK/bin/qs" <<'EOF'
#!/usr/bin/env bash
S="$RECOVER_TEST_STATE"
echo "qs $*" >> "$S/calls"
[[ -e "$S/bar-down" ]] && { echo "No running instances for $2"; exit 255; }
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
    *"restart bar.service"*) [[ "${FIX:-}" == bar ]] && rm -f "$S"/black.* "$S"/saver.* ;;
esac
exit 0
EOF

cat > "$WORK/bin/dbus-update-activation-environment" <<'EOF'
#!/bin/sh
echo "dbus-update-activation-environment $*" >> "$RECOVER_TEST_STATE/calls"
EOF
# The script's pauses wait for real hardware; here they only cost time.
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/sleep"
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

# A bar that cannot be asked: the modeset still comes.
fresh eDP-1
touch "$S/black.eDP-1" "$S/bar-down"
FIX=relight run
ok "a bar that does not answer is reported" "$(said 'the bar did not answer over IPC')" yes
ok "and the modeset follows" "$(count 'disable')" 1
ok "it ends with a picture" "$RC" 0

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
