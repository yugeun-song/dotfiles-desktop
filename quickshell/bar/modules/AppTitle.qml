pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The focused window's application name, last in the left group because its
// width changes with every focus change. Named only on the bar of the screen
// holding that window: on every bar it sat beside screens not showing it.
// Found through keyboard focus, not the focused workspace, which follows the
// pointer: resting it on the other screen's bar blanked the name mid-typing.
//
// No global menu: Wayland has no protocol for one, and only Qt/KDE apps export
// menus over D-Bus (Chrome, Firefox, kitty and foot do not).
Item {
    id: root

    // Set by Bar.qml.
    property var screen: null

    readonly property var focusedWindow: (Screens.windowScreen?.name ?? "") === (root.screen?.name ?? "")
                                         ? Screens.focusedWindow : null

    readonly property string appId: root.focusedWindow?.wayland?.appId
                                    ?? root.focusedWindow?.lastIpcObject?.class ?? ""
    readonly property var entry: root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null
    // Desktop entry name ("Visual Studio Code", not "code-oss"), else the class.
    readonly property string appName: root.entry?.name ?? root.appId

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
}
