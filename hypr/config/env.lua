-- Session environment. Set here, not in a shell profile, so it reaches
-- clients started from a launcher that never sources a shell rc.
-- Keep /etc/environment free of these: two sources for one variable drift.

-- Several toolkits still default to X11 and then run under XWayland.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

-- Qt 6 reads QSG_RHI_BACKEND, not QT_QUICK_BACKEND; the bar runs on the
-- default OpenGL RHI. Switching to Vulkan on xe is a deliberate experiment.
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- "kde" loads KDEPlasmaPlatformTheme6.so (plasma-integration); without a
-- platform theme Qt never reads kdeglobals and KDE apps draw light. Set only
-- where the plugin is installed (the GTK one as the fallback), since naming a
-- plugin that is missing makes every Qt program warn at start on a machine
-- without Plasma packages.
local qt_platform_themes = "/usr/lib/qt6/plugins/platformthemes/"
if file_exists(qt_platform_themes .. "KDEPlasmaPlatformTheme6.so") then
    hl.env("QT_QPA_PLATFORMTHEME", "kde")
elseif file_exists(qt_platform_themes .. "libqgtk3.so") then
    hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
end
-- Disabling window decoration stops Qt drawing its own title bars.
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- fcitx5 must be named per toolkit, or that toolkit cannot type Hangul. Only
-- where it is installed: the names make Qt and SDL load an input module that
-- a machine without fcitx5 does not have (a warning per program, and no
-- input method either way).
if file_exists("/usr/bin/fcitx5") then
    hl.env("XMODIFIERS", "@im=fcitx")
    hl.env("QT_IM_MODULE", "fcitx")
    -- GTK_IM_MODULE stays unset on purpose. GDK picks per backend:
    -- text-input-v3 on Wayland, the fcitx5 immodule under XWayland. =fcitx
    -- makes both paths claim the preedit; =wayland makes GTK3 load
    -- im-wayland.so on X11, where it dereferences a NULL wl_display and
    -- crashes on the first text field.
    hl.env("SDL_IM_MODULE", "fcitx")
    hl.env("GLFW_IM_MODULE", "ibus")
    -- For programs that read neither toolkit variables nor XMODIFIERS.
    hl.env("INPUT_METHOD", "fcitx")
end

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- The pointer, named only here. XCursor clients, Hyprland and GTK (via
-- scripts/gsettings-apply.sh, which reads these variables) must agree or the
-- pointer changes size between windows.
-- HYPRCURSOR_THEME names an XCursor theme on purpose: no hyprcursor theme is
-- installed, so Hyprland falls back to the same XCursor images.
-- Spaceduck-Sky is built by theme/cursor/tint-cursors.py into
-- ~/.local/share/icons. Named only when that build exists: a theme name
-- nothing resolves makes every client draw its own default pointer, while
-- an unset name lets them agree on the system default.
local cursor_theme = "Spaceduck-Sky"
local cursor_size = "24"
local data_home = os.getenv("XDG_DATA_HOME") or (HOME .. "/.local/share")
local cursor_installed = file_exists(data_home .. "/icons/" .. cursor_theme .. "/index.theme")
    or file_exists("/usr/share/icons/" .. cursor_theme .. "/index.theme")

if cursor_installed then
    hl.env("XCURSOR_THEME", cursor_theme)
    hl.env("HYPRCURSOR_THEME", cursor_theme)
end
hl.env("XCURSOR_SIZE", cursor_size)
hl.env("HYPRCURSOR_SIZE", cursor_size)

-- The VA-API driver follows the GPUs' PCI vendors, because a wrong name
-- silently disables hardware decoding instead of erroring: Intel iHD (this
-- Lunar Lake runs xe), AMD radeonsi, NVIDIA nvidia. The first card in order
-- whose driver library is actually installed wins, so a hybrid laptop whose
-- card0 is a dGPU without its VA-API driver still gets the iGPU's; a machine
-- with no known vendor is left to libva's own probing.
local function pci_vendor(card)
    local line = read_first_line("/sys/class/drm/" .. card .. "/device/vendor")
    return line and line:match("0x%x+")
end

local VA_DRIVERS = { ["0x8086"] = "iHD", ["0x1002"] = "radeonsi", ["0x10de"] = "nvidia" }
for _, card in ipairs({ "card0", "card1", "card2" }) do
    local driver = VA_DRIVERS[pci_vendor(card) or ""]
    if driver and file_exists("/usr/lib/dri/" .. driver .. "_drv_video.so") then
        hl.env("LIBVA_DRIVER_NAME", driver)
        break
    end
end

-- Hyprland 0.57 starts hyprland-session.target itself, right after importing
-- a fixed set of variables and before scripts/session-start.sh has pushed the
-- rest of this file into the user manager. Opting out keeps the start order
-- and the restart-on-relaunch logic with the script. Ignored on 0.56.
hl.env("HYPRLAND_NO_SD_TARGET", "1")
