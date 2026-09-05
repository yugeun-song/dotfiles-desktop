#!/usr/bin/env bash
#
# Runs whichever polkit authentication agent this machine has.
#
# Any of them answers the same interface; the list is in order of preference.
# exec, so the agent is the unit's main process and systemd supervises it
# directly. A machine with none exits 0 after saying so: that is a fact about
# the machine, not a failure to restart.

set -uo pipefail

for candidate in \
    /usr/lib/hyprpolkitagent/hyprpolkitagent \
    /usr/lib/polkit-kde-authentication-agent-1 \
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
    /usr/bin/lxqt-policykit-agent
do
    [[ -x "$candidate" ]] && exec "$candidate"
done

printf 'polkit-agent: no polkit agent is installed, privileged prompts will not appear\n' >&2
exit 0
