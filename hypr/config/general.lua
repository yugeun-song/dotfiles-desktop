-- Compositor settings: outputs, input, layout, appearance, motion.

-- Catch-all for the first frame; config/monitors.lua adds per-output rules.
-- highrr, not preferred: EDID "preferred" is often 60 Hz (2560x1440@60 on the
-- Philips here), which forced a second modeset to 144 on every start. Modesets
-- are what this GPU is least trusted with; monitors.lua asks for highrr too,
-- so its rule matches this one and costs nothing.
hl.monitor({
    output = "",
    mode = "highrr",
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
            -- The bar's foreground; transparent inactive border, so only the
            -- focused window is outlined.
            active_border = "rgba(ecf0c1ff)",
            inactive_border = "rgba(00000000)",
        },
    },

    input = {
        kb_layout = "kr",
        kb_variant = "kr104",
        follow_mouse = 1,
        -- Hover focuses without raising; raising breaks drag-and-drop.
        mouse_refocus = false,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            tap_to_click = true,
            -- An int (0..2) on 0.56; 1 is what true used to mean.
            drag_lock = 1,
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
            -- The bar is opaque; blur behind it is a wasted pass per frame.
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
        -- i915/xe expose vrr_capable on eDP and DP only; on HDMI 1 does
        -- nothing but misreport adaptive sync. Revisit on DisplayPort.
        vrr = 0,
        focus_on_activate = false,
        -- Lets a new locker attach to a session whose locker crashed. The
        -- session stays locked either way (ext-session-lock); with false the
        -- attach is denied (SessionLockManager.cpp) and there is no password
        -- field until a VT switch and kill. Unlocks nothing by itself.
        allow_session_lock_restore = true,
        -- Any input wakes DPMS-off outputs; otherwise a screen off after the
        -- lid or a suspend hides the lock prompt. monitors.lua re-arms the
        -- compositor-wide DPMS state so this does not wake a shut panel when
        -- an external is lit.
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
    },

    debug = {
        -- vfr lives under debug in this Hyprland. Off, the compositor drew at
        -- panel rate on a static screen (3,275 atomic commits/s on the input
        -- thread) for no latency gain. Cost: one slow frame after long idle.
        vfr = true,
    },

    render = {
        -- Fullscreen only; rarely engages (any subsurface, e.g. browser video,
        -- blocks it), so check directScanoutTo before assuming a saving.
        -- 2 would also require a game content type. Explicit sync is no
        -- longer an option (mesa/DRM own it).
        direct_scanout = 1,
    },

    cursor = {
        -- Tri-state: 0 use them, 1 never, 2 auto (off while tearing). Tearing
        -- is off above, so 0 and the 0.55.2 default of 2 behave the same.
        no_hardware_cursors = 0,
        enable_hyprcursor = true,
        inactive_timeout = 5,
    },

    binds = {
        -- Off: re-selecting the current workspace (a second SUPER+digit, a
        -- click on the lit chip, an extra press at an end) would bounce back.
        workspace_back_and_forth = false,
        -- Inert with back_and_forth off; kept so the pair stays together.
        allow_workspace_cycles = false,
        scroll_event_delay = 0,
        -- Off: the direction keys stay on the workspace in front of them. On,
        -- a window on the other screen's workspace is a candidate whenever
        -- its edge meets the focused one's, and at the edge focus and
        -- windows hop to the next monitor. Only direction dispatchers read
        -- this: the pointer, focus-follows-mouse and dragging still cross
        -- screens, and Super+Alt+digit sends a window to any workspace.
        window_direction_monitor_fallback = false,
    },

    -- Feel only; the gestures themselves are hl.gesture below.
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

-- gestures:workspace_swipe no longer exists; declare by fingers and direction.
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "swipe", action = "move" })

-- ---------------------------------------------------------------------------
-- Motion
-- ---------------------------------------------------------------------------
-- Speed is in tenths of a second (1.0 = 100 ms). Everything is 45-165 ms
-- except border (330 ms), which is never in the way.

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

hl.animation({ leaf = "fade",                enabled = true, speed = 1.0,  bezier = "emphasizedDecel" })
hl.animation({ leaf = "fadeIn",              enabled = true, speed = 1.0,  bezier = "emphasizedDecel" })
hl.animation({ leaf = "fadeOut",             enabled = true, speed = 0.65, bezier = "emphasizedDecel" })

hl.animation({ leaf = "border",              enabled = true, speed = 3.3,  bezier = "emphasizedDecel" })

hl.animation({ leaf = "workspaces",          enabled = true, speed = 1.65, bezier = "emphasizedDecel", style = "slide" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 1.0,  bezier = "emphasizedDecel", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 0.45, bezier = "emphasizedAccel", style = "slidevert" })

hl.animation({ leaf = "layersIn",            enabled = true, speed = 1.0,  bezier = "emphasizedDecel", style = "popin 93%" })
hl.animation({ leaf = "layersOut",           enabled = true, speed = 0.8,  bezier = "emphasizedDecel", style = "popin 95%" })

hl.animation({ leaf = "zoomFactor",          enabled = true, speed = 1.0,  bezier = "emphasizedDecel" })
