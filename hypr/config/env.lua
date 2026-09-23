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
-- platform theme Qt never reads kdeglobals and KDE apps draw light.
-- Disabling window decoration stops Qt drawing its own title bars.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- fcitx5 must be named per toolkit, or that toolkit cannot type Hangul.
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("QT_IM_MODULE", "fcitx")
-- GTK_IM_MODULE stays unset on purpose. GDK picks per backend: text-input-v3
-- on Wayland, the fcitx5 immodule under XWayland. =fcitx makes both paths
-- claim the preedit; =wayland makes GTK3 load im-wayland.so on X11, where it
-- dereferences a NULL wl_display and crashes on the first text field.
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")
-- For programs that read neither toolkit variables nor XMODIFIERS (games etc.).
hl.env("INPUT_METHOD", "fcitx")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- The pointer, named only here. XCursor clients, Hyprland and GTK (via
-- scripts/gsettings-apply.sh, which reads these variables) must agree or the
-- pointer changes size between windows.
-- HYPRCURSOR_THEME names an XCursor theme on purpose: no hyprcursor theme is
-- installed, so Hyprland falls back to the same XCursor images.
-- Spaceduck-Sky is built by theme/cursor/tint-cursors.py into
-- ~/.local/share/icons; if missing, every client visibly uses its default.
local cursor_theme = "Spaceduck-Sky"
local cursor_size = "24"

hl.env("XCURSOR_THEME", cursor_theme)
hl.env("XCURSOR_SIZE", cursor_size)
hl.env("HYPRCURSOR_THEME", cursor_theme)
hl.env("HYPRCURSOR_SIZE", cursor_size)

-- Lunar Lake runs xe; a wrong VA-API driver name silently disables hardware
-- decoding instead of erroring.
hl.env("LIBVA_DRIVER_NAME", "iHD")
