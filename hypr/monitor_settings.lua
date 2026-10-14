-- The output preset, read by config/monitors.lua: the values this desktop
-- runs with, on this laptop and the next. Another machine's deviations go in
-- monitor_settings.local.lua beside this file (untracked), same fields,
-- winning over these. Every field is optional; a missing file, a load error
-- or a wrong-typed field falls back to the default with a notification.
-- Not watched: after an edit, run ./install.sh, which mirrors it and reloads.
return {
    -- Scale per display where the automatic choice is not wanted. `match` is
    -- a prefix of the description `hyprctl monitors` prints ("make model",
    -- commas dropped), so it follows the display across connectors; `output`
    -- names a connector. First match wins, local entries first.
    scales = {
        -- 14" 2880x1800 panel: 1.5 gives 1920x1200, what auto_scale below
        -- would pick too; listed so a change of the targets never moves it.
        { match = "Samsung Display Corp. 0x419D", scale = 1.5 },
        -- { output = "HDMI-A-1", scale = 1.25 },
    },

    -- For every display without an entry above: the scale, among those that
    -- keep the logical size integral, whose logical width lands nearest the
    -- target for its kind. 1920 keeps a laptop panel readable at arm's length
    -- (2880 -> 1.5, 3840 -> 2, 1920 -> 1); 2560 leaves a 1440p desk monitor
    -- at 1 and puts a 4K one at 1.5. false: scale 1 for everything unlisted.
    auto_scale = { internal = 1920, external = 2560 },

    -- The external that takes 0x0 and the workspaces when several are lit, a
    -- description prefix like `match`. Without a match or this field, the
    -- largest logical area wins, then name order.
    main = "Philips Consumer Electronics Company 27M2N5500",

    -- How workspaces spread over the outputs. "panel-first", this desktop's
    -- way: 1 on the built-in panel, 2..100 on the main external, so the panel
    -- is a side screen. "blocks" also gives each further external ten of its
    -- own (11-20, 21-30). "dynamic", Hyprland's own behaviour and the default
    -- without this field: a workspace opens where it is asked for and stays.
    -- The Displays panel (Super+O) overrides it until set back to the preset.
    workspaces = "panel-first",

    -- The panel stays on beside an external until the lid shuts. false turns
    -- it off beside any external; a keep-internal file beside this one
    -- overrides that without an edit.
    keep_internal = true,

    -- Shutting the lid with no other display lit locks the session (it is
    -- leaving the laptop); beside a lit external it only darkens the panel.
    -- false: the lid never locks.
    lock_on_lid = true,

    -- Hotplug settle windows. Removal is answered fast (the desktop is dark
    -- until the panel returns), arrival waits for link training; a burst that
    -- keeps flapping is evaluated anyway after settle_max_ms.
    -- settle_removed_ms = 400,
    -- settle_added_ms = 2000,
    -- settle_max_ms = 6000,

    -- NOT read from this file; change the defaults in config/monitors.lua.
    -- Panel-off is a separate modeset after the externals light, because one
    -- combined commit wedged the compositor with no enabled output; raise the
    -- delay if plugging a display still darkens everything.
    -- settle_synthetic_ms answers FALLBACK.
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
