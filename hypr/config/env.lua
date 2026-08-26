-- Environment for the session.
--
-- These are set here rather than in a shell profile because they have to
-- reach every client the compositor spawns, including ones started from a
-- launcher that never sources a shell rc.

-- Toolkits need to be told to use Wayland; several still default to X11 and
-- then run through XWayland with worse input and scaling.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

-- Moved here from /etc/environment, which was dropped because it set
-- QT_QPA_PLATFORM and LIBVA_DRIVER_NAME a second time and two sources for one
-- variable disagree the first time either changes.
--
-- Worth knowing rather than assuming: quickshell is a Qt Quick application, so
-- this decides how the bar itself is drawn, on a machine whose principal fault
-- is xe driver graphics hangs. Whether Vulkan makes that better or worse has
-- never been measured either way. If the hangs are being chased again, this is
-- one line to try removing.
hl.env("QT_QUICK_BACKEND", "vulkan")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Qt applications otherwise draw their own title bars on top of the
-- compositor's decorations.
-- Without a platform theme plugin Qt never reads kdeglobals, and a KDE
-- application draws in its own default light palette on a dark desktop.
-- kde selects KDEPlasmaPlatformTheme6.so from plasma-integration.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Korean input. fcitx5 has to be named for each toolkit separately; a client
-- that misses this shows a keyboard that cannot type Hangul at all.
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("QT_IM_MODULE", "fcitx")
-- wayland, not fcitx. GTK4 speaks text-input-v3 to the compositor, and naming
-- the fcitx immodule here puts the legacy path in front of it: the two then
-- both claim the preedit and Hangul composition breaks in GTK applications
-- while working everywhere else.
hl.env("GTK_IM_MODULE", "wayland")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")
-- For anything that reads neither the toolkit variables nor XMODIFIERS, which
-- in practice means games and a long tail of single-purpose programs.
hl.env("INPUT_METHOD", "fcitx")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- The pointer, named once.
--
-- Four consumers read this and each reads it from somewhere different:
-- XCURSOR_* for XCursor clients, HYPRCURSOR_* for Hyprland's own format, and
-- gsettings for GTK. Naming the size in three files is how the pointer ends up
-- changing size as it crosses from a GTK window to anything else, which is
-- exactly what it was doing. scripts/gsettings-apply.sh reads these variables
-- out of the environment rather than carrying its own copy, so this block is
-- the only place either value is written.
--
-- HYPRCURSOR_THEME names an XCursor theme on purpose. No hyprcursor-format
-- theme is installed, so Hyprland does not find one and falls back to XCursor,
-- which is the same set of images the other clients are using. Leaving it unset
-- would have Hyprland pick its own default instead, and the pointer would
-- differ between the compositor's own surfaces and everything else.
-- Built by theme/cursor/tint-cursors.py from Oxygen_White in the bar's sky
-- blue, into ~/.local/share/icons. If that build ever fails the name resolves
-- to nothing and every client falls back to its own default, which is visible
-- immediately rather than silently wrong.
local cursor_theme = "Spaceduck-Sky"
local cursor_size = "24"

hl.env("XCURSOR_THEME", cursor_theme)
hl.env("XCURSOR_SIZE", cursor_size)
hl.env("HYPRCURSOR_THEME", cursor_theme)
hl.env("HYPRCURSOR_SIZE", cursor_size)

-- Intel Lunar Lake uses the xe driver, not i915. VA-API lives in a different
-- package there and the wrong driver name silently disables hardware video
-- decoding rather than erroring.
hl.env("LIBVA_DRIVER_NAME", "iHD")
