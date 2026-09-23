#!/usr/bin/env bash
# Execs the first installed polkit agent (in preference order) so systemd
# supervises it directly. None installed exits 0: nothing to restart.

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
