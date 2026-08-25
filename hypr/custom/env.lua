-- ============================================================================
-- Custom environment variables (update-safe; lives under custom/)
-- Loaded after hyprland/env.lua so any value here overrides upstream.
-- ============================================================================

-- fcitx5 — Korean input method, available the moment Hyprland is up
-- Modern setup: GTK uses native text-input-v3 (so GTK_IM_MODULE=wayland);
-- Qt uses fcitx5-qt directly (QT_IM_MODULE=fcitx); XWayland apps need
-- XMODIFIERS; SDL/GLFW/INPUT_METHOD cover games and stragglers.
hl.env("GTK_IM_MODULE",   "wayland")
hl.env("QT_IM_MODULE",    "fcitx")
hl.env("XMODIFIERS",      "@im=fcitx")
hl.env("SDL_IM_MODULE",   "fcitx")
hl.env("GLFW_IM_MODULE",  "ibus")
hl.env("INPUT_METHOD",    "fcitx")

-- Intel Arc / Lunar Lake hardware video acceleration
hl.env("LIBVA_DRIVER_NAME", "iHD")

-- Force Firefox to native Wayland (no XWayland fallback)
hl.env("MOZ_ENABLE_WAYLAND", "1")

do
    local blocked = {
        ["SUPER + J"] = true,
        ["SUPER + K"] = true,
        ["SUPER + L"] = true,
        ["SUPER + SHIFT + L"] = true,
    }
    local original = hl.bind
    hl.bind = function(keys, dispatcher, opts)
        if blocked[keys] and not (opts and opts.description and opts.description:find("%(vim%)")) then
            return
        end
        return original(keys, dispatcher, opts)
    end
end
