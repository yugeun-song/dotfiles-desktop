#!/usr/bin/env bash
#
# Lock the screen, with the input method out of the way first.
#
# hyprlock reads wl_keyboard directly and binds neither zwp_text_input_v3 nor
# zwp_input_method_v2. fcitx5 is the one holding the grab, through the
# compositor, and it does not let go for the lock surface. With the input
# method in Hangul the keys are composed somewhere hyprlock never sees: the
# field stays empty, PAM is handed nothing, and the log says "conversation
# failed". That counts as a failure, and pam_faillock locks the account after
# three of them.
#
# A password field is latin anyway, so switching the input method off before
# the lock appears costs nothing and removes the whole class of problem.
#
# Every path that locks this machine arrives here: the key binding calls
# loginctl lock-session, hypridle answers that signal with lock_cmd, and the
# power menu calls loginctl too. Nothing should call hyprlock directly.
#
# Recovering afterwards, if this ever bites again:
#   faillock --user "$USER" --reset      needs no root, the tally file is yours

set -uo pipefail

# fcitx5-remote with no argument reports 0 when fcitx5 is not running, 1 when
# it is running but inactive, and 2 when it is active. Only 2 is a state worth
# putting back: restoring 1 with -o would turn Hangul ON for someone who locked
# in latin mode, which is a surprise waiting on the other side of an unlock.
state() { fcitx5-remote 2>/dev/null || echo 0; }

was=$(state)

if [[ "$was" == "2" ]]; then
    fcitx5-remote -c >/dev/null 2>&1 || true

    # Verified rather than assumed. -c is asynchronous and there is no reason
    # to trust that it landed: if it did not, this locks with Hangul still on
    # and hands the user the exact failure this script exists to prevent. Half
    # a second in ten steps, then lock regardless, because a screen that does
    # not lock is worse than one that is awkward to unlock.
    for _ in $(seq 10); do
        [[ "$(state)" != "2" ]] && break
        sleep 0.05
    done

    if [[ "$(state)" == "2" ]]; then
        printf 'lock: the input method is still active; the password field may not receive keys.\n' >&2
        printf 'lock: if the unlock fails, switch to latin with the input-method key and retry.\n' >&2
    fi
fi

hyprlock "$@"
rc=$?

[[ "$was" == "2" ]] && fcitx5-remote -o >/dev/null 2>&1

exit "$rc"
