pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// One screen's widgets (modules/WidgetDesk.qml makes one per screen), drawn
// only where they can be seen, the user's rule (2026-11-04: only what is
// shown runs): on a workspace with no tiled or fullscreen window, unlocked,
// outside the edit mode. Otherwise no window is made at all, and with it go
// the clocks, the quotes asked for and the textures.
//
// One window round all of a screen's widgets, under the windows (the Bottom
// layer), not one per widget: each window is a render thread and a GL
// surface of its own, and a whole-screen one a whole screen of buffer; the
// widgets usually sit together, so their bounding box is small.
Scope {
    id: root

    required property ShellScreen screen

    readonly property var monitor: Hyprland.monitorFor(root.screen)
    readonly property var workspace: root.monitor?.activeWorkspace ?? null

    // A tiled or fullscreen window hides the desktop; floating ones leave it
    // in view round them. A window not described yet (its IPC object is read
    // after it opens, WidgetDesk) counts as tiled: hidden until known.
    readonly property bool covered: {
        const ws = root.workspace;
        if (!ws)
            return false;
        if (ws.hasFullscreen)
            return true;
        for (const t of ws.toplevels?.values ?? []) {
            const ipc = t.lastIpcObject;
            if (!ipc || typeof ipc.floating !== "boolean" || !ipc.floating || (ipc.fullscreen ?? 0) > 0)
                return true;
        }
        return false;
    }

    // A screen pulled out is null here for a moment before this goes (the
    // HDMI monitor's unplug, 2026-11-05, raised a TypeError on each).
    readonly property real k: Widgets.scaleFor(root.screen?.width ?? 0, root.screen?.height ?? 0)
    // Under the bar, which is scaled by the screen's fit as every panel is.
    readonly property real top: Math.ceil(Theme.barHeight * Theme.fit(root.screen))
    readonly property var rects: Widgets.loaded && root.screen
        ? Widgets.rects(Widgets.itemsFor(root.screen.name), root.screen.width, root.screen.height, root.top) : []
    readonly property var bounds: {
        if (root.rects.length === 0)
            return { x: 0, y: 0, w: 1, h: 1 };
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const r of root.rects) {
            x0 = Math.min(x0, r.x);
            y0 = Math.min(y0, r.y);
            x1 = Math.max(x1, r.x + r.w);
            y1 = Math.max(y1, r.y + r.h);
        }
        return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    }

    readonly property bool shown: Widgets.loaded && !Widgets.editing && !root.covered && !KeyFeed.locked
        && root.rects.length > 0

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: desk

            screen: root.screen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:widgets"

            anchors {
                top: true
                left: true
            }

            margins {
                top: root.bounds.y
                left: root.bounds.x
            }

            implicitWidth: root.bounds.w
            implicitHeight: root.bounds.h

            // In on its own, as the desktop comes into view.
            Item {
                anchors.fill: parent
                opacity: 0
                Component.onCompleted: opacity = 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                Repeater {
                    model: root.rects

                    WidgetCard {
                        required property var modelData

                        rect: modelData
                        k: root.k
                        screen: root.screen
                        x: modelData.x - root.bounds.x
                        y: modelData.y - root.bounds.y
                    }
                }
            }
        }
    }

    LazyLoader {
        active: Widgets.editing && Widgets.loaded

        WidgetEditor {
            screen: root.screen
            k: root.k
            top: root.top
            rects: root.rects
        }
    }
}
