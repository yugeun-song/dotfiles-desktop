-- Session environment, here rather than in a shell profile so clients a
-- launcher starts get it too. Keep /etc/environment free of these: two
-- sources for one variable drift.

-- Several toolkits still default to X11 and then run under XWayland.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

-- No QSG_RHI_BACKEND (Qt 6 ignores QT_QUICK_BACKEND): the bar runs on the
-- default OpenGL RHI; Vulkan on xe would be a deliberate experiment.
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Library directories by distribution, for the plugin checks below: Arch,
-- Void and Alpine use /usr/lib, Fedora, openSUSE and Gentoo /usr/lib64,
-- Debian and Ubuntu the multiarch directory.
local LIB_DIRS = { "/usr/lib/", "/usr/lib64/", "/usr/lib/x86_64-linux-gnu/", "/usr/lib/aarch64-linux-gnu/" }

local function installed_under(rest)
    for _, dir in ipairs(LIB_DIRS) do
        if file_exists(dir .. rest) then
            return true
        end
    end
    return false
end

-- "kde" loads KDEPlasmaPlatformTheme6.so (plasma-integration); without a
-- platform theme Qt never reads kdeglobals and KDE apps draw light. Named
-- only where the plugin exists (GTK's as the fallback): a missing one makes
-- every Qt program warn at start.
if installed_under("qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so") then
    hl.env("QT_QPA_PLATFORMTHEME", "kde")
elseif installed_under("qt6/plugins/platformthemes/libqgtk3.so") then
    hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
end
-- No client-side title bars from Qt under a tiling compositor.
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- fcitx5 has to be named per toolkit, or that toolkit cannot type Hangul.
-- Only where it is installed: otherwise Qt and SDL load an input module that
-- is absent (a warning per program, no input method either way).
if file_exists("/usr/bin/fcitx5") then
    hl.env("XMODIFIERS", "@im=fcitx")
    hl.env("QT_IM_MODULE", "fcitx")
    -- GTK_IM_MODULE stays unset: GDK picks per backend (text-input-v3 on
    -- Wayland, the fcitx5 immodule under XWayland). =fcitx makes both claim
    -- the preedit; =wayland makes GTK3 load im-wayland.so on X11, where it
    -- dereferences a NULL wl_display and crashes on the first text field.
    hl.env("SDL_IM_MODULE", "fcitx")
    -- kitty (GLFW) reaches fcitx5 through its ibus frontend.
    hl.env("GLFW_IM_MODULE", "ibus")
    -- For programs that read neither toolkit variables nor XMODIFIERS.
    hl.env("INPUT_METHOD", "fcitx")
end

-- The clipboard history (cliphist) in the runtime directory, a tmpfs that
-- goes at logout, not under ~/.cache: what is copied (a token, a password
-- typed out by hand) never reaches the disk, and expires within the session
-- (cliphist-expire.timer). Here, so the picker and a terminal's `cliphist`
-- read the history the watchers write.
local runtime = os.getenv("XDG_RUNTIME_DIR") or ""
if runtime:sub(1, 1) == "/" then
    hl.env("CLIPHIST_DB_PATH", runtime .. "/cliphist/db")
end

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- The pointer, named only here: XCursor clients, Hyprland and GTK (through
-- scripts/gsettings-apply.sh) must agree or it changes size between windows.
-- HYPRCURSOR_THEME names an XCursor theme on purpose: with no hyprcursor
-- theme installed Hyprland falls back to the same images. Spaceduck-Sky is
-- built by theme/cursor/tint-cursors.py into $XDG_DATA_HOME/icons and named
-- only once built: a name nothing resolves makes every client draw its own
-- default pointer, an unset one lets them agree on the system default.
local cursor_theme = "Spaceduck-Sky"
local cursor_size = "24"
-- An empty or relative XDG_DATA_HOME is ignored, as the spec says.
local data_home = os.getenv("XDG_DATA_HOME") or ""
if data_home:sub(1, 1) ~= "/" then
    data_home = HOME .. "/.local/share"
end
local cursor_installed = file_exists(data_home .. "/icons/" .. cursor_theme .. "/index.theme")
    or file_exists("/usr/share/icons/" .. cursor_theme .. "/index.theme")

if cursor_installed then
    hl.env("XCURSOR_THEME", cursor_theme)
    hl.env("HYPRCURSOR_THEME", cursor_theme)
end
hl.env("XCURSOR_SIZE", cursor_size)
hl.env("HYPRCURSOR_SIZE", cursor_size)

-- The VA-API driver follows the GPUs' PCI vendors, since a wrong name
-- silently disables hardware decoding: Intel iHD (this Lunar Lake runs xe),
-- AMD radeonsi, NVIDIA nvidia. The first card whose driver library is
-- installed wins, so a hybrid laptop whose card0 is a dGPU without its VA-API
-- driver still gets the iGPU's; an unknown vendor is left to libva's probing.
local function pci_vendor(card)
    local line = read_first_line("/sys/class/drm/" .. card .. "/device/vendor")
    return line and line:match("0x%x+")
end

local VA_DRIVERS = { ["0x8086"] = "iHD", ["0x1002"] = "radeonsi", ["0x10de"] = "nvidia" }
for _, card in ipairs({ "card0", "card1", "card2" }) do
    local driver = VA_DRIVERS[pci_vendor(card) or ""]
    -- Gentoo keeps libva's drivers in va/drivers, the rest in dri.
    if driver and (installed_under("dri/" .. driver .. "_drv_video.so")
                   or file_exists("/usr/lib64/va/drivers/" .. driver .. "_drv_video.so")) then
        hl.env("LIBVA_DRIVER_NAME", driver)
        break
    end
end

-- Hyprland 0.57 starts hyprland-session.target itself, after importing a
-- fixed set of variables and before scripts/session-start.sh has pushed the
-- rest of this file into the user manager. Opting out keeps the start order
-- and the restart-on-relaunch logic in the script. Ignored on 0.56.
hl.env("HYPRLAND_NO_SD_TARGET", "1")
