#!/usr/bin/env bash
# Locks with the input method switched to latin first. hyprlock binds no
# text-input protocol, so with fcitx5 in Hangul the field stays empty, PAM gets
# nothing, and pam_faillock counts each try.
#
# Lock paths reach this via `loginctl lock-session` -> hypridle lock_cmd; the
# power menu's suspend runs it directly. Never call hyprlock directly.
# Recovery: faillock --user "$USER" --reset   (no root needed)

set -uo pipefail

# fcitx5-remote: 0 not running, 1 inactive, 2 active. Only 2 is restored.
state() { fcitx5-remote 2>/dev/null || echo 0; }

was=$(state)

if [[ "$was" == "2" ]]; then
    fcitx5-remote -c >/dev/null 2>&1 || true

    # -c is asynchronous; wait up to 0.5 s, then lock regardless.
    for _ in $(seq 10); do
        [[ "$(state)" != "2" ]] && break
        sleep 0.05
    done

    if [[ "$(state)" == "2" ]]; then
        printf 'lock: the input method is still active; the password field may not receive keys.\n' >&2
        printf 'lock: if the unlock fails, switch to latin with the input-method key and retry.\n' >&2
    fi
fi

# Sizes per screen: see lock-fit.sh. Without its copy hyprlock reads
# hyprlock.conf, which draws the reference output's sizes on every screen.
fitted=()
if conf=$("$(dirname -- "${BASH_SOURCE[0]}")/lock-fit.sh"); then
    fitted=(-c "$conf")
fi

# The bar's key overlay drops keys from here to the unlock (hypridle's
# on_unlock_cmd); hypridle's own lock notice can come late. In the
# background, so the lock never waits on the bar.
qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar" ipc call keys lock >/dev/null 2>&1 &

hyprlock "${fitted[@]}" "$@"
rc=$?

[[ "$was" == "2" ]] && fcitx5-remote -o >/dev/null 2>&1

exit "$rc"
