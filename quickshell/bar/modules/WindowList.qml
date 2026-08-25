pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

Row {
    id: root

    // A workspace can hold far more windows than the bar has room for. The
    // focused one keeps its title; the rest collapse to icons, and whatever
    // still does not fit is summarised by a single counter chip.
    property int maxWidth: 100000

    readonly property var windows: Hyprland.focusedWorkspace?.toplevels?.values ?? []
    readonly property var focusedWindow: root.windows.find(w => w.activated) ?? null
    readonly property var others: root.windows.filter(w => w !== root.focusedWindow)

    readonly property int iconOnlyWidth: Theme.iconSize + Theme.px(3) + Theme.windowChipPadding * 2
    readonly property int stride: root.iconOnlyWidth + root.spacing

    readonly property int leadWidth: root.focusedWindow ? focusedChip.implicitWidth + root.spacing : 0
    readonly property int othersRoom: Math.max(0, root.maxWidth - root.leadWidth)
    readonly property int fitCount: Math.max(0, Math.floor(root.othersRoom / root.stride))
    readonly property bool overflowing: root.others.length > root.fitCount
    readonly property int shownCount: root.overflowing ? Math.max(0, root.fitCount - 1) : root.others.length
    readonly property int hiddenCount: root.others.length - root.shownCount

    spacing: Theme.px(4)


    WindowChip {
        id: focusedChip

        visible: root.focusedWindow !== null
        toplevel: root.focusedWindow
        showCaption: true
    }

    Repeater {
        model: root.shownCount

        WindowChip {
            required property int index

            toplevel: root.others[index] ?? null
            showCaption: false
        }
    }

    Rectangle {
        visible: root.overflowing && root.hiddenCount > 0
        implicitHeight: Theme.pillHeight
        implicitWidth: counter.implicitWidth + Theme.windowChipPadding * 2
        radius: Theme.pillRadius
        color: Theme.bgAlt
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: counter

            anchors.centerIn: parent
            text: `+${root.hiddenCount}`
            font.family: Theme.uiFont
            font.pixelSize: Theme.textSize
            font.weight: Font.Medium
            color: Theme.muted
        }

        HoverHandler {
            id: overflowHover
        }

        Tooltip {
            anchorItem: parent
            active: overflowHover.hovered
            text: {
                const rest = root.others.slice(root.shownCount);
                const lines = [`${rest.length} more window${rest.length === 1 ? "" : "s"}`];
                for (const w of rest.slice(0, 10))
                    lines.push(`  ${Theme.shorten(w.title ?? "untitled", 46)}`);
                if (rest.length > 10)
                    lines.push(`  and ${rest.length - 10} more`);
                return lines.join("\n");
            }
        }
    }
}
