-- Per-machine output settings, read by config/monitors.lua.
--
-- Copy to monitor_settings.lua beside it (gitignored) and edit; this file is
-- never read. Every field is optional: a missing file, a load error or a
-- wrong-typed field falls back to the default with a notification.
-- Not watched: after editing run ./install.sh, which mirrors it and reloads.
return {
    -- Scale is the one value the policy cannot derive. `match` is a prefix of
    -- the description `hyprctl monitors` prints ("make model", commas dropped),
    -- so it follows the panel across connectors; `output` names a connector.
    -- First match wins. Unlisted outputs get scale 1 at highrr.
    scales = {
        -- 14" 2880x1800 panel; 1.5 gives an effective 1920x1200.
        { match = "Samsung Display Corp. 0x419D", scale = 1.5 },
        -- { output = "HDMI-A-1", scale = 1.25 },
    },

    -- Keep the panel on beside an external. A keep-internal file beside this
    -- one does the same without editing; either is enough.
    keep_internal = false,

    -- Hotplug settle windows. Removal is answered fast (the desktop is dark
    -- until the panel returns); arrival waits for link training. A burst that
    -- keeps flapping is evaluated anyway after settle_max_ms.
    -- settle_removed_ms = 400,
    -- settle_added_ms = 2000,
    -- settle_max_ms = 6000,

    -- NOT read from this file (load_settings ignores them); change the
    -- defaults in config/monitors.lua. Panel-off is a separate modeset after
    -- the externals light, because one combined commit wedged the compositor
    -- with no enabled output; raise the delay if plugging a display still
    -- darkens everything. settle_synthetic_ms answers FALLBACK.
    -- panel_off_delay_ms = 700,
    -- panel_off_verify_ms = 900,
    -- settle_synthetic_ms = 60,

    -- After acting, check some real output is enabled; insist on the panel
    -- up to verify_limit times.
    -- verify_ms = 3000,
    -- verify_limit = 5,

    -- Lua patterns on the output name: built-in panel, compositor-synthetic.
    -- internal = { "^eDP", "^LVDS", "^DSI" },
    -- synthetic = { "^FALLBACK$", "^HEADLESS%-" },
}
