pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// The focused window's application name, last in the left group because it is
// the only part whose width changes.
//
// No global menu: Wayland has no protocol for one, and only Qt/KDE apps export
// menus over D-Bus (Chrome, Firefox, kitty and foot do not).
Item {
    id: root

    readonly property var focusedWindow: {
        const windows = Hyprland.focusedWorkspace?.toplevels?.values ?? [];
        return windows.find(w => w.activated) ?? null;
    }

    readonly property string appId: root.focusedWindow?.wayland?.appId
                                    ?? root.focusedWindow?.lastIpcObject?.class ?? ""
    readonly property var entry: root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null
    // Desktop entry name ("Visual Studio Code", not "code-oss"), else the class.
    readonly property string appName: root.entry?.name ?? root.appId
    readonly property string windowTitle: root.focusedWindow?.title ?? ""

    // Capped, not fixed, so a long name stops before the centred media chip.
    // +2 px: Text needs slightly more than TextMetrics reports, or "kitty"
    // elides to "kit...".
    implicitWidth: Math.min(Math.ceil(metrics.width) + Theme.px(2), Theme.appNameWidth)
    implicitHeight: Theme.barHeight

    TextMetrics {
        id: metrics

        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        font.weight: Font.DemiBold
        text: root.appName
    }

    // Set apart by weight alone.
    Text {
        id: name

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Theme.barLineHeight
        verticalAlignment: Text.AlignVCenter
        visible: root.appName !== ""
        elide: Text.ElideRight
        text: root.appName
        // Foreign strings; never interpret as markup.
        textFormat: Text.PlainText
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        font.weight: Font.DemiBold
        color: Theme.fg
    }

    HoverHandler {
        id: hover
    }

    Tooltip {
        anchorItem: root
        active: hover.hovered && root.appName !== ""
        text: {
            const lines = [];
            if (root.appName !== "")
                lines.push(`App       ${root.appName}`);
            if (root.windowTitle !== "")
                lines.push(`Title     ${Theme.shorten(root.windowTitle, 56)}`);
            if (root.appId !== "")
                lines.push(`Class     ${root.appId}`);
            return lines.join("\n");
        }
    }
}
