pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The desktop widgets' layout and settings (modules/WidgetDesk.qml and the
// files it uses), after the user's rules (2026-11-04):
//   - every size and place is on one grid per screen (the user, 2026-11-05:
//     a unit set by the screen's size, each widget so many units wide and
//     tall, so a layout stays easy to keep): see the grid below;
//   - no two widgets overlap: a layout carried to another shape can bring
//     two together, and the later one moves to the free place nearest;
//   - one layout mirrored on every screen by default, one per screen as the
//     option, as a duplicated display mirrors one;
//   - moved and resized only in the edit mode a key turns on (Super+Alt+W),
//     reset from the settings panel (Super+Ctrl+W); a click on a widget opens
//     its own options (2026-11-05);
//   - kept locally, in the bar's state (widgets.json), never in the
//     repository, whose defaults below stand until then and after a reset;
//   - a widget not drawn holds nothing: no window, no timer, nothing kept
//     for its return (2026-11-05), but the system widget's last minute and
//     a half, kept unread for a moment away and dropped after
//     (services/SystemReadings.qml, the same day). The window goes with the
//     last widget hidden;
//   - one widget's state is the same on every screen and workspace it shows
//     on, unless a setting says otherwise (the user, 2026-11-05): what it
//     shows comes from one service, never from a copy per screen.
Singleton {
    id: root

    // What the gallery offers, each with the sizes it is drawn at.
    readonly property var kinds: [
        { kind: "clock", title: "Clock", sizes: ["small", "medium"] },
        { kind: "calendar", title: "Calendar", sizes: ["small", "medium", "large"] },
        { kind: "weather", title: "Weather", sizes: ["small", "medium"] },
        { kind: "system", title: "System", sizes: ["small", "medium", "large"] }
    ]
    readonly property var sizeNames: ({ small: "S", medium: "M", large: "L" })

    // The grid. One cell is a small widget: a share of the screen's shorter
    // side, an eighth, since 0.15 looked a little large (the user,
    // 2026-11-05), the side no more than the laptop panel's (panelShort) at
    // the bar's fit. A larger screen thus draws the widgets in the panel's
    // pixels, as it draws the bar (the user, the same day: on the desk
    // monitor an eighth of its own side drew them a fifth larger than the
    // panel does, beside a bar of the panel's pixels); a smaller one draws
    // them smaller, so the layout still fits it. A medium one spans two cells
    // and the gap between them, a large one two by two, so a mixed layout
    // lines up. The gap, between cells and from the screen's edges and the
    // bar, is a share of the cell: 16 to 170, a little shorter than the 20
    // before (the user, 2026-11-05). A widget's content is drawn in the
    // reference pixels of a 170 px cell and scaled to the card (WidgetCard).
    readonly property var spans: ({ small: [1, 1], medium: [2, 1], large: [2, 2] })
    readonly property int smallRef: 170
    readonly property real share: 0.125
    readonly property int panelShort: 1200
    readonly property int gapRef: 16

    // Each kind's options as a new widget has them.
    readonly property var optionDefaults: ({
        clock: { hours24: true },
        calendar: { mondayFirst: true },
        weather: {},
        system: { cpu: true, memory: true, network: true, gpu: true, vram: true, battery: true, disk: true, tmpfs: true }
    })

    // Where a desktop's widgets start, the user's own layout (2026-11-05):
    // the month on top, the weather and the clock side by side under it, the
    // machine under them, all at the top left; the month and the machine
    // large, the month's days as large as the card allows and the machine's
    // nine rows (the same day). Earlier ones keep their place when
    // another shape of screen brings two together (resolve).
    readonly property var defaults: ({
        mode: "mirror",
        layout: [
            { id: "calendar", kind: "calendar", size: "large", col: 0, row: 0 },
            { id: "weather", kind: "weather", size: "small", col: 0, row: 2 },
            { id: "clock", kind: "clock", size: "small", col: 1, row: 2 },
            { id: "system", kind: "system", size: "large", col: 0, row: 3 }
        ]
    })

    property string mode: root.defaults.mode
    property var layout: root.defaults.layout
    property var screens: ({})
    // Until the file has been read, nothing is drawn: drawing the defaults
    // first moved every widget a moment later.
    property bool loaded: false

    property bool editing: false
    property bool settingsOpen: false
    // The widget whose options are open: { screen, id }, or null.
    property var optionsTarget: null

    function toggleEditing(): void {
        if (!root.editing && !Surfaces.mayOpen("widgetEditor"))
            return;
        root.editing = !root.editing;
    }

    function toggleSettings(): void {
        if (!root.settingsOpen && !Surfaces.mayOpen("widgetSettings"))
            return;
        root.settingsOpen = !root.settingsOpen;
    }

    function openOptions(screen: string, id: string): void {
        if (!Surfaces.mayOpen("widgetOptions"))
            return;
        root.optionsTarget = { screen: screen, id: id };
    }

    function closeOptions(): void {
        root.optionsTarget = null;
    }

    // The editor is a window as the Displays panel is: the settings open over
    // it and give it the keys back (Surfaces.qml); settings and a widget's
    // options are transient.
    onEditingChanged: {
        if (root.editing)
            root.optionsTarget = null;
        Surfaces.report("widgetEditor", root.editing);
    }
    onSettingsOpenChanged: Surfaces.report("widgetSettings", root.settingsOpen)
    onOptionsTargetChanged: Surfaces.report("widgetOptions", root.optionsTarget !== null)

    Connections {
        target: Surfaces

        function onShut(name) {
            if (name === "widgetEditor")
                root.editing = false;
            else if (name === "widgetSettings")
                root.settingsOpen = false;
            else if (name === "widgetOptions")
                root.optionsTarget = null;
        }
    }

    // ---- geometry ----------------------------------------------------------
    // A screen's grid: the cell, the gap and their pitch, the area inside the
    // margins (a gap from every edge, the bar's included), and how many
    // whole cells it holds each way.
    function grid(W: real, H: real, top: real): var {
        const side = Math.min(W, H, root.panelShort * Theme.fit({ width: W, height: H }));
        const cell = Math.max(1, Math.round(side * root.share));
        const gap = Math.max(1, Math.round(cell * root.gapRef / root.smallRef));
        const pitch = cell + gap;
        const x0 = gap;
        const x1 = W - gap;
        const y0 = top + gap;
        const y1 = H - gap;
        return {
            cell: cell,
            gap: gap,
            pitch: pitch,
            x0: x0,
            x1: x1,
            y0: y0,
            y1: y1,
            cols: Math.max(0, Math.floor((x1 - x0 + gap) / pitch)),
            rows: Math.max(0, Math.floor((y1 - y0 + gap) / pitch))
        };
    }

    // Reference pixels to a screen's: the cell to the reference cell.
    function scaleFor(W: real, H: real): real {
        return root.grid(W, H, 0).cell / root.smallRef;
    }

    function spanOf(size: string): var {
        return root.spans[size] ?? root.spans.small;
    }

    // n cells and the gaps between them.
    function extent(g: var, n: int): real {
        return n * g.cell + (n - 1) * g.gap;
    }

    // A place, as kept: a column or row from the left or top from 0, from
    // the right or bottom below 0, -1 flush with that edge. Counted from
    // both ends, a widget put at an edge stays there on a screen of another
    // width, and the margin is one gap on both sides, whatever room the
    // whole cells leave over in the middle.
    function along(start: real, end: real, g: var, index: int, n: int): real {
        return index >= 0 ? start + index * g.pitch : end - root.extent(g, n) - (-index - 1) * g.pitch;
    }

    // The nearest place a span of n fits in count cells, from the same end.
    function fitIndex(index: int, count: int, n: int): int {
        const last = Math.max(0, count - n);
        return index >= 0 ? Math.min(index, last) : Math.max(index, -(last + 1));
    }

    // A rect at a place on grid g.
    function placed_(it: var, g: var, col: int, row: int): var {
        const s = root.spanOf(it.size);
        const c = root.fitIndex(col, g.cols, s[0]);
        const r = root.fitIndex(row, g.rows, s[1]);
        return Object.assign({}, it, {
            col: c,
            row: r,
            x: root.along(g.x0, g.x1, g, c, s[0]),
            y: root.along(g.y0, g.y1, g, r, s[1]),
            w: root.extent(g, s[0]),
            h: root.extent(g, s[1])
        });
    }

    // The layout a screen shows: its own in per-screen mode once it has one.
    function itemsFor(name: string): var {
        if (root.mode === "screens" && Array.isArray(root.screens[name]))
            return root.screens[name];
        return root.layout;
    }

    // Every list a present screen shows; the shared one when none is known.
    function shownLists(): var {
        const names = Quickshell.screens.map(s => s.name);
        return names.length > 0 ? names.map(n => root.itemsFor(n)) : [root.layout];
    }

    // Whether any screen shows a widget of this kind now.
    function placed(kind: string): bool {
        return root.shownLists().some(list => list.some(it => it.kind === kind));
    }

    // Closer than a gap counts: neighbours on the grid are exactly one apart.
    function overlaps(a: var, b: var, gap: real): bool {
        return a.x < b.x + b.w + gap && b.x < a.x + a.w + gap
            && a.y < b.y + b.h + gap && b.y < a.y + a.h + gap;
    }

    // In order: a rect that meets one placed before it goes to the free place
    // nearest where it was, counted from whichever ends are nearest; one
    // with no free place stays where it is.
    function resolve(rects: var, g: var): var {
        const placed = [];
        for (const r of rects) {
            if (!placed.some(p => root.overlaps(r, p, g.gap))) {
                placed.push(r);
                continue;
            }
            const s = root.spanOf(r.size);
            const cols = [];
            const rows = [];
            for (let i = 0; i <= g.cols - s[0]; i++)
                cols.push(i, -(i + 1));
            for (let i = 0; i <= g.rows - s[1]; i++)
                rows.push(i, -(i + 1));
            let best = null;
            let bestDistance = Infinity;
            for (const row of rows) {
                for (const col of cols) {
                    const c = root.placed_(r, g, col, row);
                    if (placed.some(p => root.overlaps(c, p, g.gap)))
                        continue;
                    const d = (c.x - r.x) * (c.x - r.x) + (c.y - r.y) * (c.y - r.y);
                    if (d < bestDistance) {
                        bestDistance = d;
                        best = c;
                    }
                }
            }
            placed.push(best ?? r);
        }
        return placed;
    }

    // The rects on a screen of W x H whose bar takes `top`: each widget at
    // its place on the screen's grid, overlaps resolved.
    function rects(items: var, W: real, H: real, top: real): var {
        if (W <= 0 || H <= 0)
            return [];
        const g = root.grid(W, H, top);
        const out = [];
        for (const it of items ?? []) {
            out.push(root.placed_({ id: it.id, kind: it.kind, size: it.size, options: root.optionsOf(it) },
                                  g, it.col, it.row));
        }
        return root.resolve(out, g);
    }

    // ---- editing -----------------------------------------------------------
    // Every edit names the screen it was made on: in mirror mode it changes
    // the one layout every screen shows, else that screen's own, begun as a
    // copy of the shared one.
    function editable(name: string): var {
        return JSON.parse(JSON.stringify(root.itemsFor(name)));
    }

    function commit(name: string, items: var): void {
        if (root.mode === "screens") {
            const next = Object.assign({}, root.screens);
            next[name] = items;
            root.screens = next;
        } else {
            root.layout = items;
        }
        root.save();
    }

    // The place nearest a rect at x, y: counted from the right when its
    // middle is in the screen's right half, from the bottom in the lower
    // half, so it snaps flush to the nearer edge.
    function nearest(g: var, x: real, y: real, w: real, h: real, W: real, H: real, top: real): var {
        const fromRight = x + w / 2 > W / 2;
        const fromBottom = y + h / 2 > (top + H) / 2;
        return {
            col: fromRight ? -(Math.round((g.x1 - (x + w)) / g.pitch) + 1) : Math.round((x - g.x0) / g.pitch),
            row: fromBottom ? -(Math.round((g.y1 - (y + h)) / g.pitch) + 1) : Math.round((y - g.y0) / g.pitch)
        };
    }

    // Where a widget let go at x, y (screen pixels) lands: the nearest place
    // on the grid, or the free one nearest that, the others where they were.
    function landing(name: string, id: string, x: real, y: real, W: real, H: real, top: real): var {
        const g = root.grid(W, H, top);
        const current = root.rects(root.itemsFor(name), W, H, top);
        const moved = current.find(r => r.id === id);
        if (!moved)
            return null;
        const at = root.nearest(g, x, y, moved.w, moved.h, W, H, top);
        const snapped = root.placed_(moved, g, at.col, at.row);
        const others = current.filter(r => r.id !== id);
        return root.resolve(others.concat([snapped]), g).find(r => r.id === id) ?? snapped;
    }

    // Kept as its place on the grid.
    function place(name: string, id: string, x: real, y: real, W: real, H: real, top: real): void {
        const final = root.landing(name, id, x, y, W, H, top);
        if (!final)
            return;
        const items = root.editable(name);
        const at = items.find(it => it.id === id);
        at.col = final.col;
        at.row = final.row;
        at.moved = true;
        root.commit(name, items);
    }

    function resize(name: string, id: string, size: string, W: real, H: real, top: real): void {
        const items = root.editable(name);
        const at = items.find(it => it.id === id);
        const info = root.kinds.find(k => k.kind === at?.kind);
        if (!at || !info || info.sizes.indexOf(size) === -1)
            return;
        at.size = size;
        // Its new size may reach a neighbour: where it lands is kept.
        const landed = root.rects(items, W, H, top).find(r => r.id === id);
        if (landed) {
            at.col = landed.col;
            at.row = landed.row;
        }
        at.moved = true;
        root.commit(name, items);
    }

    function remove(name: string, id: string): void {
        root.commit(name, root.editable(name).filter(it => it.id !== id));
    }

    // A new widget, at the free place nearest the screen's top left.
    function add(name: string, kind: string, W: real, H: real, top: real): void {
        const info = root.kinds.find(k => k.kind === kind);
        if (!info)
            return;
        const items = root.editable(name);
        const id = `${kind}-${Date.now()}`;
        items.push({ id: id, kind: kind, size: info.sizes[0], col: 0, row: 0, moved: true });
        const landed = root.rects(items, W, H, top).find(r => r.id === id);
        const at = items.find(it => it.id === id);
        at.col = landed.col;
        at.row = landed.row;
        root.commit(name, items);
    }

    function setMode(mode: string): void {
        if (mode !== "mirror" && mode !== "screens")
            return;
        root.mode = mode;
        root.save();
    }

    // ---- a widget's options ----------------------------------------------
    function item(name: string, id: string): var {
        return root.itemsFor(name).find(it => it.id === id) ?? null;
    }

    // Its options with its kind's defaults under them.
    function optionsOf(it: var): var {
        const base = root.optionDefaults[it?.kind] ?? {};
        return Object.assign({}, base, it?.options ?? {});
    }

    function setOptions(name: string, id: string, patch: var): bool {
        const items = root.editable(name);
        const at = items.find(it => it.id === id);
        if (!at)
            return false;
        const next = root.validOptions(at.kind, Object.assign({}, root.optionsOf(at), patch));
        if (next === null)
            return false;
        at.options = next;
        root.commit(name, items);
        return true;
    }

    // A kind's options as kept, or null for a kind there is not: every
    // option is a switch, unknown keys are dropped.
    function validOptions(kind: string, o: var): var {
        const base = root.optionDefaults[kind];
        if (base === undefined || !o || typeof o !== "object")
            return null;
        const out = {};
        for (const key of Object.keys(base))
            out[key] = typeof o[key] === "boolean" ? o[key] : base[key];
        return out;
    }

    // Back to what the repository gives: the file is removed, so a later
    // change to the defaults reaches this machine too.
    function reset(everything: bool): void {
        root.optionsTarget = null;
        root.layout = root.defaults.layout;
        root.screens = ({});
        if (everything) {
            root.mode = root.defaults.mode;
            Quickshell.execDetached(["rm", "-f", "--", store.path]);
            return;
        }
        root.save();
    }

    // ---- the file ----------------------------------------------------------
    function save(): void {
        store.setText(JSON.stringify({
            version: 2,
            mode: root.mode,
            layout: root.layout,
            screens: root.screens
        }, null, 2) + "\n");
    }

    // Version 1 kept a place as shares of the screen: read on the reference
    // screen (2560x1440), whose grid the shares were mostly set on, and
    // taken to the nearest place there.
    function fromShares(x: real, y: real, size: string): var {
        const W = 2560;
        const H = 1440;
        const top = Math.ceil(Theme.barHeight * Theme.fit({ width: W, height: H }));
        const g = root.grid(W, H, top);
        const s = root.spanOf(size);
        return root.nearest(g, x * W, y * H, root.extent(g, s[0]), root.extent(g, s[1]), W, H, top);
    }

    // A widget as kept, or null: a kind, a size it is drawn at, a place on
    // the grid, options of its kind. Anything else in the file is dropped,
    // not drawn; options that are not its kind's fall back to the defaults.
    // One the user has not moved or resized stands where, and as large as,
    // the defaults put its id, so a change to the defaults reaches it; its
    // options stay its own.
    function validItem(it: var): var {
        if (!it || typeof it.id !== "string" || it.id === "" || it.id.length > 64)
            return null;
        const info = root.kinds.find(k => k.kind === it.kind);
        if (!info || info.sizes.indexOf(it.size) === -1)
            return null;
        const home = it.moved === true ? null : root.defaults.layout.find(d => d.id === it.id && d.kind === it.kind) ?? null;
        const size = home ? home.size : it.size;
        let at = null;
        if (home)
            at = { col: home.col, row: home.row };
        else if (Number.isInteger(it.col) && Number.isInteger(it.row))
            at = { col: it.col, row: it.row };
        else if (typeof it.x === "number" && typeof it.y === "number" && isFinite(it.x) && isFinite(it.y))
            at = root.fromShares(Math.max(0, Math.min(1, it.x)), Math.max(0, Math.min(1, it.y)), size);
        if (!at)
            return null;
        const bound = v => Math.max(-64, Math.min(63, v));
        const out = { id: it.id, kind: it.kind, size: size, col: bound(at.col), row: bound(at.row) };
        if (it.moved === true)
            out.moved = true;
        if (it.options && typeof it.options === "object") {
            const options = root.validOptions(it.kind, Object.assign({}, root.optionDefaults[it.kind], it.options));
            if (options !== null)
                out.options = options;
        }
        return out;
    }

    function adopt(text: string): void {
        let kept = null;
        try {
            kept = JSON.parse(text);
        } catch (e) {
            console.warn("[widgets] the settings file is not JSON; the defaults stand");
        }
        if (kept && typeof kept === "object") {
            if (kept.mode === "mirror" || kept.mode === "screens")
                root.mode = kept.mode;
            if (Array.isArray(kept.layout))
                root.layout = kept.layout.map(root.validItem).filter(it => it !== null);
            if (kept.screens && typeof kept.screens === "object") {
                const screens = {};
                for (const name of Object.keys(kept.screens)) {
                    if (Array.isArray(kept.screens[name]))
                        screens[name] = kept.screens[name].map(root.validItem).filter(it => it !== null);
                }
                root.screens = screens;
            }
        }
        root.loaded = true;
    }

    FileView {
        id: store

        path: Paths.stateDir + "/widgets.json"
        // Missing until the first change: the defaults then stand.
        printErrors: false
        onLoaded: root.adopt(store.text())
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[widgets] could not read", store.path, "-", error);
            root.loaded = true;
        }
        onSaveFailed: error => console.warn("[widgets] could not keep the layout in", store.path, "-", error)
    }
}
