-- Per-machine output settings, read by config/monitors.lua.
--
-- Copy this file to monitor_settings.lua beside it and edit. That copy is
-- not part of the repository (.gitignore), because what it holds describes
-- one machine: which panel wants which scale, whether both screens stay on.
-- The values here are the ones in use on the laptop this repository was
-- written on, kept as a worked example; this file itself is never read.
--
-- Everything is optional. A missing file, a file that fails to load, or a
-- field of the wrong type falls back to the default named beside it, and a
-- notification says which. The result is always a working desktop: the
-- built-in panel alone, or the externals with the panel off, at scale 1.
--
-- The compositor does not watch this file. After editing it: hyprctl reload.
return {
    -- Scale per display. Scale is the one value the policy cannot derive,
    -- because it depends on how far the screen is from your eyes and not on
    -- anything the connector reports.
    --
    -- `match` is compared with what the display says about itself, "make
    -- model" as `hyprctl monitors` prints it under description, so the same
    -- panel on another connector still matches and a different panel on the
    -- same connector does not. `output` names a connector instead, for the
    -- times that is the easier thing to know. First entry to match wins.
    --
    -- Anything with no entry runs at scale 1, at the highest refresh rate it
    -- can do, then the largest resolution available at that rate.
    scales = {
        -- 14 inch 2880x1800 panel. At scale 1 the text is unreadable at
        -- arm's length; 1.5 makes it an effective 1920x1200.
        { match = "Samsung Display Corp. 0x419D", scale = 1.5 },
        -- { output = "HDMI-A-1", scale = 1.25 },
    },

    -- Both screens on when an external is attached, instead of the panel
    -- going off. Default false. A file named keep-internal beside this one
    -- means the same and can be added and removed without editing anything;
    -- either one is enough.
    keep_internal = false,

    -- Milliseconds to let a burst of hotplug events settle before acting.
    -- An output that went away is answered fast, because the desktop is
    -- dark until the panel is back (default 400). An output that arrived
    -- waits, because both screens on is harmless and a link that is still
    -- training may go away again (default 2000). Whatever is flapping, an
    -- evaluation is forced after settle_max_ms (default 6000).
    -- settle_removed_ms = 400,
    -- settle_added_ms = 2000,
    -- settle_max_ms = 6000,

    -- How long after acting to check that some real output is enabled, and
    -- how many times to insist on the panel if none is (defaults 3000, 5).
    -- verify_ms = 3000,
    -- verify_limit = 5,

    -- What counts as the built-in panel and what is the compositor's own.
    -- Lua patterns against the output name. The defaults cover every laptop
    -- connector type the kernel has; change these only for something exotic.
    -- internal = { "^eDP", "^LVDS", "^DSI" },
    -- synthetic = { "^FALLBACK$", "^HEADLESS%-" },
}
