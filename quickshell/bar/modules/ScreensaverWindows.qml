pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// A screensaver per display: a black layer with a clock that moves once a
// minute, over a display nothing has been done on for its set number of
// minutes (services/Screensaver.qml; off unless set).
//
// Wayland has no per-output idle, so "nothing done on this display" is
// derived: input goes to the focused monitor (the pointer's, and the
// keyboard's through the focused window), so a display is in use exactly
// while it is the focused monitor and the seat is not idle. Hence two
// clocks per display. The seat clock is the compositor's (ext-idle-notify,
// inhibitors respected): idle for the display's minutes means every display
// is unused, this one included. The away clock starts when focus leaves the
// display and is cancelled when it returns; when it runs out the display is
// unused unless a window on it inhibits idle (a film on the external while
// the panel is typed on), which the compositor's clock would have honoured
// and this one has to ask about.
//
// Moving the pointer onto the display or switching to a workspace on it
// (Super+digit) makes it the focused monitor, and the saver goes; a press
// or click anywhere wakes the seat and the focused display's saver goes,
// the others stay until they are used. Nothing here touches the output:
// no DPMS, no disable, and the lock is a different thing entirely. The
// saver never asks for the lock, never takes the keyboard, and sits in the
// layer stack under the session lock, which the compositor draws over every
// layer (the above_lock layer rule would break that; never set it here).
Scope {
    id: root

    // Preview from a shell, e.g. after changing the look:
    //   qs -p ~/.config/quickshell/bar ipc call screensaver preview eDP-1 10
    IpcHandler {
        target: "screensaver"

        function preview(name: string, seconds: int): void {
            root.previewName = name;
            previewTimer.interval = Math.max(1, seconds || 10) * 1000;
            previewTimer.restart();
        }
    }

    property string previewName: ""

    Timer {
        id: previewTimer

        onTriggered: root.previewName = ""
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: slot

            required property var modelData

            readonly property string name: slot.modelData?.name ?? ""
            readonly property int minutes: Screensaver.minutesByName[slot.name] ?? 0
            readonly property bool armed: slot.minutes >= Screensaver.minMinutes
            readonly property bool focused: (Hyprland.focusedMonitor?.name ?? "") === slot.name

            // The away clock has run out; cleared when focus returns.
            property bool away: false
            // A window on this display inhibited idle at the last look.
            property bool blocked: false

            readonly property bool showing: root.previewName === slot.name
                || (slot.armed && (seat.isIdle || (slot.away && !slot.focused && !slot.blocked)))

            onFocusedChanged: {
                if (slot.focused) {
                    slot.away = false;
                    slot.blocked = false;
                }
            }

            // A new number starts both clocks over.
            onMinutesChanged: {
                slot.away = false;
                slot.blocked = false;
            }

            IdleMonitor {
                id: seat

                enabled: slot.armed
                timeout: slot.minutes * 60
                respectInhibitors: true
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
                running: slot.armed && slot.away && slot.blocked && !slot.focused

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

            function settle(text) {
                // Focus came back while the list was on its way.
                if (!slot.armed || slot.focused)
                    return;
                slot.blocked = slot.inhibitedOn(text);
                slot.away = true;
            }

            // True when a mapped, visible window on this display's active
            // workspace holds an idle inhibitor (the protocol's, or the
            // idle_inhibit window rule). An unreadable list counts as none:
            // the saver is the feature, and the compositor is in trouble
            // anyway if hyprctl fails.
            function inhibitedOn(text) {
                let list;
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    return false;
                }
                if (!Array.isArray(list))
                    return false;
                const monitor = Hyprland.monitors.values.find(m => m.name === slot.name);
                if (!monitor)
                    return false;
                const workspace = monitor.activeWorkspace?.id ?? 0;
                return list.some(c => c && c.inhibitingIdle === true && c.mapped !== false && c.hidden !== true
                                 && Number(c.monitor) === monitor.id
                                 && (workspace === 0 || Number(c.workspace?.id ?? 0) === workspace));
            }

            // The surface exists only while shown; between times there is
            // nothing to draw and nothing to hold buffers.
            LazyLoader {
                active: slot.showing

                PanelWindow {
                    id: win

                    screen: slot.modelData
                    color: "black"
                    exclusionMode: ExclusionMode.Ignore
                    focusable: false
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    WlrLayershell.namespace: "quickshell:screensaver"

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }

                    // The clock's share of this screen, as on the reference output.
                    readonly property real fit: Theme.fit(win.screen)

                    // Takes the click that wakes the display, so it does not
                    // land on whatever is underneath.
                    MouseArea {
                        anchors.fill: parent
                    }

                    FittedStage {
                        id: stage

                        fit: win.fit

                        property date now: new Date()
                        property bool placed: false

                        // The first place needs the stage's size, which
                        // arrives with the compositor's configure, after
                        // creation, one side at a time.
                        onWidthChanged: stage.placeOnce()
                        onHeightChanged: stage.placeOnce()

                        function placeOnce() {
                            if (!stage.placed && stage.width > 0 && stage.height > 0) {
                                stage.placed = true;
                                stage.place();
                            }
                        }

                        function place() {
                            stage.now = new Date();
                            const m = Theme.saverMargin;
                            const w = Math.max(0, stage.width - clock.width - m * 2);
                            const h = Math.max(0, stage.height - clock.height - m * 2);
                            clock.x = m + Math.floor(Math.random() * (w + 1));
                            clock.y = m + Math.floor(Math.random() * (h + 1));
                        }

                        // Until one fade before the next minute turns, so the
                        // new time is up as it does; too close to it, the
                        // minute after.
                        function untilNextTick() {
                            const left = 60000 - (Date.now() % 60000);
                            return left > Theme.saverFadeMs + 50 ? left - Theme.saverFadeMs : left + 60000 - Theme.saverFadeMs;
                        }

                        // The clock moves with each minute: a still picture
                        // is what a screensaver is against.
                        Timer {
                            id: tick

                            interval: stage.untilNextTick()
                            running: true

                            onTriggered: {
                                hop.start();
                                tick.interval = stage.untilNextTick();
                                tick.restart();
                            }
                        }

                        SequentialAnimation {
                            id: hop

                            NumberAnimation {
                                target: clock
                                property: "opacity"
                                to: 0
                                duration: Theme.saverFadeMs
                                easing.type: Easing.InQuad
                            }
                            ScriptAction {
                                script: stage.place()
                            }
                            NumberAnimation {
                                target: clock
                                property: "opacity"
                                to: 1
                                duration: Theme.saverFadeMs
                                easing.type: Easing.OutQuad
                            }
                        }

                        // The lock screen's clock (date over the time, day
                        // before month, Inter) and nothing else: no card,
                        // no surface, ink on black. The screen is meant to
                        // show nothing but these two lines.
                        Column {
                            id: clock

                            spacing: Theme.px(4)

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(stage.now, "ddd d MMM")
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.saverDateSize
                                font.weight: Font.Medium
                                color: Theme.saverDate
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(stage.now, "HH:mm")
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.saverTimeSize
                                font.weight: Font.DemiBold
                                color: Theme.saverTime
                            }
                        }
                    }
                }
            }
        }
    }
}
