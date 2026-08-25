-- ============================================================================
-- Custom autostart entries (update-safe; lives under custom/)
-- Runs after hyprland/execs.lua so dbus-update-activation-environment has
-- already populated WAYLAND_DISPLAY / XDG_CURRENT_DESKTOP into the user bus.
-- ============================================================================

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; systemctl --user start hyprland-session.target")

    -- Power profile: performance.
    -- power-profiles-daemon's polkit policy allows allow_active=yes for
    -- set-active-profile, so the active session can call this without sudo
    -- or a password prompt.
    hl.exec_cmd("powerprofilesctl set performance")

    -- fcitx5 (Korean input). Replace any stale instance left by a previous session.
    hl.exec_cmd("fcitx5 -d --replace")

    -- Auto monitor switcher: docked / undocked / external-only.
    -- The watcher applies the right profile once at boot, then re-applies on
    -- every Hyprland monitor add/remove event. Single entry point.
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/auto_monitors_watcher.sh")

    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/quickshell_keepawake_default_on.sh")

    hl.exec_cmd("$HOME/.local/bin/ii-kitty-sync")
end)
