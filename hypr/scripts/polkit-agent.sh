#!/usr/bin/env bash
# Execs the first installed polkit agent so systemd supervises it directly.
# Preference order: Hyprland's, KDE's, GNOME's, LXQt's, MATE's, each at the
# paths Arch, Debian/Ubuntu, Fedora and openSUSE give it (they differ in
# their libexec directory). None installed exits 0: nothing to restart.

set -uo pipefail

for candidate in \
    /usr/lib/hyprpolkitagent/hyprpolkitagent \
    /usr/libexec/hyprpolkitagent \
    /usr/lib/polkit-kde-authentication-agent-1 \
    /usr/libexec/polkit-kde-authentication-agent-1 \
    /usr/libexec/kf6/polkit-kde-authentication-agent-1 \
    /usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1 \
    /usr/lib/aarch64-linux-gnu/libexec/polkit-kde-authentication-agent-1 \
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
    /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
    /usr/libexec/polkit-gnome-authentication-agent-1 \
    /usr/bin/lxqt-policykit-agent \
    /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
    /usr/libexec/polkit-mate-authentication-agent-1
do
    # -f as well: a directory passes -x, and exec on one ends the script.
    [[ -f "$candidate" && -x "$candidate" ]] && exec "$candidate"
done

printf 'polkit-agent: no polkit agent is installed, privileged prompts will not appear\n' >&2
exit 0
