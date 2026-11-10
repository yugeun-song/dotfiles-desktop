pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The colours of the bar, its widgets and every panel (the user, 2026-11-11),
// in one of four tones, chosen in modules/AppearancePanel.qml:
//   black   the bar's own palette (spaceduck, as kitty's theme), as it was;
//   white   the same roles in a warm white with the black tone's navy as text;
//   auto    black or white after the wallpaper: in its tone by default (the
//           user's call), or opposite it (`rule`);
//   custom  a background, text and accent drawn from the wallpaper, in the
//           same rule, each of which can be set by hand.
// Theme.qml takes its base colours from `palette`, so whatever is drawn from
// Theme follows. The island stays black in every tone (the user's call), and
// is lifted to grey only where it hangs over a ground too dark for it
// (islandFill). scripts/wall-tone.py reads the wallpaper once per change
// (wallpaper.sh's "wallpaper changed", a screen added or resized): nothing
// polls. Only the bar sets `active`: the lock screen and the video player
// import this too, and keep the black tone without reading a file.
Singleton {
    id: root

    property bool active: false
    // { name, width, height, bar } per screen, in logical pixels, from
    // shell.qml: Theme cannot be read here, since it reads this.
    property var screens: []

    readonly property var modes: ["black", "white", "auto", "custom"]
    readonly property var defaults: ({ mode: "black", rule: "match", custom: {} })
    property var saved: ({})
    readonly property var options: Object.assign({}, root.defaults, root.saved)
    readonly property string mode: root.active && root.modes.indexOf(root.options.mode) >= 0 ? root.options.mode : "black"
    readonly property string rule: root.options.rule === "opposite" ? "opposite" : "match"
    readonly property var custom: (root.options.custom && typeof root.options.custom === "object") ? root.options.custom : ({})

    // wall-tone.py's last answer, null before one: the tone, two palettes,
    // the picture's own colours and each screen's island fill.
    property var reading: null
    readonly property var swatches: root.reading?.swatches ?? []

    // The tone the wallpaper asks for under the rule: "light" or "dark".
    readonly property string tone: root.toneFor(root.reading, root.rule)
    readonly property var palette: root.paletteFor(root.mode, root.rule, root.custom, root.reading)

    function set(change: var): void {
        if (!root.active)
            return;
        root.saved = Object.assign({}, root.saved, change);
        store.setText(JSON.stringify(root.saved) + "\n");
    }

    function adopt(text: string): void {
        try {
            const got = JSON.parse(text);
            root.saved = got && typeof got === "object" ? got : ({});
        } catch (e) {
            if (text.trim() !== "")
                console.warn("[appearance] could not read", store.path);
        }
    }

    function setMode(name: string): void {
        if (root.modes.indexOf(name) >= 0)
            root.set({ mode: name });
    }

    function setRule(name: string): void {
        root.set({ rule: name === "opposite" ? "opposite" : "match" });
    }

    // A role's colour by hand ("#rrggbb"), or "" for the wallpaper's again.
    function setCustom(role: string, hex: string): void {
        if (["bg", "fg", "accent"].indexOf(role) < 0)
            return;
        const next = Object.assign({}, root.custom);
        if (root.validHex(hex))
            next[role] = hex.toLowerCase();
        else
            delete next[role];
        root.set({ custom: next });
    }

    function resetCustom(): void {
        root.set({ custom: {} });
    }

    // ---- colours, plain values in and out (tests/unit/qml/shell.qml) ---------
    function validHex(hex: var): bool {
        return typeof hex === "string" && /^#[0-9a-fA-F]{6}$/.test(hex);
    }

    function rgb(hex: string): color {
        return Qt.rgba(parseInt(hex.slice(1, 3), 16) / 255, parseInt(hex.slice(3, 5), 16) / 255,
                       parseInt(hex.slice(5, 7), 16) / 255, 1);
    }

    function hexOf(c: color): string {
        const two = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
        return `#${two(c.r)}${two(c.g)}${two(c.b)}`;
    }

    // In the stored values, as Qt.tint and the tokens' alphas blend.
    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    // Relative luminance and contrast, WCAG 2.
    function luminance(c: color): real {
        const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }

    function contrast(a: color, b: color): real {
        const ya = root.luminance(a), yb = root.luminance(b);
        return (Math.max(ya, yb) + 0.05) / (Math.min(ya, yb) + 0.05);
    }

    // Where dark and light text read alike: above it a ground is light.
    readonly property real crossover: 0.18

    function toneFor(reading: var, rule: string): string {
        const tone = reading?.tone === "light" ? "light" : "dark";
        return rule === "opposite" ? (tone === "light" ? "dark" : "light") : tone;
    }

    // A colour as text on a ground: as it is where it reads to `ratio`, else
    // deepened (or on a dark ground lightened) along its own hue until it
    // does: the accents, made for the black tone, are pale on the white one.
    function readable(c: color, on: color, ratio: real): color {
        let out = c;
        const up = root.luminance(on) < root.crossover;
        for (let i = 0; i < 16 && root.contrast(out, on) < ratio; i++)
            out = up ? Qt.lighter(out, 1.08) : Qt.darker(out, 1.08);
        return out;
    }

    // Text on an accent fill: the navy where it reads, else white.
    function textOn(fill: color): color {
        const ink = root.rgb("#0f111b");
        return root.contrast(fill, ink) >= 4.5 ? ink : Qt.rgba(1, 1, 1, 1);
    }

    // The black tone is the bar's palette as Theme had it, to the pixel.
    function black(): var {
        const bg = root.rgb("#0f111b");
        return {
            light: false, bg: bg, bgAlt: root.rgb("#1b1c36"), fg: root.rgb("#ecf0c1"), muted: root.rgb("#686f9a"),
            raised: Qt.lighter(bg, 1.45), raisedHover: Qt.lighter(bg, 1.9), well: Qt.darker(bg, 1.8),
            accent: root.rgb("#7aa2f7"), accentText: root.rgb("#0f111b")
        };
    }

    // The same roles in white: a warm white under the black tone's navy,
    // muted text to 5.5:1, cards lifted to plain white and pressed a shade
    // darker, the well a step under the surface. The accent is the black
    // tone's, whose navy text reads on it.
    function white(): var {
        const bg = root.rgb("#f4f4f0");
        const fg = root.rgb("#0f111b");
        const raised = Qt.rgba(1, 1, 1, 1);
        return {
            light: true, bg: bg, bgAlt: root.rgb("#e6e6e0"), fg: fg, muted: root.rgb("#5a6085"),
            raised: raised, raisedHover: root.mix(raised, fg, 0.06), well: Qt.darker(bg, 1.06),
            accent: root.rgb("#7aa2f7"), accentText: fg
        };
    }

    // Any background and text: the other roles from them, lifted the way
    // the tone lifts (lighter cards on a dark ground, white ones on a light).
    function derived(bg: color, fg: color, accent: color): var {
        const light = root.luminance(bg) > root.crossover;
        const raised = light ? root.mix(bg, Qt.rgba(1, 1, 1, 1), 0.65) : Qt.lighter(bg, 1.45);
        return {
            light: light, bg: bg, bgAlt: root.mix(bg, fg, 0.08), fg: fg, muted: root.mix(fg, bg, 0.42),
            raised: raised, raisedHover: light ? root.mix(raised, fg, 0.06) : Qt.lighter(bg, 1.9),
            well: light ? Qt.darker(bg, 1.06) : Qt.darker(bg, 1.8),
            accent: accent, accentText: root.textOn(accent)
        };
    }

    // The custom tone's three colours before any hand: the wallpaper's, or
    // the tone's own where it gave none.
    function drawn(reading: var, rule: string): var {
        const p = reading?.palettes?.[rule] ?? null;
        const base = root.toneFor(reading, rule) === "light" ? root.white() : root.black();
        return {
            bg: root.validHex(p?.bg) ? root.rgb(p.bg) : base.bg,
            fg: root.validHex(p?.fg) ? root.rgb(p.fg) : base.fg,
            accent: root.validHex(p?.accent) ? root.rgb(p.accent) : base.accent
        };
    }

    function paletteFor(mode: string, rule: string, custom: var, reading: var): var {
        if (mode === "white")
            return root.white();
        if (mode === "auto")
            return root.toneFor(reading, rule) === "light" ? root.white() : root.black();
        if (mode === "custom") {
            const d = root.drawn(reading, rule);
            const pick = role => root.validHex(custom?.[role]) ? root.rgb(custom[role]) : d[role];
            return root.derived(pick("bg"), pick("fg"), pick("accent"));
        }
        return root.black();
    }

    // ---- the island over the desktop ---------------------------------------
    // The fill where the grown island hangs below the bar on that screen:
    // wall-tone.py's for the wallpaper there, so black unless the ground is
    // too dark for it. A tiled or fullscreen window covers the wallpaper,
    // and what it shows is not read (another program's pixels), so the
    // island keeps its black over windows; a window not described yet
    // counts as covering (WidgetScreen.qml's rule).
    function islandFill(screenName: string): color {
        const hex = root.reading?.screens?.[screenName]?.island ?? "";
        if (!root.active || !root.validHex(hex) || root.covered(screenName))
            return Qt.rgba(0, 0, 0, 1);
        return root.rgb(hex);
    }

    function covered(screenName: string): bool {
        const monitor = Hyprland.monitors.values.find(m => m.name === screenName);
        const ws = monitor?.activeWorkspace ?? null;
        if (!ws)
            return true;
        if (ws.hasFullscreen)
            return true;
        for (const t of ws.toplevels?.values ?? []) {
            const ipc = t.lastIpcObject;
            if (!ipc || typeof ipc.floating !== "boolean" || !ipc.floating || (ipc.fullscreen ?? 0) > 0)
                return true;
        }
        return false;
    }

    // ---- reading the wallpaper ------------------------------------------------
    // BAR_WALLPAPER is the tests' stand-in for wallpaper.sh's picture.
    readonly property string wallpaper: Quickshell.env("BAR_WALLPAPER")
        || `${Quickshell.env("HOME") ?? ""}/Pictures/Wallpapers/current-desktop.png`

    function refresh(): void {
        if (!root.active || root.screens.length === 0)
            return;
        if (reader.running) {
            reader.again = true;
            return;
        }
        reader.running = true;
    }

    // Read at once, before the bar's first frame, so a white bar never
    // starts black: the file waits for its load (blockLoading).
    onActiveChanged: {
        if (!root.active)
            return;
        store.path = Paths.stateDir + "/appearance.json";
        root.adopt(store.text());
        settle.restart();
    }
    // Screens come and go in a burst at a plug: read once it settles.
    onScreensChanged: settle.restart()

    Timer {
        id: settle

        interval: 300
        onTriggered: root.refresh()
    }

    Process {
        id: reader

        property bool again: false

        command: ["python3", "-I", Quickshell.shellPath("scripts/wall-tone.py"), root.wallpaper]
            .concat(root.screens.map(s => `${s.name}:${s.width}:${s.height}:${s.bar}`))

        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "")
                    return;
                try {
                    const got = JSON.parse(this.text);
                    if (got && got.palettes && got.screens)
                        root.reading = got;
                } catch (e) {
                    console.warn("[appearance] wall-tone.py said something unreadable");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "")
                    console.warn("[appearance]", this.text.trim());
            }
        }
        onExited: {
            if (reader.again) {
                reader.again = false;
                reader.running = true;
            }
        }
    }

    // ---- the panel ----------------------------------------------------------
    property bool panelOpen: false
    property var panelScreen: null

    function togglePanel(screen: var): void {
        if (!root.panelOpen && !Surfaces.mayOpen("appearance"))
            return;
        if (!root.panelOpen)
            root.panelScreen = screen;
        root.panelOpen = !root.panelOpen;
    }

    // Transient, one panel at a time (services/Surfaces.qml).
    onPanelOpenChanged: Surfaces.report("appearance", root.panelOpen)

    Connections {
        target: Surfaces

        function onShut(name) {
            if (name === "appearance")
                root.panelOpen = false;
        }
    }

    // For scripts and the end-to-end tests: qs ipc call appearance mode white.
    IpcHandler {
        target: "appearance"
        enabled: root.active

        function mode(name: string): void {
            root.setMode(name);
        }
        function rule(name: string): void {
            root.setRule(name);
        }
        function custom(role: string, hex: string): void {
            root.setCustom(role, hex);
        }
        function reset(): void {
            root.resetCustom();
        }
        function refresh(): void {
            root.refresh();
        }
        function panel(): void {
            const name = Hyprland.focusedMonitor?.name ?? "";
            root.togglePanel(Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null);
        }
        function island(screen: string): string {
            return root.hexOf(root.islandFill(screen));
        }
        function state(): string {
            const p = root.palette;
            return JSON.stringify({
                mode: root.mode, rule: root.rule, custom: root.custom, tone: root.tone, read: root.reading !== null,
                palette: { bg: root.hexOf(p.bg), fg: root.hexOf(p.fg), muted: root.hexOf(p.muted), accent: root.hexOf(p.accent) }
            });
        }
    }

    // Its path is set as the bar starts (onActiveChanged). Missing until the
    // first change: the defaults then stand.
    FileView {
        id: store

        blockLoading: true
        printErrors: false
        onLoaded: root.adopt(store.text())
    }
}
