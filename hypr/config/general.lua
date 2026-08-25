-- Compositor settings: outputs, input, layout, appearance, motion.

-- A catch-all so an output nobody has configured still lights up at its best
-- mode. scripts/auto_monitors.sh refines this at runtime and on every
-- hotplug; this line only has to make the first frame appear.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 8,
        border_size = 3,
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
        col = {
            -- The bar's green. An inactive border that is fully transparent
            -- reads as no border at all, which is the point: only the focused
            -- window is outlined.
            active_border = "rgba(5ccc96ff)",
            inactive_border = "rgba(00000000)",
        },
    },

    input = {
        kb_layout = "kr",
        kb_variant = "kr104",
        follow_mouse = 1,
        -- Focus follows the pointer, but moving the pointer over a window
        -- does not raise it. Raising on hover makes drag-and-drop between
        -- two windows nearly impossible.
        mouse_refocus = false,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            tap_to_click = true,
            drag_lock = true,
        },
    },

    decoration = {
        rounding = 18,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        blur = {
            enabled = true,
            size = 6,
            passes = 2,
            new_optimizations = true,
            -- Blurring behind the status bar costs a full-screen pass every
            -- frame for a strip that is already opaque.
            special = false,
        },
        shadow = {
            enabled = true,
            range = 12,
            render_power = 2,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
        smart_split = false,
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        -- Variable refresh rate off. On this Intel iGPU it produces panel
        -- flicker over DisplayPort and HDMI, and it shares the code path that
        -- hangs under xe.
        vrr = 0,
        focus_on_activate = true,
        -- Nothing here restores a session lock, and a stale restore leaves
        -- an unlockable screen after a crash.
        allow_session_lock_restore = false,
    },

    debug = {
        -- vfr is under debug, not misc, in this Hyprland. Leaving it true
        -- suspends rendering when nothing changes, which saves battery and
        -- adds a frame of latency to the next event. Off, because the motion
        -- below is tuned against a panel that is always running.
        vfr = false,
    },

    render = {
        -- Same reason as vrr above: this path shares the code that hangs.
        -- Explicit sync is not configurable any more; mesa and DRM own it.
        direct_scanout = 0,
    },

    cursor = {
        no_hardware_cursors = false,
        enable_hyprcursor = true,
        inactive_timeout = 5,
    },

    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles = true,
        scroll_event_delay = 0,
    },

    -- Which gesture does what is declared with hl.gesture below; only the
    -- feel of the swipe is configured here.
    gestures = {
        workspace_swipe_distance = 400,
        workspace_swipe_cancel_ratio = 0.3,
        workspace_swipe_direction_lock = true,
        workspace_swipe_create_new = false,
    },

    xwayland = {
        force_zero_scaling = true,
    },
})

-- Touchpad gestures. The old gestures:workspace_swipe pair is gone; a gesture
-- is now declared by finger count and direction.
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "swipe", action = "move" })

-- ---------------------------------------------------------------------------
-- Motion
-- ---------------------------------------------------------------------------
-- Speeds are in tenths of a second, so these are all well under 200 ms. The
-- shape matters more than the duration: a decelerating curve puts most of the
-- movement in the first few frames, so the result is legible long before the
-- animation finishes and nothing feels like waiting.

hl.curve("emphasizedDecel", {
    type = "bezier",
    points = { { 0.05, 0.7 }, { 0.1, 1 } },
})
hl.curve("emphasizedAccel", {
    type = "bezier",
    points = { { 0.3, 0 }, { 0.8, 0.15 } },
})

hl.animation({ leaf = "windowsIn",           enabled = true, speed = 1.0,  bezier = "emphasizedDecel", style = "popin 92%" })
hl.animation({ leaf = "windowsOut",          enabled = true, speed = 0.65, bezier = "emphasizedDecel", style = "popin 96%" })
hl.animation({ leaf = "windowsMove",         enabled = true, speed = 1.0,  bezier = "emphasizedDecel", style = "slide" })

hl.animation({ leaf = "fadeIn",              enabled = true, speed = 1.0,  bezier = "emphasizedDecel" })
hl.animation({ leaf = "fadeOut",             enabled = true, speed = 0.65, bezier = "emphasizedDecel" })

hl.animation({ leaf = "border",              enabled = true, speed = 3.3,  bezier = "emphasizedDecel" })

hl.animation({ leaf = "workspaces",          enabled = true, speed = 1.65, bezier = "emphasizedDecel", style = "slide" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 1.0,  bezier = "emphasizedDecel", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 0.45, bezier = "emphasizedAccel", style = "slidevert" })

hl.animation({ leaf = "layersIn",            enabled = true, speed = 1.0,  bezier = "emphasizedDecel", style = "popin 93%" })
hl.animation({ leaf = "layersOut",           enabled = true, speed = 0.8,  bezier = "emphasizedDecel", style = "popin 95%" })

hl.animation({ leaf = "zoomFactor",          enabled = true, speed = 1.0,  bezier = "emphasizedDecel" })
