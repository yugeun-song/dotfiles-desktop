pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Rectangle {
    id: root

    property var toplevel: null
    property bool showCaption: false

    readonly property string appId: root.toplevel?.wayland?.appId ?? root.toplevel?.lastIpcObject?.class ?? ""
    readonly property var entry: root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null
    readonly property string entryIcon: root.entry?.icon ?? ""
    readonly property string iconSource: Theme.appIcon(root.entryIcon !== "" ? root.entryIcon : root.appId)
    readonly property string appName: root.entry?.name ?? root.appId
    readonly property string windowTitle: root.toplevel?.title ?? ""
    readonly property bool focused: root.toplevel?.activated ?? false

    readonly property int glyphWidth: Theme.iconSize + Theme.px(3)
    readonly property bool captionVisible: root.showCaption || root.iconSource === ""

    implicitHeight: Theme.pillHeight
    implicitWidth: body.implicitWidth + Theme.windowChipPadding * 2
    radius: Theme.pillRadius
    color: root.focused ? Theme.violet : Theme.bgAlt

    Row {
        id: body

        anchors.centerIn: parent
        spacing: root.captionVisible ? Theme.pillGlyphGap : 0

        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconSource !== ""
            source: root.iconSource
            sourceSize.width: root.glyphWidth
            sourceSize.height: root.glyphWidth
            width: root.glyphWidth
            height: root.glyphWidth
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            id: caption

            anchors.verticalCenter: parent.verticalCenter
            visible: root.captionVisible
            width: root.captionVisible ? Math.min(Math.ceil(captionMetrics.width), root.focused ? Theme.windowTitleWidth : Theme.windowNameWidth) : 0
            elide: Text.ElideRight
            text: root.focused && root.windowTitle !== "" ? root.windowTitle : root.appName
            font.family: Theme.uiFont
            font.pixelSize: Theme.textSize
            font.weight: Font.Medium
            color: root.focused ? Theme.fg : Theme.muted
        }
    }

    TextMetrics {
        id: captionMetrics

        font.family: Theme.uiFont
        font.pixelSize: Theme.textSize
        font.weight: Font.Medium
        text: caption.text
    }

    HoverHandler {
        id: hover
    }

    Tooltip {
        anchorItem: root
        active: hover.hovered
        text: {
            const lines = [];
            if (root.appName !== "")
                lines.push(`App       ${root.appName}`);
            if (root.windowTitle !== "")
                lines.push(`Title     ${Theme.shorten(root.windowTitle, 56)}`);
            if (root.appId !== "")
                lines.push(`Class     ${root.appId}`);
            lines.push(root.focused ? "Focused" : "Click to focus");
            return lines.join("\n");
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const address = root.toplevel?.address ?? "";
            if (address !== "")
                Hyprland.dispatch(`hl.dsp.focus({window = "address:${address}"})`);
        }
    }
}
