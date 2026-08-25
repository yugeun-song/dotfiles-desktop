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
# Recovering afterwards, if this ever bites again:
#   faillock --user "$USER" --reset      needs no root, the tally file is yours

set -uo pipefail

# 0 means the input method was already inactive, and then there is nothing to
# put back afterwards.
was=$(fcitx5-remote 2>/dev/null || echo 0)

fcitx5-remote -c >/dev/null 2>&1 || true

hyprlock "$@"
rc=$?

# Only if it was on. Turning it on for someone who had it off would be a
# surprise waiting on the other side of an unlock.
if [[ "$was" != "0" ]]; then
    fcitx5-remote -o >/dev/null 2>&1 || true
fi

exit "$rc"
