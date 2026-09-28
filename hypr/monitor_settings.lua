-- The output preset, read by config/monitors.lua. Tracked: these are the
-- values this desktop is meant to run with, on this laptop and on the next
-- one. What differs on another machine goes in monitor_settings.local.lua
-- beside this file (untracked), which takes the same fields and wins over
-- this one. Every field is optional: a missing file, a load error or a
-- wrong-typed field falls back to the default with a notification.
-- Not watched: after editing run ./install.sh, which mirrors it and reloads.
return {
    -- Scale per display where the automatic choice is not the wanted one.
    -- `match` is a prefix of the description `hyprctl monitors` prints ("make
    -- model", commas dropped), so it follows the panel across connectors;
    -- `output` names a connector. First match wins, local entries first.
    scales = {
        -- 14" 2880x1800 panel: 1.5 gives an effective 1920x1200, which is
        -- also what auto_scale below would pick; listed so a change of the
        -- targets never moves this panel.
        { match = "Samsung Display Corp. 0x419D", scale = 1.5 },
        -- { output = "HDMI-A-1", scale = 1.25 },
    },

    -- For every display without an entry above: the scale, among those that
    -- keep the logical size integral, whose logical width lands nearest the
    -- target for its kind. 1920 keeps a laptop panel readable at arm's
    -- length (2880 -> 1.5, 3840 -> 2, 1920 -> 1); 2560 leaves a 1440p desk
    -- monitor at 1 and puts a 4K one at 1.5. false means scale 1 for
    -- everything unlisted.
    auto_scale = { internal = 1920, external = 2560 },

    -- The external that takes 0x0 and the workspaces when several are lit,
    -- as a description prefix like `match` above. Without a match, or without
    -- this field, the largest logical area wins, then name order.
    main = "Philips Consumer Electronics Company 27M2N5500",

    -- How workspaces are spread over the outputs. This desktop's way is
    -- "panel-first": workspace 1 on the built-in panel, 2..100 on the main
    -- external, so the panel is a side screen. "blocks" also gives each
    -- further external ten workspaces of its own (11-20, 21-30). "dynamic" is
    -- Hyprland's own behaviour, which is what the policy does without this
    -- field: a workspace opens where it is asked for and stays there. The
    -- Displays panel (Super+O) can override this for the session.
    workspaces = "panel-first",

    -- The panel stays on beside an external, with workspace 1 on it and the
    -- rest on the external, until the lid shuts. false turns it off beside
    -- any external; a keep-internal file beside this one overrides that
    -- without editing.
    keep_internal = true,

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
