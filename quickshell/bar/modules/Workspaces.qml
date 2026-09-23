pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

// Workspace numbers with a sliding indicator. Always the ten containing the
// current workspace (1-10, 11-20, ...), so the row never changes width and a
// target never moves under the pointer.
//
// The indicator's edges animate at different speeds (150 ms / 520 ms) so it
// stretches toward the destination and reads as one moving object.
Item {
    id: root

    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? 1
    readonly property int groupSize: 10

    // Special workspaces have negative ids; the row keeps its current group.
    property int firstId: 1
    readonly property int lastId: root.firstId + root.groupSize - 1

    // Fixed cells: the indicator is positioned by arithmetic over them.
    readonly property int cellWidth: Theme.workspaceMinWidth
    readonly property int cellGap: Theme.px(2)
    readonly property int stride: root.cellWidth + root.cellGap

    readonly property real targetLeft: (root.activeId - root.firstId) * root.stride
    readonly property real targetRight: root.targetLeft + root.cellWidth

    property int previousId: root.activeId
    property bool movingRight: true
    property real slideLeft: root.targetLeft
    property real slideRight: root.targetRight

    implicitWidth: root.groupSize * root.cellWidth + (root.groupSize - 1) * root.cellGap
    implicitHeight: Theme.barHeight

    function groupFor(id: int): int {
        return Math.floor((id - 1) / root.groupSize) * root.groupSize + 1;
    }

    function relayout(animate: bool) {
        const left = (root.activeId - root.firstId) * root.stride;
        snap.enabled = !animate;
        root.slideLeft = left;
        root.slideRight = left + root.cellWidth;
        snap.enabled = false;
    }

    onActiveIdChanged: {
        if (root.activeId < 1)
            return;
        const group = root.groupFor(root.activeId);
        const groupChanged = group !== root.firstId;
        root.movingRight = root.activeId > root.previousId;
        root.previousId = root.activeId;
        root.firstId = group;
        // Changing group relabels every cell, so snap instead of sliding.
        root.relayout(!groupChanged);
    }

    Component.onCompleted: {
        if (root.activeId >= 1)
            root.firstId = root.groupFor(root.activeId);
        root.relayout(false);
    }

    QtObject {
        id: snap

        property bool enabled: false
    }

    Behavior on slideLeft {
        enabled: !snap.enabled

        NumberAnimation {
            duration: root.movingRight ? 520 : 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on slideRight {
        enabled: !snap.enabled

        NumberAnimation {
            duration: root.movingRight ? 150 : 520
            easing.type: Easing.OutCubic
        }
    }

    // 0 at rest, 1 when stretched over ~2 extra cells; drives trail tint and shadow.
    readonly property real stretch: Math.min(1, Math.max(0, (root.slideRight - root.slideLeft - root.cellWidth) / (root.stride * 2)))
    readonly property color trailTint: Qt.lighter(Theme.fg, 1 + root.stretch * 0.6)

    Rectangle {
        id: indicatorShadow

        x: indicator.x
        // 1 px: at 2 px the left side of the bar read as sitting lower.
        y: indicator.y + Theme.px(1)
        width: indicator.width
        height: indicator.height
        radius: indicator.radius
        visible: indicator.visible
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.18 + root.stretch * 0.22)
        scale: 1 + root.stretch * 0.04
    }

    Rectangle {
        id: indicator

        x: root.slideLeft
        y: Theme.barInset
        width: Math.max(root.cellWidth, root.slideRight - root.slideLeft)
        height: parent.height - Theme.barInset * 2
        radius: height / 2
        visible: root.activeId >= root.firstId && root.activeId <= root.lastId

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0.0
                color: root.movingRight ? root.trailTint : Theme.fg
            }

            GradientStop {
                position: 0.45
                color: Theme.fg
            }

            GradientStop {
                position: 1.0
                color: root.movingRight ? Theme.fg : root.trailTint
            }
        }
    }

    WheelHandler {
        id: wheel

        // Touchpads send many small deltas plus a kinetic tail; act only per
        // full 120-unit notch.
        property real notch: 0

        // Keep in sync with MIN_/MAX_WORKSPACE in hypr/config/keybinds.lua.
        readonly property int minWorkspace: 1
        readonly property int maxWorkspace: 100

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            wheel.notch += event.angleDelta.y;
            if (Math.abs(wheel.notch) < 120)
                return;
            const step = wheel.notch > 0 ? -1 : 1;
            wheel.notch = 0;

            const current = Hyprland.focusedWorkspace?.id ?? 0;
            if (current < wheel.minWorkspace)
                return;

            // Absolute target: Hyprland's relative "-1"/"+1" wraps around.
            const target = Math.min(wheel.maxWorkspace,
                                    Math.max(wheel.minWorkspace, current + step));
            if (target === current)
                return;
            Hyprland.dispatch(`hl.dsp.focus({workspace = ${target}})`);
        }
    }

    Row {
        anchors.fill: parent
        spacing: root.cellGap

        Repeater {
            model: root.groupSize

            Item {
                id: cell

                required property int index
                readonly property int id: root.firstId + cell.index
                readonly property bool current: cell.id === root.activeId
                readonly property bool busy: {
                    const w = (Hyprland.workspaces?.values ?? []).find(x => x.id === cell.id);
                    return (w?.toplevels?.values?.length ?? 0) > 0;
                }

                width: root.cellWidth
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: Theme.barInset
                    anchors.bottomMargin: Theme.barInset
                    radius: height / 2
                    visible: !cell.current
                    color: hover.hovered ? Theme.menuHover : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 110
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    height: Theme.barLineHeight
                    verticalAlignment: Text.AlignVCenter
                    text: `${cell.id}`
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.workspaceTextSize
                    // Current is bolder; occupied vs empty is told by opacity.
                    font.weight: cell.current ? Font.DemiBold : Font.Normal
                    // Dark on the indicator, light off it.
                    color: cell.current ? Theme.bg
                           : cell.busy ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.70)
                                       : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.32)
                }

                HoverHandler {
                    id: hover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // Must be a Lua call expression; anything else evaluates
                    // to nil and is refused silently.
                    onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${cell.id}})`)
                }
            }
        }
    }
}
