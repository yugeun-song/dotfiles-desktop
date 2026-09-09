pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// The focused window's application name.
//
// No File/Edit/View after it. Wayland has no global menu protocol, so a bar
// can only show what an application exported over D-Bus -- which Qt and KDE
// applications do and Chrome, Firefox, kitty and foot do not. Menus for a
// third of what is running is worse than never promising them.
//
// Last in the left group, after the badge and the workspaces: those two are
// fixed points and this is the one thing there whose width is decided by
// whatever has focus. Ahead of them it moved both every time focus crossed
// between a short name and a long one.
Item {
    id: root

    readonly property var focusedWindow: {
        const windows = Hyprland.focusedWorkspace?.toplevels?.values ?? [];
        return windows.find(w => w.activated) ?? null;
    }

    readonly property string appId: root.focusedWindow?.wayland?.appId
                                    ?? root.focusedWindow?.lastIpcObject?.class ?? ""
    readonly property var entry: root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null
    // The desktop entry's name is the one a person would recognise -- "Visual
    // Studio Code" rather than "code-oss". The class is the fallback, and an
    // empty workspace has neither.
    readonly property string appName: root.entry?.name ?? root.appId
    readonly property string windowTitle: root.focusedWindow?.title ?? ""

    // Capped, not fixed. Nothing follows it on the bar, so a short name needs
    // no padding out; a very long one still has to stop before it reaches the
    // island in the centre.
    // A pixel of slack past the measurement. TextMetrics reports the ink and
    // Text needs a shade more than that to lay the same string out, so a width
    // of exactly ceil(metrics.width) put the elide one pixel short and "kitty"
    // came out as "kit...".
    implicitWidth: Math.min(Math.ceil(metrics.width) + Theme.px(2), Theme.appNameWidth)
    implicitHeight: Theme.barHeight

    TextMetrics {
        id: metrics

        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        font.weight: Font.DemiBold
        text: root.appName
    }

    // Set apart by weight alone, which is what macOS does and why it reads as
    // a title rather than as a heading.
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
        // The class and the desktop entry name are both strings this machine
        // did not choose. Nothing here ever wanted markup.
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
