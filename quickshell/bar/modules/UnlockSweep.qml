pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// The unlock as a phone's: the lock screen swept up off the desktop (the
// user, 2026-10-26). hyprlock fades in and, at the unlock, lets the session
// go at once (hyprlock.conf), so the sweep is drawn here. While the
// compositor says the session is locked, this screen is captured now and
// then, the lock screen being all it then shows; an overlay the lock hides
// holds the last capture, so at the unlock it covers the desktop as the lock
// screen did, and is drawn up off the screen. Nothing is made unless a lock
// was seen, and all of it goes with the sweep.
Scope {
    id: root

    required property ShellScreen screen

    // KeyFeed's: hypridle, lock.sh and the compositor's answer all reach it.
    readonly property bool locked: KeyFeed.locked
    // The compositor has said so: only then is a capture the lock screen, not
    // the desktop before hyprlock covered it.
    property bool confirmed: false
    property bool sweeping: false

    onLockedChanged: {
        if (root.locked) {
            root.confirmed = false;
            confirm.restart();
            return;
        }
        confirm.stop();
        if (root.confirmed && (sheetLoader.item?.ready ?? false))
            root.sweeping = true;
        root.confirmed = false;
    }

    onSweepingChanged: {
        if (root.sweeping)
            sheetLoader.item?.sweep();
    }

    // A bar started mid-lock asks too.
    Component.onCompleted: {
        if (root.locked)
            confirm.start();
    }

    // Asked until it says so, then not again for this lock.
    Timer {
        id: confirm

        interval: Theme.unlockConfirmMs
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!probe.running)
                probe.running = true;
        }
    }

    Process {
        id: probe

        command: ["hyprctl", "locked"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "true" && root.locked) {
                    root.confirmed = true;
                    confirm.stop();
                }
            }
        }
    }

    LazyLoader {
        id: sheetLoader

        active: root.confirmed || root.sweeping

        PanelWindow {
            id: sheet

            readonly property bool ready: shot.hasContent

            function sweep(): void {
                sweepUp.restart();
            }

            screen: root.screen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:unlock"
            // The desktop takes the pointer from the first moment.
            mask: Region {}

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            ScreencopyView {
                id: shot

                width: sheet.width
                height: sheet.height
                captureSource: root.screen
                live: false
                paintCursor: false
                // Fades as it goes, gone seven tenths of the way up, as a
                // toast fades by its width (NotificationToasts.qml).
                opacity: Math.max(0, 1 + shot.y / (sheet.height * 0.7))
            }

            // The capture is a second old at most when the unlock comes. Not
            // at once: the view takes a moment to be ready to record.
            Timer {
                interval: Theme.unlockCaptureMs
                running: root.locked && root.confirmed
                repeat: true
                onTriggered: shot.captureFrame()
            }

            // A toast's exit: from rest, then away. Easing off from a fast
            // first frame moved the whole screen half its height in 50 ms,
            // and a frame the unlock's own redraw held back showed as a jump.
            // Quartic, not the toast's cubic, at the same length: held a
            // moment longer, then pulled harder (the user, 2026-10-29: the
            // pace was right, the pull wanted more).
            NumberAnimation {
                id: sweepUp

                target: shot
                property: "y"
                from: 0
                to: -sheet.height
                duration: Theme.unlockSweepMs
                easing.type: Easing.InQuart
                onFinished: root.sweeping = false
            }
        }
    }
}
