pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

Row {
    id: root

    // A workspace can hold far more windows than the bar has room for. The
    // focused one keeps its title; the rest collapse to icons, and whatever
    // still does not fit is summarised by a single counter chip.
    //
    // The order is the workspace's own and never changes with focus. Moving
    // the focused window to the front would mean the two windows you switch
    // between trade places every time you switch, so the chip you are aiming
    // at is never where you last saw it.
    property int maxWidth: 100000

    readonly property var windows: Hyprland.focusedWorkspace?.toplevels?.values ?? []
    readonly property var focusedWindow: root.windows.find(w => w.activated) ?? null
    readonly property var others: root.windows.filter(w => w !== root.focusedWindow)

    readonly property int iconOnlyWidth: Theme.iconSize + Theme.px(3) + Theme.windowChipPadding * 2
    readonly property int stride: root.iconOnlyWidth + root.spacing

    readonly property int leadWidth: root.focusedWindow ? focusedProbe.implicitWidth + root.spacing : 0
    readonly property int othersRoom: Math.max(0, root.maxWidth - root.leadWidth)
    readonly property int fitCount: Math.max(0, Math.floor(root.othersRoom / root.stride))
    readonly property bool overflowing: root.others.length > root.fitCount
    readonly property int shownCount: root.overflowing ? Math.max(0, root.fitCount - 1) : root.others.length
    readonly property int hiddenCount: root.others.length - root.shownCount

    // What is actually drawn, still in the workspace's order. Width is taken
    // from the unfocused windows at the end, never from the focused one: the
    // title you are looking at is the one that must not disappear.
    readonly property var kept: {
        const keep = root.others.slice(0, root.shownCount);
        return root.windows.filter(w => w === root.focusedWindow || keep.indexOf(w) !== -1);
    }

    spacing: Theme.px(4)

    // Measured, never shown. leadWidth has to know how wide the focused chip
    // wants to be before the row is laid out, and the real chip is inside the
    // repeater where nothing can reach it by id. A Row does not position an
    // invisible child, so this costs no space.
    WindowChip {
        id: focusedProbe

        visible: false
        toplevel: root.focusedWindow
        showCaption: true
    }

    Repeater {
        model: root.kept

        WindowChip {
            required property var modelData

            toplevel: modelData
            showCaption: modelData === root.focusedWindow
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
