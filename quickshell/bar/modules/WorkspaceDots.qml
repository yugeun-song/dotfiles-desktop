pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

// Workspaces, as the menu bar can carry them.
//
// macOS has no workspace indicator at all -- Spaces are invisible until you
// ask for them -- so there is nothing to copy here, and the old Workspaces
// module cannot come across unchanged: it is a row of numbered chips at pill
// height, which is taller than this bar and reads as ten buttons in a place
// where everything else is a glyph.
//
// So it becomes what a status item is: a small thing that says where you are
// and gets out of the way. A dot per workspace, the current one drawn as a
// filled bar rather than a dot so it is found without counting, and an
// occupied one dimmer than the current but brighter than an empty one. That
// is the same three states the chips carried, in the space a menu bar has.
Row {
    id: root

    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? 1
    readonly property int count: Theme.workspaceCount

    // Which workspaces have something on them. Hyprland reports a workspace
    // only once it exists, so an id missing from this list is empty rather
    // than unknown.
    readonly property var occupied: {
        const busy = {};
        for (const w of (Hyprland.workspaces?.values ?? [])) {
            if ((w.toplevels?.values?.length ?? 0) > 0)
                busy[w.id] = true;
        }
        return busy;
    }

    spacing: Theme.dotGap
    anchors.verticalCenter: parent?.verticalCenter ?? undefined

    Repeater {
        model: root.count

        Item {
            id: cell

            required property int index
            readonly property int id: cell.index + 1
            readonly property bool current: cell.id === root.activeId
            readonly property bool busy: root.occupied[cell.id] === true

            // The cell is a fixed width whatever the dot inside it does, so
            // the row does not reflow as focus moves and the dot beside the
            // one you are aiming at stays where you last saw it.
            implicitWidth: Theme.dotActiveWidth
            implicitHeight: Theme.barHeight

            Rectangle {
                anchors.centerIn: parent
                width: cell.current ? Theme.dotActiveWidth : Theme.dotSize
                height: Theme.dotSize
                radius: height / 2
                color: cell.current ? Theme.fg : cell.busy ? Theme.muted
                                                           : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.18)

                Behavior on width {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            }

            HoverHandler {
                id: hover
            }

            Tooltip {
                anchorItem: cell
                active: hover.hovered
                text: cell.current ? `Workspace ${cell.id}, current`
                                   : cell.busy ? `Workspace ${cell.id}, in use\nClick to switch`
                                               : `Workspace ${cell.id}, empty\nClick to switch`
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // The same dispatcher and the same Lua form Workspaces.qml
                // used: hl.dispatch wraps what it is given, so anything that
                // is not a call evaluates to nil and is refused with nothing
                // reaching here to say so.
                onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${cell.id}})`)
            }
        }
    }
}
