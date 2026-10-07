pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// A screensaver per display, in two stages, once the display has gone
// unused for its set number of minutes (services/Screensaver.qml; off unless
// set). Nothing but black is ever shown: the screens are left on overnight
// in a room someone sleeps in, where a clock is a light of its own. The
// output stays enabled and keeps its windows, and nothing else stops: no
// suspend, no lock, programs run on behind the dark screen.
//
//   black  The display is unused while someone works on another. Hyprland
//          fills it with #000000 (a 1x1 layer with dim_around, rules.lua),
//          which an OLED panel shows as pixels switched off. No modeset, so
//          it comes and goes at once.
//   off    Nobody is at the keys. DPMS, through MONITORS.saver in
//          hypr/config/monitors.lua, since a backlit panel glows even when
//          black. Every DPMS change stalls the whole compositor for half a
//          second to a second and a half (see M.saver), which is why off
//          waits for an empty seat, and why a display that is off stays off
//          until it is used instead of waking to black.
//
// Wayland has no per-output idle, so "unused" is derived: input goes to the
// pointer's screen (Hyprland's focused monitor) and to the screen of the
// window taking the keys, which Hyprland leaves behind when the pointer
// crosses onto another screen's bar or empty space. A display is in use
// exactly while it is one of those and the seat is not idle. Hence two
// clocks per display. The seat clock is
// the compositor's (ext-idle-notify): no input for the display's minutes
// means every display is unused, this one included, unless a visible window
// anywhere inhibits idle (a film). The away clock starts when focus leaves
// the display and is cancelled when it returns; when it runs out the display
// is unused unless a window on it inhibits idle (a film on the external
// while the panel is typed on).
//
// Both clocks ask `hyprctl clients` about inhibitors when they run out. The
// compositor's inhibitor-aware clock would do the seat's asking itself, but
// Hyprland (0.56.2, and main as of October 2026) restarts every such clock
// whenever focus changes, so a window opening or closing at night, with
// nobody at the keys, turned the display back on. The cost: an inhibitor
// that appears once the screens are dark (a film starting by itself) does
// not wake them.
//
// Moving the pointer onto a dark display or switching to a workspace on it
// (Super+digit) makes it the focused monitor and lights it: at once from
// black, after the panel's power-up from off. A press or click anywhere
// wakes the seat and lights the focused display; the others stay dark until
// they are used. Once every display is off, the compositor's own wake takes
// over (*_enables_dpms in general.lua): the first key or pointer motion
// turns them all on. A display turned on by anything but this module (that
// wake, a resume, the lid) counts as used, so both its clocks start over.
//
// Nothing goes dark while the Displays panel is open (`paused`), and a
// display being shared stays up while the share lasts (`shares`). A region
// shot or a colour pick lifts the black while it runs (`lifted`). A reload
// hands the dark displays and the shares on to the new instance (`kept`);
// when the bar stops, bar.service lights whatever it left off
// (MONITORS.saver_release).
Scope {
    id: root

    // Either stage for a while, from a shell:
    //   qs -p ~/.config/quickshell/bar ipc call screensaver preview eDP-1 10
    //   qs -p ~/.config/quickshell/bar ipc call screensaver previewOff eDP-1 10
    //
    // And for hypr/scripts/capture.sh (lift N, then lift 0); see `lifted`.
    IpcHandler {
        target: "screensaver"

        function preview(name: string, seconds: int): void {
            root.startPreview(name, seconds, "black");
        }

        function previewOff(name: string, seconds: int): void {
            root.startPreview(name, seconds, "off");
        }

        function lift(seconds: int): void {
            root.lifted = seconds > 0;
            if (root.lifted) {
                liftTimer.interval = Math.min(seconds, 300) * 1000;
                liftTimer.restart();
            } else {
                liftTimer.stop();
            }
        }
    }

    // Set while a region shot or a colour pick runs. Both grab every output
    // before their overlay shows, and a display in the black stage came out
    // black. Only the black goes: the clocks run on, so it comes back as it
    // was. Bounded, in case the capture dies before it says it is done.
    property bool lifted: false

    Timer {
        id: liftTimer

        onTriggered: root.lifted = false
    }

    property string previewName: ""
    // "black" or "off".
    property string previewStage: "black"

    function startPreview(name, seconds, stage) {
        root.previewName = name;
        root.previewStage = stage;
        previewTimer.interval = Math.max(1, seconds || 10) * 1000;
        previewTimer.restart();
    }

    Timer {
        id: previewTimer

        onTriggered: root.previewName = ""
    }

    // Every display stays up while this is set. shell.qml sets it while the
    // Displays panel is open: its changes, and the countdown that reverts
    // them, are only safe on screens the user can see.
    property bool paused: false

    // What this module did to each display, and the shares under way, kept
    // across reloads. install.sh reloads the bar, at night too, and the new
    // instance lit every display the old one had darkened, then waited its
    // full minutes to darken them again; a share in progress was forgotten,
    // and its display could go dark under the call. JSON strings, as in
    // Notifications.qml; state is {name: {off, offSince, away, slept,
    // blocked}}.
    PersistentProperties {
        id: kept

        reloadableId: "screensaver"

        property string state: "{}"
        property string shares: "{}"

        onLoaded: {
            root.inherited = root.parseObject(kept.state);
            root.inheritedArrived();
            root.shares = root.parseObject(kept.shares);
            root.settleShares();
            // Nothing announces a DPMS change, so the cached monitor state
            // can predate the old instance's last request: a display it had
            // just turned off still read as lit and was lit again. Read the
            // monitors afresh; the answer lands within milliseconds.
            Hyprland.refreshMonitors();
            settle.restart();
        }
    }

    Timer {
        id: settle

        interval: 300
        onTriggered: root.restored = true
    }

    function parseObject(text) {
        try {
            const value = JSON.parse(text);
            return value !== null && typeof value === "object" ? value : {};
        } catch (e) {
            return {};
        }
    }

    function record(name, entry) {
        const all = root.parseObject(kept.state);
        if (entry)
            all[name] = entry;
        else
            delete all[name];
        kept.state = JSON.stringify(all);
    }

    onSharesChanged: kept.shares = JSON.stringify(root.shares)

    // The previous instance's state, taken by each display once; empty
    // after a start.
    property var inherited: ({})
    property bool restored: false

    signal inheritedArrived

    // No display decides anything before both are in: with the minutes
    // still unread every display reads as unarmed, and without the saved
    // state a display left dark would be lit.
    readonly property bool ready: root.restored && Screensaver.loaded

    onReadyChanged: {
        // What no display took is stale by the time one could: a display
        // that comes back later must not inherit its old darkness.
        if (root.ready)
            Qt.callLater(() => root.inherited = {});
    }

    // A display taken over while off counts the seat as idle, as it was
    // when it went off. A new idle notification reports going idle and
    // back only, so the first input after a reload would never arrive;
    // this one-second notification stands in for it.
    property int waking: 0

    signal inputSeen

    IdleMonitor {
        id: wake

        enabled: root.waking > 0
        timeout: 1
        respectInhibitors: false

        onIsIdleChanged: {
            if (wake.isIdle)
                return;
            root.waking = 0;
            root.inputSeen();
        }
    }

    // Screen sharing (a call, a recording) shows a display to someone, so it
    // must not go dark: a shared output is held up, and a shared window holds
    // every display, since its frames are drawn with its monitor's. Hyprland
    // reports any screencopy as a share until half a second after its last
    // frame, a screenshot included, so a share counts once it has lasted.
    // Keyed "monitor,<output>" or "region,<output>" as screencastv2 gives
    // them, and "window," for every window share: Hyprland names those by
    // the window's title as it is when the window is next resized, so a
    // share may stop under another name than it started with. Values are
    // { since, count }: when the first of the shares under the key began,
    // and how many are on (Hyprland sends one start and one stop each).
    property var shares: ({})
    // Those that have lasted, as { type, name }.
    property var lasting: []
    readonly property bool shareHoldsAll: root.lasting.some(s => s.type === "window")
    readonly property var shareHolds: root.lasting.filter(s => s.type !== "window").map(s => s.name)

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "screencastv2")
                return;
            // "<1|0>,<type>,<name>"; a window title may hold commas.
            const data = String(event.data);
            const a = data.indexOf(",");
            const b = a < 0 ? -1 : data.indexOf(",", a + 1);
            if (b < 0)
                return;
            const type = data.slice(a + 1, b);
            const key = type === "window" ? "window," : data.slice(a + 1);
            const next = Object.assign({}, root.shares);
            const entry = next[key];
            if (data.slice(0, a) === "1") {
                next[key] = entry ? { since: entry.since, count: entry.count + 1 } : { since: Date.now(), count: 1 };
            } else if (entry) {
                // A stop with no start seen began before this instance.
                if (entry.count > 1)
                    next[key] = { since: entry.since, count: entry.count - 1 };
                else
                    delete next[key];
            }
            root.shares = next;
            root.settleShares();
        }
    }

    Timer {
        id: shareTimer

        onTriggered: root.settleShares()
    }

    function settleShares() {
        const now = Date.now();
        const lasting = [];
        let wait = 0;
        for (const key of Object.keys(root.shares)) {
            const left = Theme.saverShareMs - (now - root.shares[key].since);
            if (left <= 0) {
                const at = key.indexOf(",");
                lasting.push({ type: key.slice(0, at), name: key.slice(at + 1) });
            } else if (wait === 0 || left < wait) {
                wait = left;
            }
        }
        root.lasting = lasting;
        if (wait > 0) {
            shareTimer.interval = wait + 50;
            shareTimer.restart();
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: slot

            required property var modelData

            readonly property string name: slot.modelData?.name ?? ""
            readonly property int minutes: Screensaver.minutesByName[slot.name] ?? 0
            readonly property bool held: root.paused || root.shareHoldsAll || root.shareHolds.includes(slot.name)
            readonly property bool armed: slot.minutes >= Screensaver.minMinutes && !slot.held
            // In use: the pointer's screen (Hyprland's focused monitor), or
            // the one the keys go to, which keeps its window when the pointer
            // rests on another screen's bar or empty space (Screens.keyboard).
            readonly property bool focused: (Hyprland.focusedMonitor?.name ?? "") === slot.name
                || (Screens.keyboard?.name ?? "") === slot.name
            readonly property var monitor: Hyprland.monitors.values.find(m => m.name === slot.name) ?? null

            readonly property bool previewing: root.previewName === slot.name

            // The seat clock has run out and no window inhibited idle at the
            // last look; cleared by input.
            property bool rested: false
            // Went off for an empty seat and has not been used since. Never
            // written from the wantOff handler (ask), which would make a
            // binding loop of wantOff.
            property bool slept: false
            // The away clock has run out; cleared when focus returns.
            property bool away: false
            // A window on this display inhibited idle at the last look.
            property bool blocked: false
            // This module turned the display off and has not turned it on.
            property bool off: false
            // When this display was last asked to turn off.
            property real offSince: 0

            // Unused while someone works elsewhere: black.
            readonly property bool unused: slot.armed && slot.away && !slot.focused && !slot.blocked
            readonly property bool wantOff: (slot.previewing && root.previewStage === "off")
                || (slot.armed && (slot.rested || (slot.slept && slot.unused)))
            readonly property bool dark: (slot.wantOff || slot.unused || slot.previewing || slot.inheritedDark) && !root.lifted

            onWantOffChanged: slot.ask(slot.wantOff)

            onRestedChanged: {
                if (slot.rested)
                    slot.slept = true;
            }

            // Waits for the saved state and the minutes (root.ready).
            Component.onCompleted: {
                if (root.ready)
                    slot.start();
            }

            Connections {
                target: root

                function onReadyChanged() {
                    if (root.ready)
                        slot.start();
                }

                // Black at once where the previous instance had it dark:
                // its layer is gone with it, and waiting for start() showed
                // the desktop for half a second at every reload.
                function onInheritedArrived() {
                    const saved = root.inherited[slot.name];
                    slot.inheritedDark = saved?.off === true || (saved?.away === true && !slot.focused);
                }

                function onInputSeen() {
                    if (!slot.waking)
                        return;
                    slot.waking = false;
                    slot.rested = false;
                    if (!slot.unused)
                        slot.slept = false;
                    if (slot.off)
                        Hyprland.refreshMonitors();
                }
            }

            // Set while a display taken over off waits for the next input.
            property bool waking: false

            // Black until start() has decided; see onInheritedArrived.
            property bool inheritedDark: false

            // Takes over what the instance before a reload left: a display
            // still off stays off, one that was black stays black. Anything
            // else is lit, in case an earlier instance left it off (after a
            // crash bar.service has lit it already; M.saver passes over a
            // display that is lit).
            function start() {
                const saved = root.inherited[slot.name];
                const lit = slot.monitor?.lastIpcObject?.dpmsStatus;
                if (saved?.off === true && lit === false && slot.armed) {
                    slot.offSince = saved.offSince ?? Date.now();
                    slot.off = true;
                    slot.slept = true;
                    slot.blocked = saved.blocked === true;
                    slot.away = !slot.focused;
                    slot.rested = true;
                    slot.waking = true;
                    root.waking += 1;
                } else if (saved?.away === true && !slot.focused && lit !== false) {
                    slot.blocked = saved.blocked === true;
                    slot.slept = saved.slept === true;
                    slot.away = true;
                } else {
                    slot.ask(false);
                }
                slot.inheritedDark = false;
            }

            // For the next instance; see `kept`.
            function remember() {
                if (!root.ready)
                    return;
                root.record(slot.name, slot.off || slot.away
                            ? { off: slot.off, offSince: slot.offSince, away: slot.away,
                                slept: slot.slept, blocked: slot.blocked }
                            : null);
            }

            onOffChanged: slot.remember()
            onAwayChanged: slot.remember()
            onSleptChanged: slot.remember()
            onBlockedChanged: slot.remember()

            onFocusedChanged: {
                if (slot.focused) {
                    slot.away = false;
                    slot.blocked = false;
                    slot.slept = false;
                }
            }

            // A new number, or the end of a hold, starts both clocks over.
            onMinutesChanged: slot.startOver()
            onArmedChanged: slot.startOver()

            function startOver() {
                slot.away = false;
                slot.blocked = false;
                slot.slept = false;
            }

            // A Lua dispatch on the IPC socket, no process. The name goes
            // into the Lua source; connector names never need quoting, and
            // anything that would is refused rather than escaped. A config
            // without MONITORS.saver (install.sh reloads the bar before the
            // compositor) is passed over: a failing dispatch puts an error
            // bar on screen until the next reload.
            function ask(off) {
                if (!/^[A-Za-z0-9._-]+$/.test(slot.name))
                    return;
                slot.off = off;
                if (off)
                    slot.offSince = Date.now();
                Hyprland.dispatch(`function() if MONITORS and MONITORS.saver then MONITORS.saver("${slot.name}", ${off}) end end`);
            }

            IdleMonitor {
                id: seat

                // Off for a moment to start the clock over (reconcile).
                enabled: slot.armed && !restart.running
                // Never 0, even for the moment `armed` has turned true and
                // this has not yet followed: a 0 s notification is idle at
                // once, and the display would blink off and on.
                timeout: Math.max(1, slot.minutes) * 60
                // Input alone; inhibitors are asked about (see the top).
                respectInhibitors: false

                onIsIdleChanged: {
                    if (seat.isIdle) {
                        slot.check();
                        return;
                    }
                    slot.rested = false;
                    // The input was on this display, or it is in use anyway.
                    if (!slot.unused)
                        slot.slept = false;
                    // Input after an idle spell. If every display was off,
                    // the compositor has just turned them all on; reading
                    // the state now lets reconcile see it at once.
                    if (slot.off)
                        Hyprland.refreshMonitors();
                }
            }

            Timer {
                id: restart

                interval: 1
            }

            // Runs while the display is not focused and has not yet been
            // found unused; focus returning stops it through the binding.
            Timer {
                id: awayTimer

                interval: Math.max(1, slot.minutes) * 60000
                running: slot.armed && !slot.focused && !slot.away

                onTriggered: slot.check()
            }

            // Held back by an inhibitor: ask again now and then. Nothing
            // announces an inhibitor going away, so this is a poll, kept
            // to the rare state it serves.
            Timer {
                id: recheck

                interval: Theme.saverRecheckMs
                repeat: true
                running: slot.armed && ((seat.isIdle && !slot.rested) || (slot.away && slot.blocked && !slot.focused))

                onTriggered: slot.check()
            }

            function check() {
                if (!clients.running)
                    clients.running = true;
            }

            // The compositor's window list, asked for only here: idle
            // inhibitors change without an event, so the cached toplevels
            // cannot say. One process per look.
            Process {
                id: clients

                command: ["hyprctl", "clients", "-j"]

                stdout: StdioCollector {
                    onStreamFinished: slot.settle(this.text)
                }

                onExited: code => {
                    if (code !== 0)
                        slot.settle("");
                }
            }

            // A hung hyprctl must not hold the display in limbo.
            Timer {
                interval: 5000
                running: clients.running

                onTriggered: {
                    clients.running = false;
                    slot.settle("");
                }
            }

            // Either clock may have asked. With the seat idle, a display
            // focus is not on has gone unused for its minutes as well, so
            // the away clock's answer is given then too.
            function settle(text) {
                if (!slot.armed)
                    return;
                const list = slot.parse(text);
                // Input came back while the list was on its way.
                if (seat.isIdle)
                    slot.rested = !list.some(c => slot.inhibiting(c));
                // Focus came back while the list was on its way.
                if (!slot.focused) {
                    slot.blocked = slot.inhibitedOn(list);
                    slot.away = true;
                }
            }

            // An unreadable list counts as no window: the saver is the
            // feature, and the compositor is in trouble anyway if hyprctl
            // fails.
            function parse(text) {
                try {
                    const list = JSON.parse(text);
                    return Array.isArray(list) ? list : [];
                } catch (e) {
                    return [];
                }
            }

            // A mapped, visible window holding an idle inhibitor (the
            // protocol's, or the idle_inhibit window rule); the compositor
            // counts the same ones.
            function inhibiting(c) {
                return c && c.inhibitingIdle === true && c.mapped !== false && c.hidden !== true;
            }

            // Such a window on this display's active workspace.
            function inhibitedOn(list) {
                const monitor = slot.monitor;
                if (!monitor)
                    return false;
                const workspace = monitor.activeWorkspace?.id ?? 0;
                return list.some(c => slot.inhibiting(c) && Number(c.monitor) === monitor.id
                                 && (workspace === 0 || Number(c.workspace?.id ?? 0) === workspace));
            }

            // Nothing announces a DPMS change either: while this display is
            // off, its real state is read now and then.
            Timer {
                interval: Theme.saverRecheckMs
                repeat: true
                running: slot.off

                onTriggered: Hyprland.refreshMonitors()
            }

            Connections {
                target: slot.monitor

                function onLastIpcObjectChanged() {
                    slot.reconcile();
                }
            }

            // On while meant to be off, and not in a reading that may
            // predate this module's own request: something else turned it
            // on, which counts as use. Both clocks start over; the seat's by
            // re-creating the idle notification, since only input resets it.
            function reconcile() {
                if (!slot.off || slot.monitor?.lastIpcObject?.dpmsStatus !== true)
                    return;
                if (Date.now() - slot.offSince < Theme.saverSettleMs)
                    return;
                if (slot.previewing) {
                    previewTimer.stop();
                    root.previewName = "";
                }
                slot.rested = false;
                slot.slept = false;
                slot.away = false;
                slot.blocked = false;
                restart.restart();
            }

            // The black: Hyprland fills the output with #000000 around this
            // one pixel (dim_around, rules.lua), so nothing the size of the
            // screen is allocated here. Kept while off as well, so that off
            // begins and ends behind black rather than over the desktop.
            LazyLoader {
                active: slot.dark

                PanelWindow {
                    screen: slot.modelData
                    color: "transparent"
                    implicitWidth: 1
                    implicitHeight: 1
                    exclusionMode: ExclusionMode.Ignore
                    focusable: false
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    WlrLayershell.namespace: "quickshell:screensaver"
                    // Not even its one pixel takes the pointer.
                    mask: Region {}
                }
            }
        }
    }
}
