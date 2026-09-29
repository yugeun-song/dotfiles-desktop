pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// Display settings: which outputs are on, at what mode, scale and rotation,
// and how the built-in panel sits beside an external. It edits the override
// file hypr/config/monitors.lua reads (see the header there); the policy
// keeps the last word, so nothing chosen here can leave every screen dark.
// Writes go through hypr/scripts/monitor-override.sh, which validates the
// lines, keeps the previous file for a revert and asks the compositor to
// re-evaluate. This file never touches the state directory itself.
Scope {
    id: root

    property bool open: false

    function toggle() {
        if (root.open)
            root.close();
        else
            root.show();
    }

    function show() {
        root.error = "";
        root.hint = "";
        root.menuOpen = false;
        root.resetPendingOnLoad = true;
        root.refresh();
        root.open = true;
    }

    function close() {
        root.menuOpen = false;
        root.open = false;
    }

    // The shell's own directory is not where the script lives.
    readonly property string script: Paths.hyprScripts + "/monitor-override.sh"

    // ---- what the compositor has ----------------------------------------
    // Outputs as `hyprctl monitors all` lists them, enabled ones first by x
    // then y so the numbers follow the desk left to right, disabled ones
    // after. Each: { name, description, internal, disabled, width, height,
    // refresh, scale, x, y, transform, mirrorOf, modes: [{ key, label, w,
    // h, r }] }.
    property var outputs: []
    property string error: ""
    property string hint: ""
    property bool scriptMissing: false
    property bool busy: false
    property int selected: 0

    // The file's lines, [selector, field, value], as last read.
    property var rawOverrides: []

    // Edits waiting for Apply, keyed by output name: { enabled, mode, scale,
    // transform, side, mirror }, every value a string; a missing key means
    // automatic, i.e. whatever the policy decides.
    property var pending: ({})

    // Set when opening and after an apply: the next complete read replaces
    // the pending edits. Not on a hotplug refresh, which must not discard
    // what the user is in the middle of choosing.
    property bool resetPendingOnLoad: true
    property bool monitorsFresh: false
    property bool overridesFresh: false

    readonly property var externals: root.outputs.filter(o => !o.internal)
    readonly property var panel: root.outputs.find(o => o.internal) ?? null
    readonly property var current: root.selected < root.outputs.length ? root.outputs[root.selected] : null

    // One test for the whole bar (and the same as config/monitors.lua), so the
    // brightness key and this panel cannot disagree on what the panel is.
    function isInternal(name) {
        return Brightness.isInternal(name);
    }

    // hyprctl prints modes as "2560x1440@144.00Hz".
    function parseMode(text) {
        const m = String(text).match(/^(\d+)x(\d+)@([\d.]+)/);
        if (!m)
            return null;
        return { w: Number(m[1]), h: Number(m[2]), r: Number(m[3]) };
    }

    // The value written to the file; two decimals as hyprctl prints them.
    function modeKey(mode) {
        return `${mode.w}x${mode.h}@${mode.r.toFixed(2)}`;
    }

    // 59.94 and 60.00 both round to 60, so decimals stay when they carry a
    // difference.
    function modeLabel(mode) {
        const r = Math.round(mode.r * 100) / 100;
        const hz = Number.isInteger(r) ? String(r) : r.toFixed(2);
        return `${mode.w} x ${mode.h}  ${hz} Hz`;
    }

    // ---- reading ----------------------------------------------------------

    function refresh() {
        root.monitorsFresh = false;
        root.overridesFresh = false;
        // A slow hyprctl must not be started twice; the running one answers.
        if (!monitorsProc.running)
            monitorsProc.running = true;
        if (!showProc.running)
            showProc.running = true;
        if (!statusProc.running)
            statusProc.running = true;
    }

    // The workspace scheme in force comes from the policy itself: the file
    // alone cannot say what the preset chose or which external is main.
    property string schemeNow: ""
    property string schemeSource: ""
    property string schemePreset: ""
    property string mainName: ""

    Process {
        id: statusProc

        command: ["hyprctl", "repl", "return MONITORS.status()"]

        stdout: StdioCollector {
            onStreamFinished: root.parseStatus(this.text)
        }
    }

    // "key=value" tokens, as MONITORS.status() prints them.
    function parseStatus(text) {
        const map = {};
        for (const token of String(text).trim().split(/\s+/)) {
            const at = token.indexOf("=");
            if (at > 0)
                map[token.slice(0, at)] = token.slice(at + 1);
        }
        root.schemeNow = map.workspaces ?? "";
        root.schemeSource = map.source ?? "";
        root.schemePreset = map.preset ?? "";
        root.mainName = map.main && map.main !== "-" ? map.main : "";
    }

    // The compositor's list settles a moment after a rule is applied, and
    // after a hotplug burst.
    Timer {
        id: refreshLater

        interval: 1500
        onTriggered: root.refresh()
    }

    Process {
        id: monitorsProc

        command: ["hyprctl", "monitors", "all", "-j"]

        stdout: StdioCollector {
            onStreamFinished: root.parseMonitors(this.text)
        }

        onExited: code => {
            if (code !== 0)
                root.error = `hyprctl monitors failed (exit ${code})`;
        }
    }

    // Exit 3 marks a missing script (not installed yet) apart from a failing
    // one, and a missing script must not read as "no overrides".
    Process {
        id: showProc

        command: ["sh", "-c", "if [ -x \"$1\" ]; then exec \"$1\" show; else exit 3; fi", "_", root.script]

        stdout: StdioCollector {
            onStreamFinished: root.parseOverrides(this.text)
        }

        onExited: code => {
            root.scriptMissing = code === 3;
            if (code === 3)
                root.hint = "monitor-override.sh is not installed; run ./install.sh";
        }
    }

    function parseMonitors(text) {
        let parsed = [];
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            root.error = "could not read the compositor's output list";
            root.monitorsFresh = true;
            return;
        }
        if (!Array.isArray(parsed))
            parsed = [];
        const list = [];
        for (const m of parsed) {
            if (!m || typeof m.name !== "string")
                continue;
            // The compositor's own outputs, as policy.synthetic in monitors.lua.
            if (/^(FALLBACK$|HEADLESS-)/.test(m.name))
                continue;
            const modes = [];
            const seen = {};
            const available = Array.isArray(m.availableModes) ? m.availableModes : [];
            for (const s of available) {
                const mode = root.parseMode(s);
                if (!mode)
                    continue;
                const key = root.modeKey(mode);
                if (seen[key])
                    continue;
                seen[key] = true;
                modes.push({ key: key, label: root.modeLabel(mode), w: mode.w, h: mode.h, r: mode.r });
            }
            list.push({
                name: m.name,
                id: Number(m.id),
                // Commas dropped: the selector format monitors.lua matches on.
                description: String(m.description ?? "").replace(/,/g, "").trim(),
                internal: root.isInternal(m.name),
                disabled: m.disabled === true,
                width: Number(m.width) || 0,
                height: Number(m.height) || 0,
                refresh: Number(m.refreshRate) || 0,
                scale: Number(m.scale) || 1,
                x: Number(m.x) || 0,
                y: Number(m.y) || 0,
                transform: Number(m.transform) || 0,
                // hyprctl gives the mirrored output's numeric id, not its
                // name; resolved to a name below once every output is known.
                mirrorOfId: typeof m.mirrorOf === "string" && m.mirrorOf !== "none" ? Number(m.mirrorOf) : NaN,
                mirrorOf: "",
                modes: modes
            });
        }
        for (const o of list) {
            if (Number.isNaN(o.mirrorOfId))
                continue;
            const target = list.find(other => other.id === o.mirrorOfId);
            o.mirrorOf = target ? target.name : String(o.mirrorOfId);
        }
        list.sort((a, b) => (a.disabled - b.disabled) || (a.x - b.x) || (a.y - b.y) || a.name.localeCompare(b.name));
        root.outputs = list;
        root.error = "";
        if (root.selected >= list.length)
            root.selected = 0;
        root.monitorsFresh = true;
        root.maybeResetPending();
    }

    function parseOverrides(text) {
        const lines = [];
        for (const raw of String(text).split("\n")) {
            const line = raw.replace(/\r$/, "");
            if (line.trim() === "" || line.startsWith("#"))
                continue;
            const parts = line.split("\t");
            if (parts.length < 3)
                continue;
            lines.push([parts[0], parts[1], parts.slice(2).join("\t")]);
        }
        root.rawOverrides = lines;
        root.overridesFresh = true;
        root.maybeResetPending();
    }

    function maybeResetPending() {
        if (!root.resetPendingOnLoad || !root.monitorsFresh || !root.overridesFresh)
            return;
        root.resetPendingOnLoad = false;
        root.pending = root.currentMap();
        root.pendingScheme = root.currentScheme;
        root.pendingSaver = root.currentSaverMap();
    }

    // ---- the screensaver (services/Screensaver.qml's file) ------------
    // Minutes per connector, 0 for off. Pending like the fields above and
    // written by Apply, so the panel has one way of taking a change; the
    // countdown does not cover it, since a screensaver time is nothing a
    // screen can fail to show.
    property var pendingSaver: ({})
    // The last number a display had while on, so the switch brings it back.
    property var saverMemory: ({})

    function currentSaverMap() {
        const map = {};
        for (const o of root.outputs)
            map[o.name] = Screensaver.minutesOf(o.name, o.description);
        return map;
    }

    function saverKey(map) {
        return root.outputs.map(o => `${o.name}=${map[o.name] ?? 0}`).join(" ");
    }

    readonly property string currentSaverKey: root.saverKey(root.currentSaverMap())
    readonly property string pendingSaverKey: root.saverKey(root.pendingSaver)
    readonly property bool saverDirty: root.pendingSaverKey !== root.currentSaverKey

    function setSaver(name, minutes) {
        const next = Object.assign({}, root.pendingSaver);
        next[name] = minutes;
        root.pendingSaver = next;
        if (minutes > 0) {
            const memory = Object.assign({}, root.saverMemory);
            memory[name] = minutes;
            root.saverMemory = memory;
        }
        root.hint = "";
    }

    function applySaver() {
        const changes = [];
        for (const o of root.outputs) {
            const want = root.pendingSaver[o.name] ?? 0;
            if (want === Screensaver.minutesOf(o.name, o.description))
                continue;
            // The selector the overrides use for this output; the other
            // forms are dropped so one line speaks for it. Twins (a shared
            // description) keep theirs.
            const aliases = ["name:" + o.name];
            if (o.description !== "" && !root.sharedDescription(o.description))
                aliases.push(o.description);
            changes.push({ selector: root.selectorFor(o), minutes: want, aliases: aliases });
        }
        if (changes.length > 0)
            Screensaver.setMany(changes);
    }

    // ---- the workspace scheme (the file's "*" line) --------------------
    // "auto" means no line: the preset decides.
    readonly property string currentScheme: {
        const line = root.rawOverrides.find(l => l[0] === "*" && l[1] === "workspaces");
        return line ? line[2] : "auto";
    }
    property string pendingScheme: "auto"

    readonly property var schemes: [
        { id: "auto",        label: "Preset" },
        { id: "panel-first", label: "Panel first" },
        { id: "blocks",      label: "Blocks of ten" },
        { id: "dynamic",     label: "Dynamic" }
    ]

    function schemeLabel(id) {
        const found = root.schemes.find(s => s.id === id);
        return found ? found.label : id;
    }

    function setScheme(id) {
        root.pendingScheme = id;
        root.hint = "";
    }

    // What a scheme does on this desk, in words.
    function schemeWhat(id) {
        const panel = root.panel ? root.panel.name : "the panel";
        const main = root.mainName !== "" ? root.mainName : "the main external";
        switch (id) {
        case "panel-first":
            return `1 on ${panel}, the rest on ${main}`;
        case "blocks":
            return `1 on ${panel}, every further external ten of its own (11-20, 21-30), ${main} the rest`;
        case "dynamic":
            return "each workspace opens where it is asked for and stays there";
        default:
            return "";
        }
    }

    // The scheme applied now and where it came from; and where Apply would
    // take it when the choice differs.
    readonly property string schemeCaption: {
        if (root.schemeNow === "")
            return "";
        let text = `Now ${root.schemeLabel(root.schemeNow)} from the ${root.schemeSource}: ${root.schemeWhat(root.schemeNow)}`;
        const next = root.pendingScheme === "auto" ? root.schemePreset : root.pendingScheme;
        if (next !== "" && next !== root.schemeNow)
            text += `. Apply makes it ${root.schemeLabel(next)}`;
        return text;
    }

    // The output an override line names, or "" for one that is not present.
    // A description shared by two present outputs is ambiguous and matches
    // neither; their lines are written by connector (selectorFor).
    function resolve(selector) {
        const byDescription = root.outputs.filter(o => o.description !== "" && selector === o.description);
        if (byDescription.length === 1)
            return byDescription[0].name;
        for (const o of root.outputs) {
            if (selector === "name:" + o.name)
                return o.name;
        }
        return "";
    }

    readonly property var fields: ["enabled", "mode", "scale", "transform", "side", "mirror"]

    // name: lines first, description lines after, so a description entry
    // wins field by field over a name: entry for the same output, as
    // override_for in monitors.lua merges them; file order must not decide.
    function currentMap() {
        const map = {};
        const ordered = root.rawOverrides.filter(line => line[0].startsWith("name:"))
            .concat(root.rawOverrides.filter(line => !line[0].startsWith("name:")));
        for (const line of ordered) {
            const name = root.resolve(line[0]);
            if (name === "" || root.fields.indexOf(line[1]) === -1)
                continue;
            if (!map[name])
                map[name] = {};
            map[name][line[1]] = line[2];
        }
        return map;
    }

    // Lines for outputs that are not present are kept verbatim so an
    // unplugged monitor's settings survive an apply.
    readonly property var keptLines: root.rawOverrides.filter(line =>
        line[0] !== "*" && root.resolve(line[0]) === "" && !root.sharedDescription(line[0]))

    // A line naming a description two present outputs share is not kept:
    // the panel writes those by connector, and the policy lets a description
    // entry win, so keeping it would override every edit to either twin.
    function sharedDescription(selector) {
        return root.outputs.filter(o => o.description !== "" && o.description === selector).length > 1;
    }

    // One value per field with the defaults folded away, so two maps that
    // mean the same compare equal.
    function normalized(map) {
        const out = {};
        for (const o of root.outputs) {
            const src = map[o.name] ?? {};
            const dst = {};
            for (const f of root.fields) {
                let v = src[f];
                if (v === undefined || v === null || v === "" || v === "auto")
                    continue;
                v = String(v);
                if (f === "enabled" && v === "true" && !o.internal)
                    continue;
                if (f === "transform" && v === "0")
                    continue;
                if (!o.internal && (f === "side" || f === "mirror"))
                    continue;
                if (f === "side" && v === "right")
                    continue;
                if (f === "mirror" && v === "false")
                    continue;
                dst[f] = v;
            }
            if (Object.keys(dst).length > 0)
                out[o.name] = dst;
        }
        return out;
    }

    // A description shared by two present outputs (a pair of identical
    // monitors) cannot tell them apart, so those are written by connector.
    function selectorFor(o) {
        if (o.description === "")
            return "name:" + o.name;
        const twins = root.outputs.filter(other => other.description === o.description);
        return twins.length > 1 ? "name:" + o.name : o.description;
    }

    function toTsv(map, scheme) {
        const norm = root.normalized(map);
        let text = "";
        for (const o of root.outputs) {
            const entry = norm[o.name];
            if (!entry)
                continue;
            const selector = root.selectorFor(o);
            for (const f of root.fields) {
                if (entry[f] !== undefined)
                    text += `${selector}\t${f}\t${entry[f]}\n`;
            }
        }
        if (scheme !== "auto")
            text += `*\tworkspaces\t${scheme}\n`;
        for (const line of root.keptLines)
            text += `${line[0]}\t${line[1]}\t${line[2]}\n`;
        return text;
    }

    readonly property string pendingTsv: root.toTsv(root.pending, root.pendingScheme)
    readonly property string currentTsv: root.toTsv(root.currentMap(), root.currentScheme)
    readonly property bool dirty: root.pendingTsv !== root.currentTsv || root.saverDirty

    function pendingOf(name) {
        return root.pending[name] ?? {};
    }

    function value(name, field) {
        const v = root.pendingOf(name)[field];
        return v === undefined || v === null || v === "" ? "auto" : String(v);
    }

    // Rebuilt, not mutated: a var property notifies only on reassignment.
    function clonePending() {
        const next = {};
        for (const key in root.pending)
            next[key] = Object.assign({}, root.pending[key]);
        return next;
    }

    // Every edit lands here: a stale hint would describe the previous state.
    function commitPending(next) {
        root.pending = next;
        root.hint = "";
    }

    // The panel's side as the picture should draw it: the pending choice
    // when it differs from the one in force, else nothing (the geometry
    // the compositor reports is drawn as it is).
    readonly property string pendingSide: {
        const panel = root.panel;
        if (!panel || root.externals.length === 0)
            return "";
        const want = root.value(panel.name, "side");
        const now = root.currentMap()[panel.name]?.side ?? "auto";
        if (want === now)
            return "";
        return want === "auto" ? "right" : want;
    }

    // One wheel notch moves the built-in panel one side round the first
    // external, clockwise for wheel down. The only arrangement the policy
    // takes is the panel's side, so the picture offers that and not free
    // placement. Notches are counted so a touchpad's fine steps do not
    // race round.
    property real wheelBalance: 0

    function wheelSide(delta) {
        const panel = root.panel;
        if (!panel || root.externals.length === 0)
            return;
        root.wheelBalance += delta;
        const order = ["right", "below", "left", "above"];
        while (Math.abs(root.wheelBalance) >= 120) {
            const step = root.wheelBalance > 0 ? -1 : 1;
            root.wheelBalance -= step < 0 ? 120 : -120;
            const cur = root.value(panel.name, "side");
            let i = order.indexOf(cur === "auto" ? "right" : cur);
            if (i < 0)
                i = 0;
            root.setField(panel.name, "side", order[(i + step + order.length) % order.length]);
        }
    }

    function setField(name, field, v) {
        const next = root.clonePending();
        if (!next[name])
            next[name] = {};
        if (v === "auto" || v === undefined || v === null || v === "")
            delete next[name][field];
        else
            next[name][field] = String(v);
        root.commitPending(next);
    }

    // Lit after the pending edits, ignoring the lid (the policy handles it).
    // Overridden on counts, overridden off does not, and an output the
    // policy itself has off (the lid-shut panel, keep_internal = false)
    // counts only when the edits turn it on; the policy would ignore an off
    // that leaves nothing lit, so the panel must not offer one.
    function litWith(map) {
        return root.outputs.filter(o => {
            const enabled = map[o.name]?.enabled ?? "auto";
            if (enabled === "false")
                return false;
            if (enabled === "true")
                return true;
            return !o.disabled;
        });
    }

    // The policy would refuse these anyway; saying why here beats a silent
    // no-op after Apply.
    function refusal(map) {
        const lit = root.litWith(map);
        if (lit.length === 0)
            return "at least one display must stay on";
        if (root.panel && (map[root.panel.name]?.enabled ?? "auto") === "false" && root.externals.length === 0)
            return "the built-in panel stays on while no external display is connected";
        return "";
    }

    function canTurnOff(o) {
        if (!o)
            return false;
        if (o.internal)
            return root.externals.length > 0;
        return root.litWith(root.pending).some(other => other.name !== o.name);
    }

    function offNote(o) {
        if (!o)
            return "";
        if (o.internal && root.externals.length === 0)
            return "stays on without an external display";
        if (!o.internal && !root.canTurnOff(o))
            return "the last display on cannot be turned off";
        return "";
    }

    // ---- presets ----------------------------------------------------------
    // Extend left/right say where the external sits relative to the laptop;
    // the policy's default (external at 0x0, panel to its right) is "left".
    readonly property var presets: [
        { id: "laptop",   label: "Laptop only",   what: "the built-in panel alone, every external off" },
        { id: "external", label: "External only", what: "the external alone, the built-in panel off" },
        { id: "left",     label: "Extend left",   what: "the external on the left, the panel to its right" },
        { id: "right",    label: "Extend right",  what: "the external on the right, the panel to its left" },
        { id: "mirror",   label: "Mirror",        what: "the panel shows what the external shows" }
    ]

    // The tile the pending edits describe, and the tile the desk is on now.
    readonly property string preset: root.presetOf(root.pending)
    readonly property string currentPreset: root.presetOf(root.currentMap())

    function presetLabel(id) {
        const found = root.presets.find(p => p.id === id);
        return found ? found.label : "";
    }

    function presetWhat(id) {
        const found = root.presets.find(p => p.id === id);
        return found ? found.what : "";
    }

    // One line under the heading saying which tile the desk is on now, in
    // words, and where Apply would take it when the selection differs: the
    // highlighted tile alone said nothing about what was applied.
    readonly property string layoutCaption: {
        const now = root.currentPreset;
        const next = root.preset;
        let text;
        if (now !== "")
            text = `Now ${root.presetLabel(now)}: ${root.presetWhat(now)}`;
        else
            text = `Now no preset (${root.outputs.filter(o => !o.disabled).map(o => o.name).join(" + ")} on)`;
        if (next !== now)
            text += `. Apply makes it ${next !== "" ? root.presetLabel(next) : "a custom mix"}`;
        return text;
    }

    // Where the pending map is silent, the compositor's state speaks: with
    // keep_internal = false the panel is off without any override, and the
    // tile that describes the desk must still be the lit one.
    function presetOf(map) {
        if (!root.panel || root.externals.length === 0)
            return "";
        const p = map[root.panel.name] ?? {};
        const panelOff = p.enabled === undefined ? root.panel.disabled : p.enabled === "false";
        const mirror = p.mirror === undefined ? root.panel.mirrorOf !== "" : p.mirror === "true";
        const side = p.side ?? "auto";
        const externalsOff = root.externals.filter(o => (map[o.name]?.enabled ?? "auto") === "false").length;
        if (externalsOff === root.externals.length && !panelOff && !mirror)
            return "laptop";
        if (panelOff && externalsOff === 0)
            return "external";
        if (externalsOff > 0 || panelOff)
            return "";
        if (mirror)
            return "mirror";
        if (side === "auto" || side === "right")
            return "left";
        if (side === "left")
            return "right";
        return "";
    }

    function applyPreset(id) {
        if (!root.panel)
            return;
        const next = root.clonePending();
        const panel = next[root.panel.name] ?? {};
        for (const o of root.externals) {
            const e = next[o.name] ?? {};
            if (id === "laptop")
                e.enabled = "false";
            else
                delete e.enabled;
            next[o.name] = e;
        }
        delete panel.mirror;
        delete panel.side;
        // Extend and Mirror force the panel on only when it is off now
        // (keep_internal = false in the settings): otherwise the tile that
        // describes the current desk would read as a change.
        const force = root.panel.disabled ? "true" : undefined;
        switch (id) {
        case "laptop":
            panel.enabled = "true";
            break;
        case "external":
            panel.enabled = "false";
            break;
        case "left":
            panel.enabled = force;
            break;
        case "right":
            panel.enabled = force;
            panel.side = "left";
            break;
        case "mirror":
            panel.enabled = force;
            panel.mirror = "true";
            break;
        }
        if (panel.enabled === undefined)
            delete panel.enabled;
        next[root.panel.name] = panel;
        root.commitPending(next);
    }

    // ---- writing ----------------------------------------------------------

    // Not during the countdown: a second set would make .prev the state just
    // applied, and the revert would no longer reach the one before it.
    function apply() {
        if (!root.dirty || root.busy || root.scriptMissing || root.countdown > 0)
            return;
        const why = root.refusal(root.pending);
        if (why !== "") {
            root.hint = why;
            return;
        }
        if (root.saverDirty)
            root.applySaver();
        // Only the screensaver changed: nothing for the compositor, and
        // nothing to count down over.
        if (root.pendingTsv === root.currentTsv) {
            root.resetPendingOnLoad = true;
            root.refresh();
            return;
        }
        root.busy = true;
        root.error = "";
        // The content travels as an argument, never through the shell's
        // parser: descriptions are whatever the display claims to be.
        setProc.command = ["sh", "-c", "printf '%s' \"$1\" | \"$2\" set", "_", root.pendingTsv, root.script];
        setProc.running = true;
    }

    Process {
        id: setProc

        // Exit 2 means nothing was written. Anything else wrote the file, so
        // the countdown runs even when the compositor did not re-evaluate:
        // that override would otherwise apply itself at the next reload or
        // login with no revert on offer, and the next Apply would overwrite
        // .prev, losing the state before it.
        onExited: code => {
            root.busy = false;
            if (code === 2) {
                root.error = "the override file was refused; see the bar log";
                return;
            }
            if (code !== 0)
                root.error = `written, but the compositor did not re-evaluate (exit ${code})`;
            root.startCountdown();
            root.resetPendingOnLoad = true;
            refreshLater.restart();
        }
    }

    function reset() {
        if (root.busy || root.scriptMissing)
            return;
        root.busy = true;
        root.error = "";
        root.hint = "";
        root.countdown = 0;
        clearProc.running = true;
    }

    Process {
        id: clearProc

        command: ["sh", "-c", "exec \"$1\" clear", "_", root.script]

        onExited: code => {
            root.busy = false;
            if (code !== 0)
                root.error = `reset failed (exit ${code})`;
            root.resetPendingOnLoad = true;
            refreshLater.restart();
        }
    }

    // ---- keep or revert ---------------------------------------------------
    // In the Scope, not the window: a wrong mode can leave the screen dark
    // with the panel unreadable, and closing the panel must not stop the
    // clock either.
    property int countdown: 0

    function startCountdown() {
        root.countdown = Theme.displaysRevertSeconds;
    }

    function keep() {
        root.countdown = 0;
    }

    Timer {
        id: revertTimer

        interval: 1000
        repeat: true
        running: root.countdown > 0

        onTriggered: {
            root.countdown = root.countdown - 1;
            if (root.countdown === 0)
                root.revert();
        }
    }

    function revert() {
        root.countdown = 0;
        if (root.busy)
            return;
        root.busy = true;
        root.error = "";
        revertProc.running = true;
    }

    Process {
        id: revertProc

        command: ["sh", "-c", "exec \"$1\" revert", "_", root.script]

        onExited: code => {
            root.busy = false;
            if (code !== 0)
                root.error = `revert failed (exit ${code})`;
            root.resetPendingOnLoad = true;
            refreshLater.restart();
        }
    }

    // ---- identify ---------------------------------------------------------
    property bool identifying: false

    Timer {
        id: identifyTimer

        interval: Theme.displaysIdentifyMs
        onTriggered: root.identifying = false
    }

    function identify() {
        root.identifying = true;
        identifyTimer.restart();
    }

    function numberOf(name) {
        for (let i = 0; i < root.outputs.length; i++) {
            if (root.outputs[i].name === name)
                return i + 1;
        }
        return 0;
    }

    // An empty model instantiates nothing, so no window exists until asked.
    Variants {
        model: root.identifying ? Quickshell.screens : []

        PanelWindow {
            id: badgeWindow

            required property var modelData

            screen: badgeWindow.modelData
            color: "transparent"
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:displays-identify"

            // The badge's share of its own screen, as on the reference output.
            readonly property real fit: Theme.fit(badgeWindow.screen)

            implicitWidth: Math.round(badge.side * badgeWindow.fit)
            implicitHeight: Math.round(badge.side * badgeWindow.fit)

            // Bottom-right, clear of the card in the middle of the focused
            // screen. rules.lua orders this namespace over the other layers
            // of its level, so the number shows through the card and a
            // screensaver alike.
            anchors {
                bottom: true
                right: true
            }

            margins {
                bottom: Math.round(Theme.px(40) * badgeWindow.fit)
                right: Math.round(Theme.px(40) * badgeWindow.fit)
            }

            // Empty mask: clicks pass through.
            mask: Region {
                item: null
            }

            Rectangle {
                id: badge

                // A square, whichever way the content is longer: the number
                // is tall and the connector name wide, and a card fitted to
                // each looked like a narrow pill.
                readonly property int side: Math.max(badgeColumn.implicitWidth + Theme.px(44),
                                                     badgeColumn.implicitHeight + Theme.px(28))

                implicitWidth: badge.side
                implicitHeight: badge.side
                scale: badgeWindow.fit
                transformOrigin: Item.TopLeft
                radius: Theme.px(18)
                color: Theme.accentIndigo

                Column {
                    id: badgeColumn

                    anchors.centerIn: parent
                    spacing: Theme.px(2)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String(root.numberOf(badgeWindow.modelData?.name ?? "") || "?")
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.px(64)
                        font.weight: Font.Bold
                        color: Theme.ink
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: badgeWindow.modelData?.name ?? ""
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.px(14)
                        font.weight: Font.Medium
                        color: Theme.ink
                    }
                }
            }
        }
    }

    // ---- follow the compositor while open ---------------------------------
    Connections {
        target: Hyprland
        enabled: root.open

        function onRawEvent(event) {
            const name = event?.name ?? "";
            if (name === "monitoradded" || name === "monitoraddedv2"
                || name === "monitorremoved" || name === "monitorremovedv2")
                refreshLater.restart();
        }
    }

    GlobalShortcut {
        name: "displays"
        description: "Display settings: outputs, modes, scale, presets"

        onPressed: root.toggle()
    }

    Connections {
        target: Screensaver

        function onErrorChanged() {
            if (Screensaver.error !== "")
                root.hint = Screensaver.error;
        }
    }

    // ---- pieces -----------------------------------------------------------

    // A small labelled button; `active` fills it with the accent.
    component Chip: Rectangle {
        id: chip

        property string label: ""
        property bool active: false

        signal clicked

        implicitWidth: chipText.implicitWidth + Theme.px(22)
        implicitHeight: Theme.px(30)
        radius: Theme.px(8)
        color: chip.active ? Theme.accentIndigo
                           : (chipHover.hovered && chip.enabled ? Theme.surfaceRaisedHover : Theme.surfaceRaised)
        opacity: chip.enabled ? 1 : 0.4

        Text {
            id: chipText

            anchors.centerIn: parent
            text: chip.label
            font.family: Theme.uiFont
            font.pixelSize: Theme.px(13)
            font.weight: Font.Medium
            color: chip.active ? Theme.ink : Theme.fg
        }

        HoverHandler {
            id: chipHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    // Section heading in the cheatsheet's spaced capitals.
    component Heading: Text {
        font.family: Theme.uiFont
        font.pixelSize: Theme.px(11)
        font.letterSpacing: Theme.px(2)
        color: Theme.surfaceFaint
    }

    // A screen drawn for the preset pictograms: a panel with a base.
    component Screen: Item {
        id: shape

        property bool laptop: false
        property bool off: false

        implicitWidth: shape.laptop ? Theme.px(30) : Theme.px(40)
        implicitHeight: shape.laptop ? Theme.px(24) : Theme.px(34)

        Rectangle {
            id: face

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: parent.height - Theme.px(6)
            radius: Theme.px(3)
            color: "transparent"
            border.width: Math.max(1, Theme.px(2))
            border.color: Theme.fg
            opacity: shape.off ? 0.3 : 0.9

            // A sliver of "content" so a mirror reads as the same picture twice.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.px(5)
                width: parent.width * 0.42
                height: Theme.px(3)
                radius: height / 2
                color: Theme.fg
            }
        }

        // Laptop: a wide base; monitor: a stand.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: shape.laptop ? parent.width + Theme.px(8) : Theme.px(14)
            height: Theme.px(3)
            radius: height / 2
            color: Theme.fg
            opacity: shape.off ? 0.3 : 0.9
        }

        Rectangle {
            visible: !shape.laptop
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.px(3)
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.px(4)
            height: Theme.px(4)
            color: Theme.fg
            opacity: shape.off ? 0.3 : 0.9
        }

        // The cross in the alert colour, as in the KDE tiles.
        Item {
            visible: shape.off
            anchors.centerIn: face
            width: Theme.px(14)
            height: Theme.px(14)

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: Math.max(2, Theme.px(2))
                rotation: 45
                color: Theme.accentRed
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: Math.max(2, Theme.px(2))
                rotation: -45
                color: Theme.accentRed
            }
        }
    }

    // ---- the window -------------------------------------------------------
    property bool menuOpen: false
    property int menuIndex: 0

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win

            // The focused screen (services/Screens.qml says why not the default).
            screen: Screens.focused

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:displays"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // The card's share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(win.screen)

            // A PanelWindow never takes focus itself; Keys must live on a
            // child. This one is also the stage, so the card and its canvas
            // keep their share of the screen.
            FittedStage {
                id: page

                fit: win.fit
                focus: true

                Keys.onPressed: event => {
                    if (root.menuOpen) {
                        const n = root.current ? root.current.modes.length + 1 : 0;
                        switch (event.key) {
                        case Qt.Key_Escape:
                            root.menuOpen = false;
                            break;
                        case Qt.Key_Up:
                        case Qt.Key_K:
                            root.menuIndex = Math.max(0, root.menuIndex - 1);
                            break;
                        case Qt.Key_Down:
                        case Qt.Key_J:
                            root.menuIndex = Math.min(n - 1, root.menuIndex + 1);
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            page.chooseMode(root.menuIndex);
                            break;
                        default:
                            return;
                        }
                        event.accepted = true;
                        return;
                    }
                    // During the countdown Esc reverts at once instead of
                    // closing: a close that let the clock run on would undo
                    // the change 30 s after the user had walked away, and on
                    // a screen gone dark Esc is the key anyone reaches for.
                    if (event.key === Qt.Key_Escape) {
                        if (root.countdown > 0)
                            root.revert();
                        else
                            root.close();
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.countdown > 0)
                            root.keep();
                        else
                            root.apply();
                        event.accepted = true;
                        return;
                    }
                    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        const i = event.key - Qt.Key_1;
                        if (i < root.outputs.length)
                            root.selected = i;
                        event.accepted = true;
                    }
                }

                function chooseMode(index) {
                    if (!root.current)
                        return;
                    if (index <= 0)
                        root.setField(root.current.name, "mode", "auto");
                    else if (index - 1 < root.current.modes.length)
                        root.setField(root.current.name, "mode", root.current.modes[index - 1].key);
                    root.menuOpen = false;
                }

                // Dim backdrop; clicking it closes the panel.
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.78)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }

                Rectangle {
                    id: card

                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(64), Theme.displaysWidth)
                    height: Math.min(parent.height - Theme.px(48), body.implicitHeight + Theme.displaysPad * 2)
                    radius: Theme.surfaceRadius
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine
                    clip: true

                    // Swallows clicks so a near miss does not hit the backdrop.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: body

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.displaysPad
                        spacing: Theme.px(14)

                        // -- title --
                        Item {
                            width: parent.width
                            height: title.implicitHeight

                            Text {
                                id: title

                                text: "Displays"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(22)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Esc to close"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(13)
                                color: Theme.surfaceFaint
                            }
                        }

                        Text {
                            width: parent.width
                            text: root.error !== "" ? root.error : "Select a display to change its settings"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(13)
                            color: root.error !== "" ? Theme.accentRed : Theme.muted
                            elide: Text.ElideRight
                        }

                        // -- layout canvas --
                        Rectangle {
                            id: canvas

                            width: parent.width
                            height: Theme.displaysCanvasHeight
                            radius: Theme.px(12)
                            color: Theme.bg
                            border.width: 1
                            border.color: Theme.surfaceLine

                            WheelHandler {
                                onWheel: event => root.wheelSide(event.angleDelta.y)
                            }

                            Item {
                                id: stage

                                anchors.fill: parent
                                anchors.margins: Theme.px(18)

                                // Boxes in stage coordinates, one per output.
                                readonly property var boxes: stage.place(root.outputs, stage.width, stage.height, root.pendingSide)

                                // Enabled outputs keep their logical geometry
                                // (x, y, size over scale, sides swapped when
                                // rotated); disabled ones queue up to the
                                // right at their last size. The whole is
                                // scaled to fit and centred. A pending side
                                // for the panel that differs from the one in
                                // force is drawn as it will be, beside the
                                // first external, so the wheel shows its
                                // effect before Apply.
                                function place(list, w, h, side) {
                                    if (list.length === 0 || w <= 0 || h <= 0)
                                        return [];
                                    const gap = 24;
                                    const raw = [];
                                    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
                                    for (const o of list) {
                                        if (o.disabled)
                                            continue;
                                        const swap = o.transform % 2 === 1;
                                        // An enabled output that refused every
                                        // mode reports 0x0; drawn at a screen's
                                        // size rather than as a speck.
                                        const pw = swap ? o.height : o.width;
                                        const ph = swap ? o.width : o.height;
                                        const lw = pw > 0 ? pw / o.scale : 1920;
                                        const lh = ph > 0 ? ph / o.scale : 1080;
                                        raw.push({ o: o, x: o.x, y: o.y, w: lw, h: lh });
                                    }
                                    const panel = raw.find(r => r.o.internal);
                                    const external = raw.find(r => !r.o.internal && r.o.mirrorOf === "");
                                    if (side !== "" && panel && external && panel !== external) {
                                        switch (side) {
                                        case "left":
                                            panel.x = external.x - panel.w;
                                            panel.y = external.y;
                                            break;
                                        case "right":
                                            panel.x = external.x + external.w;
                                            panel.y = external.y;
                                            break;
                                        case "above":
                                            panel.x = external.x;
                                            panel.y = external.y - panel.h;
                                            break;
                                        case "below":
                                            panel.x = external.x;
                                            panel.y = external.y + external.h;
                                            break;
                                        }
                                    }
                                    for (const r of raw) {
                                        minX = Math.min(minX, r.x);
                                        minY = Math.min(minY, r.y);
                                        maxX = Math.max(maxX, r.x + r.w);
                                        maxY = Math.max(maxY, r.y + r.h);
                                    }
                                    if (raw.length === 0) {
                                        minX = 0; minY = 0; maxX = 0; maxY = 0;
                                    }
                                    let cursor = maxX + (raw.length > 0 ? gap : 0);
                                    for (const o of list) {
                                        if (!o.disabled)
                                            continue;
                                        const lw = (o.width > 0 ? o.width / o.scale : 1920);
                                        const lh = (o.height > 0 ? o.height / o.scale : 1080);
                                        raw.push({ o: o, x: cursor, y: minY, w: lw, h: lh });
                                        maxX = Math.max(maxX, cursor + lw);
                                        maxY = Math.max(maxY, minY + lh);
                                        cursor += lw + gap;
                                    }
                                    const spanW = Math.max(1, maxX - minX);
                                    const spanH = Math.max(1, maxY - minY);
                                    const k = Math.min(w / spanW, h / spanH);
                                    const offX = (w - spanW * k) / 2;
                                    const offY = (h - spanH * k) / 2;
                                    const out = [];
                                    for (let i = 0; i < list.length; i++) {
                                        const r = raw.find(entry => entry.o === list[i]);
                                        out.push({
                                            x: offX + (r.x - minX) * k,
                                            y: offY + (r.y - minY) * k,
                                            w: Math.max(Theme.px(40), r.w * k),
                                            h: Math.max(Theme.px(28), r.h * k)
                                        });
                                    }
                                    return out;
                                }

                                Repeater {
                                    model: root.outputs

                                    Rectangle {
                                        id: box

                                        required property var modelData
                                        required property int index

                                        readonly property var geometry: stage.boxes[box.index] ?? { x: 0, y: 0, w: 0, h: 0 }
                                        readonly property bool active: root.selected === box.index

                                        x: box.geometry.x
                                        y: box.geometry.y
                                        width: box.geometry.w
                                        height: box.geometry.h
                                        radius: Theme.px(6)

                                        // A wheel step moves the panel around
                                        // the external; a glide reads as a
                                        // move, a jump as a redraw.
                                        Behavior on x {
                                            NumberAnimation {
                                                duration: 160
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        Behavior on y {
                                            NumberAnimation {
                                                duration: 160
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        color: box.active ? Theme.accentIndigo
                                                          : (boxHover.hovered ? Theme.surfaceRaisedHover : Theme.surfaceRaised)
                                        border.width: 1
                                        border.color: box.modelData.disabled ? Theme.surfaceFaint : Theme.surfaceLine
                                        opacity: box.modelData.disabled ? 0.55 : 1

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 0

                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: String(box.index + 1)
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.px(34)
                                                font.weight: Font.DemiBold
                                                color: box.active ? Theme.ink : Theme.fg
                                            }

                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: box.modelData.name + (box.modelData.disabled ? "  off" : "")
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.px(11)
                                                font.weight: Font.Medium
                                                color: box.active ? Theme.ink : Theme.muted
                                            }
                                        }

                                        HoverHandler {
                                            id: boxHover
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.selected = box.index
                                        }
                                    }
                                }

                                Text {
                                    visible: root.outputs.length === 0
                                    anchors.centerIn: parent
                                    text: root.error !== "" ? "No output list" : "Reading outputs"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    color: Theme.muted
                                }
                            }

                            Chip {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: Theme.px(12)
                                label: "Identify"
                                active: root.identifying
                                onClicked: root.identify()
                            }
                        }

                        // -- presets --
                        Column {
                            width: parent.width
                            spacing: Theme.px(8)
                            visible: root.panel !== null && root.externals.length > 0

                            Item {
                                width: parent.width
                                height: layoutHeading.implicitHeight

                                Heading {
                                    id: layoutHeading

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "LAYOUT"
                                }

                                Text {
                                    anchors.left: layoutHeading.right
                                    anchors.right: parent.right
                                    anchors.leftMargin: Theme.px(16)
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: root.layoutCaption
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(12)
                                    color: Theme.surfaceFaint
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: presetRow

                                width: parent.width
                                spacing: Theme.px(10)

                                readonly property int tileWidth: Math.floor((width - spacing * (root.presets.length - 1)) / root.presets.length)

                                Repeater {
                                    model: root.presets

                                    Rectangle {
                                        id: tile

                                        required property var modelData

                                        readonly property bool active: root.preset === tile.modelData.id
                                        readonly property string kind: tile.modelData.id

                                        width: presetRow.tileWidth
                                        height: Theme.displaysTileHeight
                                        radius: Theme.px(12)
                                        color: tileHover.hovered ? Theme.surfaceRaisedHover : Theme.surfaceRaised
                                        border.width: Math.max(1, Theme.px(2))
                                        border.color: tile.active ? Theme.accentIndigo : "transparent"

                                        // Marks the desk as it is, apart from
                                        // the selection outline, so choosing
                                        // another tile never hides where the
                                        // outputs are right now.
                                        Rectangle {
                                            visible: root.currentPreset === tile.kind
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.margins: Theme.px(8)
                                            width: currentLabel.implicitWidth + Theme.px(12)
                                            height: currentLabel.implicitHeight + Theme.px(4)
                                            radius: height / 2
                                            color: tile.active ? Theme.accentIndigo : Theme.surfaceRaisedHover

                                            Text {
                                                id: currentLabel

                                                anchors.centerIn: parent
                                                text: "current"
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.px(10)
                                                font.weight: Font.DemiBold
                                                color: tile.active ? Theme.ink : Theme.fg
                                            }
                                        }

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: Theme.px(10)

                                            // Laptop left, monitor right, except
                                            // "Extend left" which is the desk as
                                            // the policy lays it out.
                                            Item {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: Theme.px(84)
                                                height: Theme.px(34)

                                                Screen {
                                                    laptop: tile.kind !== "left"
                                                    off: tile.kind === "external"
                                                    anchors.left: parent.left
                                                    anchors.bottom: parent.bottom
                                                    anchors.leftMargin: tile.kind === "mirror" ? Theme.px(14) : 0
                                                    z: tile.kind === "mirror" ? 1 : 0
                                                }

                                                Screen {
                                                    laptop: tile.kind === "left"
                                                    off: tile.kind === "laptop"
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.rightMargin: tile.kind === "mirror" ? Theme.px(14) : 0
                                                }
                                            }

                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: tile.modelData.label
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.px(12)
                                                font.weight: Font.Medium
                                                color: tile.active ? Theme.accentIndigo : Theme.muted
                                            }
                                        }

                                        HoverHandler {
                                            id: tileHover
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.applyPreset(tile.kind)
                                        }
                                    }
                                }
                            }
                        }

                        // -- workspaces --
                        // Always shown: the scheme is a desk-wide choice that
                        // only shows its effect once an external is lit.
                        Column {
                            width: parent.width
                            spacing: Theme.px(8)

                            Item {
                                width: parent.width
                                height: workspacesHeading.implicitHeight

                                Heading {
                                    id: workspacesHeading

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "WORKSPACES"
                                }

                                Text {
                                    anchors.left: workspacesHeading.right
                                    anchors.right: parent.right
                                    anchors.leftMargin: Theme.px(16)
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: root.schemeCaption
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(12)
                                    color: Theme.surfaceFaint
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                spacing: Theme.px(8)

                                Repeater {
                                    model: root.schemes

                                    Chip {
                                        required property var modelData

                                        // The preset chip names what it resolves to.
                                        label: modelData.id === "auto" && root.schemePreset !== ""
                                               ? `Preset (${root.schemeLabel(root.schemePreset)})`
                                               : modelData.label
                                        active: root.pendingScheme === modelData.id
                                        onClicked: root.setScheme(modelData.id)
                                    }
                                }
                            }
                        }

                        // -- settings for the selected output --
                        Column {
                            id: settings

                            width: parent.width
                            spacing: Theme.px(8)
                            visible: root.current !== null

                            readonly property var o: root.current
                            readonly property string name: settings.o?.name ?? ""

                            // What the mode and scale rows show: the pending
                            // choice, else what the compositor runs now.
                            readonly property var shownMode: {
                                const key = root.value(settings.name, "mode");
                                if (key !== "auto") {
                                    const m = root.parseMode(key);
                                    if (m)
                                        return m;
                                }
                                return settings.o ? { w: settings.o.width, h: settings.o.height, r: settings.o.refresh } : { w: 0, h: 0, r: 0 };
                            }
                            readonly property real shownScale: {
                                const s = root.value(settings.name, "scale");
                                const n = Number(s);
                                return s !== "auto" && n > 0 ? n : (settings.o?.scale ?? 1);
                            }
                            readonly property string logicalSize: {
                                const m = settings.shownMode;
                                if (!m.w || !m.h)
                                    return "";
                                return `${Math.round(m.w / settings.shownScale)} x ${Math.round(m.h / settings.shownScale)}`;
                            }

                            Heading {
                                text: "SETTINGS"
                            }

                            Row {
                                spacing: Theme.px(10)

                                Rectangle {
                                    width: Theme.px(26)
                                    height: Theme.px(26)
                                    radius: Theme.px(7)
                                    color: Theme.accentIndigo
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(root.selected + 1)
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(14)
                                        font.weight: Font.Bold
                                        color: Theme.ink
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: settings.name
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(15)
                                    font.weight: Font.DemiBold
                                    color: Theme.fg
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, settings.width - Theme.px(200))
                                    text: {
                                        const o = settings.o;
                                        if (!o)
                                            return "";
                                        const parts = [];
                                        if (o.internal)
                                            parts.push("built-in");
                                        if (o.description !== "")
                                            parts.push(o.description);
                                        if (o.mirrorOf !== "")
                                            parts.push("mirroring " + o.mirrorOf);
                                        return parts.join("  ");
                                    }
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    color: Theme.muted
                                    elide: Text.ElideRight
                                }
                            }

                            // Power
                            Item {
                                width: parent.width
                                height: Theme.displaysRowHeight

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Power"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    color: Theme.surfaceDim
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.displaysLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.px(12)

                                    readonly property bool on: root.value(settings.name, "enabled") !== "false"
                                    readonly property bool canOff: root.canTurnOff(settings.o)

                                    // Pill switch: the knob sits at the lit end.
                                    Rectangle {
                                        id: pill

                                        width: Theme.px(46)
                                        height: Theme.px(24)
                                        radius: height / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: parent.on ? Theme.accentIndigo : Theme.surfaceRaised
                                        opacity: parent.on && !parent.canOff ? 0.5 : 1

                                        Rectangle {
                                            width: parent.height - Theme.px(6)
                                            height: width
                                            radius: width / 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: pill.parent.on ? pill.width - width - Theme.px(3) : Theme.px(3)
                                            color: pill.parent.on ? Theme.ink : Theme.fg

                                            Behavior on x {
                                                NumberAnimation {
                                                    duration: 110
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (pill.parent.on) {
                                                    if (pill.parent.canOff)
                                                        root.setField(settings.name, "enabled", "false");
                                                    else
                                                        root.hint = root.offNote(settings.o);
                                                } else {
                                                    root.setField(settings.name, "enabled", settings.o?.internal ? "true" : "auto");
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.on ? "On" : "Off"
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(13)
                                        font.weight: Font.Medium
                                        color: Theme.fg
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: parent.on && !parent.canOff
                                        text: root.offNote(settings.o)
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(12)
                                        color: Theme.muted
                                    }
                                }
                            }

                            // Mode
                            Item {
                                width: parent.width
                                height: Theme.displaysRowHeight

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Mode"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    color: Theme.surfaceDim
                                }

                                Rectangle {
                                    id: modeButton

                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.displaysLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.px(300)
                                    height: Theme.px(30)
                                    radius: Theme.px(8)
                                    color: root.menuOpen || modeHover.hovered ? Theme.surfaceRaisedHover : Theme.surfaceRaised

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.px(11)
                                        anchors.right: chevron.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: {
                                            const key = root.value(settings.name, "mode");
                                            if (key === "auto") {
                                                const m = settings.shownMode;
                                                return m.w ? `Auto  (${root.modeLabel(m)})` : "Auto";
                                            }
                                            const m = root.parseMode(key);
                                            return m ? root.modeLabel(m) : key;
                                        }
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(13)
                                        font.weight: Font.Medium
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }

                                    // md-chevron_down.
                                    Text {
                                        id: chevron

                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.px(8)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String.fromCodePoint(0xF0140)
                                        font.family: Theme.iconFont
                                        font.pixelSize: Theme.px(16)
                                        color: Theme.muted
                                    }

                                    HoverHandler {
                                        id: modeHover
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.menuOpen) {
                                                root.menuOpen = false;
                                                return;
                                            }
                                            const key = root.value(settings.name, "mode");
                                            let at = 0;
                                            if (settings.o) {
                                                for (let i = 0; i < settings.o.modes.length; i++) {
                                                    if (settings.o.modes[i].key === key)
                                                        at = i + 1;
                                                }
                                            }
                                            root.menuIndex = at;
                                            root.menuOpen = true;
                                        }
                                    }
                                }
                            }

                            // Scale
                            Item {
                                width: parent.width
                                height: Theme.displaysRowHeight

                                readonly property var steps: ["auto", "1", "1.25", "1.5", "1.75", "2", "2.5", "3"]
                                readonly property int at: {
                                    const s = root.value(settings.name, "scale");
                                    const i = steps.indexOf(s);
                                    return i;
                                }

                                function step(delta) {
                                    // An unlisted value (set by hand) steps to the nearest listed one.
                                    let i = at;
                                    if (i < 0) {
                                        const n = Number(root.value(settings.name, "scale"));
                                        i = 1;
                                        for (let k = 1; k < steps.length; k++) {
                                            if (Number(steps[k]) <= n)
                                                i = k;
                                        }
                                    }
                                    i = Math.max(0, Math.min(steps.length - 1, i + delta));
                                    root.setField(settings.name, "scale", steps[i]);
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Scale"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    color: Theme.surfaceDim
                                }

                                Row {
                                    id: scaleRow

                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.displaysLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.px(8)

                                    Chip {
                                        label: "−"
                                        enabled: scaleRow.parent.at !== 0
                                        onClicked: scaleRow.parent.step(-1)
                                    }

                                    Rectangle {
                                        width: Theme.px(150)
                                        height: Theme.px(30)
                                        radius: Theme.px(8)
                                        color: Theme.surfaceRaised
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: {
                                                const s = root.value(settings.name, "scale");
                                                return s === "auto" ? `Auto  (${settings.o?.scale ?? 1})` : s;
                                            }
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.px(13)
                                            font.weight: Font.Medium
                                            color: Theme.fg
                                        }
                                    }

                                    Chip {
                                        label: "+"
                                        enabled: scaleRow.parent.at !== scaleRow.parent.steps.length - 1
                                        onClicked: scaleRow.parent.step(1)
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: settings.logicalSize !== "" ? `${settings.logicalSize} logical` : ""
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(12)
                                        color: Theme.muted
                                    }
                                }
                            }

                            // Rotation
                            Item {
                                width: parent.width
                                height: Theme.displaysRowHeight

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Rotation"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    color: Theme.surfaceDim
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.displaysLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.px(8)

                                    Repeater {
                                        model: [
                                            { label: "Auto", value: "auto" },
                                            { label: "0", value: "0" },
                                            { label: "90", value: "1" },
                                            { label: "180", value: "2" },
                                            { label: "270", value: "3" }
                                        ]

                                        Chip {
                                            required property var modelData

                                            label: modelData.label
                                            active: root.value(settings.name, "transform") === modelData.value
                                            onClicked: root.setField(settings.name, "transform", modelData.value)
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: (settings.o?.transform ?? 0) >= 4 && root.value(settings.name, "transform") === "auto"
                                        text: "currently flipped"
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(12)
                                        color: Theme.muted
                                    }
                                }
                            }

                            // Position: the panel beside the first external.
                            Item {
                                width: parent.width
                                height: Theme.displaysRowHeight
                                visible: (settings.o?.internal ?? false) && root.externals.length > 0

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Position"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    color: Theme.surfaceDim
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.displaysLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.px(8)

                                    Repeater {
                                        model: [
                                            { label: "Left of " + (root.externals[0]?.name ?? "external"), value: "left" },
                                            { label: "Right", value: "right" },
                                            { label: "Above", value: "above" },
                                            { label: "Below", value: "below" }
                                        ]

                                        Chip {
                                            required property var modelData

                                            readonly property string side: {
                                                const s = root.value(settings.name, "side");
                                                return s === "auto" ? "right" : s;
                                            }

                                            label: modelData.label
                                            active: side === modelData.value
                                            onClicked: root.setField(settings.name, "side", modelData.value)
                                        }
                                    }
                                }
                            }

                            // Screensaver: the bar's own setting, not an
                            // override, but pending and applied like the
                            // rest so the panel has one way of taking a
                            // change. A switch, as Power: the number is a
                            // separate choice from whether it is on.
                            Item {
                                id: saverRow

                                width: parent.width
                                height: Theme.displaysRowHeight

                                readonly property int minutes: root.pendingSaver[settings.name] ?? 0
                                readonly property bool on: saverRow.minutes > 0
                                // What the switch would turn on: the last
                                // number this display had, else the default.
                                readonly property int remembered: root.saverMemory[settings.name] ?? Screensaver.defaultMinutes

                                function toggle() {
                                    root.setSaver(settings.name, saverRow.on ? 0 : saverRow.remembered);
                                }

                                // - and + walk the listed steps and stop at
                                // the ends; the wheel moves by a minute for
                                // a number between them.
                                function step(delta) {
                                    const cur = saverRow.minutes;
                                    if (cur <= 0)
                                        return;
                                    const steps = Screensaver.steps;
                                    let next = cur;
                                    if (delta > 0) {
                                        next = steps.find(v => v > cur) ?? Math.min(Screensaver.maxMinutes, cur + 1);
                                    } else {
                                        for (const v of steps) {
                                            if (v < cur)
                                                next = v;
                                        }
                                    }
                                    next = Math.max(Screensaver.minMinutes, Math.min(Screensaver.maxMinutes, next));
                                    if (next !== cur)
                                        root.setSaver(settings.name, next);
                                }

                                function nudge(delta) {
                                    const cur = saverRow.minutes;
                                    if (cur <= 0)
                                        return;
                                    const next = Math.max(Screensaver.minMinutes, Math.min(Screensaver.maxMinutes, cur + delta));
                                    if (next !== cur)
                                        root.setSaver(settings.name, next);
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Screensaver"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    color: Theme.surfaceDim
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.displaysLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.px(12)

                                    // One switch with both states written on
                                    // it: a press anywhere on it toggles, and
                                    // the lit half slides to the new state.
                                    // Two chips read as two settings; one
                                    // frame reads as one choice.
                                    Rectangle {
                                        id: saverSwitch

                                        readonly property int pad: Theme.px(3)
                                        readonly property int halfWidth: Math.max(offLabel.implicitWidth, onLabel.implicitWidth) + Theme.px(22)

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: saverSwitch.halfWidth * 2 + saverSwitch.pad * 2
                                        height: Theme.px(30)
                                        radius: Theme.px(8)
                                        color: switchHover.hovered ? Theme.surfaceRaisedHover : Theme.surfaceRaised

                                        // The lit half.
                                        Rectangle {
                                            x: saverSwitch.pad + (saverRow.on ? saverSwitch.halfWidth : 0)
                                            y: saverSwitch.pad
                                            width: saverSwitch.halfWidth
                                            height: saverSwitch.height - saverSwitch.pad * 2
                                            radius: Theme.px(6)
                                            color: Theme.accentIndigo

                                            Behavior on x {
                                                NumberAnimation {
                                                    duration: 120
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }

                                        Text {
                                            id: offLabel

                                            x: saverSwitch.pad + (saverSwitch.halfWidth - offLabel.implicitWidth) / 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Off"
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.px(13)
                                            font.weight: Font.Medium
                                            color: saverRow.on ? Theme.fg : Theme.ink
                                        }

                                        Text {
                                            id: onLabel

                                            x: saverSwitch.pad + saverSwitch.halfWidth + (saverSwitch.halfWidth - onLabel.implicitWidth) / 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "On"
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.px(13)
                                            font.weight: Font.Medium
                                            color: saverRow.on ? Theme.ink : Theme.fg
                                        }

                                        HoverHandler {
                                            id: switchHover
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: saverRow.toggle()
                                        }
                                    }

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.px(8)
                                        // Dimmed while off: the number is
                                        // what the switch would bring back.
                                        opacity: saverRow.on ? 1 : 0.4

                                        Chip {
                                            label: "−"
                                            enabled: saverRow.on && saverRow.minutes > Screensaver.minMinutes
                                            onClicked: saverRow.step(-1)
                                        }

                                        Rectangle {
                                            width: Theme.px(110)
                                            height: Theme.px(30)
                                            radius: Theme.px(8)
                                            color: Theme.surfaceRaised
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: `${saverRow.on ? saverRow.minutes : saverRow.remembered} min`
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.px(13)
                                                font.weight: Font.Medium
                                                color: Theme.fg
                                            }

                                            WheelHandler {
                                                enabled: saverRow.on
                                                onWheel: event => saverRow.nudge(event.angleDelta.y > 0 ? 1 : -1)
                                            }
                                        }

                                        Chip {
                                            label: "+"
                                            enabled: saverRow.on && saverRow.minutes < Screensaver.maxMinutes
                                            onClicked: saverRow.step(1)
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "the clock, alone on black, after that long with nothing done on this display"
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(12)
                                        color: Theme.muted
                                    }
                                }
                            }
                        }

                        // -- footer --
                        Item {
                            width: parent.width
                            height: Theme.px(40)

                            // Reverting: the banner replaces the buttons.
                            Row {
                                visible: root.countdown > 0
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.px(14)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: `Keep these settings?  Reverting in ${root.countdown} s`
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(14)
                                    font.weight: Font.Medium
                                    color: Theme.fg
                                }

                                Chip {
                                    label: "Keep"
                                    active: true
                                    onClicked: root.keep()
                                }

                                Chip {
                                    label: "Revert"
                                    onClicked: root.revert()
                                }
                            }

                            Text {
                                visible: root.countdown === 0
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Reset to automatic"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(13)
                                font.weight: Font.Medium
                                color: resetHover.hovered ? Theme.fg : Theme.muted
                                opacity: root.scriptMissing ? 0.4 : 1

                                HoverHandler {
                                    id: resetHover
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.reset()
                                }
                            }

                            Row {
                                visible: root.countdown === 0
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.px(10)

                                Chip {
                                    label: "Cancel"
                                    onClicked: root.close()
                                }

                                Chip {
                                    label: root.busy ? "Applying" : "Apply"
                                    active: root.dirty && !root.busy && !root.scriptMissing && root.countdown === 0
                                    enabled: root.dirty && !root.busy && !root.scriptMissing && root.countdown === 0
                                    onClicked: root.apply()
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: root.hint !== "" ? root.hint
                                  : root.countdown > 0 ? "enter keeps, esc reverts"
                                  : "digits select a display, the wheel over the picture moves the panel, enter applies, esc closes"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(11)
                            color: root.hint !== "" ? Theme.accentAmber : Theme.muted
                            elide: Text.ElideRight
                        }
                    }

                    // Closes the mode list on a click anywhere else in the card.
                    MouseArea {
                        anchors.fill: parent
                        visible: root.menuOpen
                        onClicked: root.menuOpen = false
                    }

                    // The mode list, above everything in the card, placed
                    // under its button when opened. Placed once per opening:
                    // mapToItem is not a binding, and the card does not move
                    // while the list is up.
                    Connections {
                        target: root

                        function onMenuOpenChanged() {
                            if (!root.menuOpen)
                                return;
                            const p = modeButton.mapToItem(card, 0, modeButton.height + Theme.px(4));
                            menu.x = p.x;
                            menu.y = p.y;
                        }
                    }

                    Rectangle {
                        id: menu

                        visible: root.menuOpen
                        width: Theme.px(300)
                        height: Math.min(Theme.px(280), modeList.contentHeight + Theme.px(8))
                        radius: Theme.px(8)
                        color: Theme.surfaceBg
                        border.width: Theme.surfaceBorder
                        border.color: Theme.surfaceLine
                        z: 10

                        ListView {
                            id: modeList

                            anchors.fill: parent
                            anchors.margins: Theme.px(4)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            currentIndex: root.menuIndex
                            highlightFollowsCurrentItem: true

                            model: {
                                const o = settings.o;
                                const rows = [{ key: "auto", label: "Auto  (highest refresh, then resolution)" }];
                                if (o) {
                                    for (const m of o.modes)
                                        rows.push({ key: m.key, label: m.label });
                                }
                                return rows;
                            }

                            delegate: Rectangle {
                                id: row

                                required property var modelData
                                required property int index

                                readonly property bool chosen: root.value(settings.name, "mode") === row.modelData.key

                                width: modeList.width
                                height: Theme.px(28)
                                radius: Theme.px(6)
                                color: root.menuIndex === row.index ? Theme.surfaceHover : "transparent"

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.px(9)
                                    anchors.right: check.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(13)
                                    font.weight: row.chosen ? Font.DemiBold : Font.Normal
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: check

                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.px(9)
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: row.chosen
                                    text: Theme.iconCheck
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.px(14)
                                    color: Theme.accentIndigo
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.menuIndex = row.index
                                    onClicked: page.chooseMode(row.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
