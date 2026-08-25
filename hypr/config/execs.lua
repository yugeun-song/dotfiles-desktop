-- Autostart.
--
-- Only the two things the compositor itself has to do, and one call into
-- scripts/session-autostart.sh. Nothing that spawns a long-running program
-- belongs here: Hyprland re-runs this file on every `hyprctl reload`, so a
-- program started from here is started again every time the config is
-- touched. The script checks before it starts, this file cannot.

hl.on("hyprland.start", function()
    -- The user bus is already running before the compositor exists, so it
    -- has no WAYLAND_DISPLAY. Anything D-Bus activates later -- the portal,
    -- the screenshot path, the notification daemon -- would come up with no
    -- display to talk to. Push the variables in before the session target
    -- pulls those services up.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user start hyprland-session.target")

    -- power-profiles-daemon ships allow_active=yes for set-active-profile,
    -- so the active session sets this without sudo and without a prompt.
    hl.exec_cmd("powerprofilesctl set performance")

    -- Everything with a process behind it. Idempotent; see the script header.
    hl.exec_cmd(CONFIG .. "/scripts/session-autostart.sh")
end)
