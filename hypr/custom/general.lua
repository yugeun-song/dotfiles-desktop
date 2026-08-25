-- ============================================================================
-- Custom general overrides (update-safe; lives under custom/)
-- Target: max smoothness for Intel Ultra 5 226V (Lunar Lake / Arc Battlemage)
-- Battery cost is acceptable per user preference.
-- ----------------------------------------------------------------------------
-- Dynamic monitor switching (docked / undocked / external-only) is driven by
-- custom/scripts/auto_monitors.sh, launched via custom/execs.lua.
-- The hl.monitor calls below are the BOOT-TIME defaults so the first frame
-- is already at the correct mode/scale (mirror of the legacy monitors.conf).
-- ============================================================================

hl.config({
    misc = {
        -- Variable refresh rate. 0=off, 1=on, 2=fullscreen-only.
        -- Off avoids panel-induced flicker on Intel iGPU + DisplayPort/HDMI
        -- links and gives a uniform 120/144 Hz experience.
        vrr = 0
    },
    debug = {
        -- vfr=true (default) suspends rendering when nothing changes — saves
        -- battery but adds a frame of latency to the next event. Force always-on
        -- rendering at the panel's refresh rate.
        vfr = false
    },
    render = {
        -- NOTE on explicit sync: recent Hyprland (>= 0.42 area) removed the
        -- render:explicit_sync / render:explicit_sync_kms keys — explicit sync
        -- is now always-on and handled by mesa + DRM/KMS itself, no compositor
        -- toggle. Setting them here would be silently ignored.

        -- Direct scanout disabled (2026-05-15) as part of the freeze
        -- mitigation. Direct scanout routes fullscreen opaque windows
        -- straight to the display engine, which shares the dmabuf /
        -- atomic-commit path that xe 1.x has race issues with. Going
        -- through Hyprland's compositor adds a tiny amount of latency
        -- but closes that race window.
        direct_scanout = 0
    },
    cursor = {
        -- Hardware cursors are noticeably faster on Intel; never disable.
        no_hardware_cursors = false,
        enable_hyprcursor   = true
    }
})

-- ---------------------------------------------------------------------------
-- Boot-time monitor declarations
-- ---------------------------------------------------------------------------
-- eDP-1 parks at 5000x0 from frame 0 so the 0.55.0 layout validator never
-- sees an overlap with HDMI between boot and the watcher's first park-then-
-- disable cycle. auto_monitors.sh restores eDP-1 to 0x0 in the undocked
-- branch (via hyprctl reload re-evaluating this file).
hl.monitor({output = "eDP-1",    mode = "2880x1800@120", position = "5000x0", scale = "1.5"})
-- HDMI-A-1: Philips 27M2N5500 — external 1440p, 144 Hz, 1.0x scale.
hl.monitor({output = "HDMI-A-1", mode = "2560x1440@144", position = "0x0",    scale = "1.0"})

-- ---------------------------------------------------------------------------
-- Custom curve (kept for reference / future use)
-- ---------------------------------------------------------------------------
hl.curve("softDecel", {
    type = "bezier",
    points = {{0.1, 0.9}, {0.05, 1}}
})

-- ---------------------------------------------------------------------------
-- Animations — snappy + elegant
-- Default curve: emphasizedDecel (Material 3, refined decel, lands with intent)
-- Speeds are in 10ths of a second; lower = shorter = snappier.
-- ---------------------------------------------------------------------------

-- Original speeds (rollback): 1.5 / 1.0 / 1.5 / 1.5 / 1.0 / 5 / 2.5 / 1.5 / 0.7 / 1.5 / 1.2 / 1.5
hl.animation({leaf = "windowsIn",           enabled = true, speed = 1.0, bezier = "emphasizedDecel", style = "popin 92%"})
hl.animation({leaf = "windowsOut",          enabled = true, speed = 0.65, bezier = "emphasizedDecel", style = "popin 96%"})
hl.animation({leaf = "windowsMove",         enabled = true, speed = 1.0, bezier = "emphasizedDecel", style = "slide"})

hl.animation({leaf = "fadeIn",              enabled = true, speed = 1.0, bezier = "emphasizedDecel"})
hl.animation({leaf = "fadeOut",             enabled = true, speed = 0.65, bezier = "emphasizedDecel"})

hl.animation({leaf = "border",              enabled = true, speed = 3.3, bezier = "emphasizedDecel"})

hl.animation({leaf = "workspaces",          enabled = true, speed = 1.65, bezier = "emphasizedDecel", style = "slide"})
hl.animation({leaf = "specialWorkspaceIn",  enabled = true, speed = 1.0, bezier = "emphasizedDecel", style = "slidevert"})
hl.animation({leaf = "specialWorkspaceOut", enabled = true, speed = 0.45, bezier = "emphasizedAccel", style = "slidevert"})

hl.animation({leaf = "layersIn",            enabled = true, speed = 1.0, bezier = "emphasizedDecel", style = "popin 93%"})
hl.animation({leaf = "layersOut",           enabled = true, speed = 0.8, bezier = "emphasizedDecel", style = "popin 95%"})

hl.animation({leaf = "zoomFactor",          enabled = true, speed = 1.0, bezier = "emphasizedDecel"})

hl.config({
    general = {
        border_size = 3,
        col = {
            active_border   = "rgba(5ccc96ff)",
            inactive_border = "rgba(00000000)"
        }
    }
})

hl.window_rule({
    match        = { pin = true },
    border_color = "rgba(5ccc96ff) rgba(00000000)"
})