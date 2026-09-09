pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

// The workspaces, as numbers, with the sliding indicator behind them.
//
// Always ten, and always the ten the current workspace falls in: 1 to 10, then
// 11 to 20, and so on. The row is therefore the same width whatever is open,
// which is the point -- built from the workspaces that happened to exist, it
// grew and shrank as windows opened and closed, and the number being aimed at
// moved out from under the pointer between one glance and the next.
//
// The indicator stretches as it travels and settles back to one cell, with a
// shadow under it that deepens with the stretch. The timings and the tint are
// the ones this bar has always used: 520 ms in the direction of travel and
// 150 ms behind it, so the leading edge arrives first and the trailing edge
// catches up, which is what makes it read as one object moving rather than two
// edges sliding.
Item {
    id: root

    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? 1
    readonly property int groupSize: 10

    // The ten the current workspace sits in. A named workspace has a negative
    // id -- the scratchpad is one -- and does not belong to any ten, so the
    // row stays on whichever group it was showing.
    property int firstId: 1
    readonly property int lastId: root.firstId + root.groupSize - 1

    // Fixed cells, because the indicator is positioned by arithmetic over them
    // and a cell that sized to its own digits would put it in the wrong place
    // for every workspace after the first double-digit one.
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
        // Crossing into another ten replaces every number in the row, so
        // sliding between them would animate the indicator across cells that
        // are not the ones it left or arrived at.
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

    // How far the indicator is stretched beyond a single cell, 0 at rest and 1
    // when it spans a couple of them mid-travel. The trail is tinted by this so
    // a settled indicator stays flat and only a moving one picks up the
    // lighter smear.
    readonly property real stretch: Math.min(1, Math.max(0, (root.slideRight - root.slideLeft - root.cellWidth) / (root.stride * 2)))
    readonly property color trailTint: Qt.lighter(Theme.fg, 1 + root.stretch * 0.6)

    Rectangle {
        id: indicatorShadow

        x: indicator.x
        // One pixel, not two. The shadow is the only thing in the bar that
        // reaches below its row, and at two it was enough to make the whole
        // left side read as sitting lower than the right.
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

    // Scrolling the row walks the workspaces, which is how this bar has always
    // worked.
    WheelHandler {
        id: wheel

        // A touchpad sends one gesture as a stream of small deltas followed by
        // a kinetic tail, so acting on each event walks several workspaces for
        // one flick. A notch is 120, and only a full notch moves.
        property real notch: 0

        // The bounds the keyboard walk uses, so a wheel and Ctrl+Super+H land
        // in the same place. MIN_WORKSPACE and MAX_WORKSPACE in
        // hypr/config/keybinds.lua hold the same two.
        readonly property int minWorkspace: 1
        readonly property int maxWorkspace: 100

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            wheel.notch += event.angleDelta.y;
            if (Math.abs(wheel.notch) < 120)
                return;
            // Read before the accumulator is cleared, or the direction is lost
            // and every notch scrolls the same way.
            const step = wheel.notch > 0 ? -1 : 1;
            wheel.notch = 0;

            const current = Hyprland.focusedWorkspace?.id ?? 0;
            if (current < wheel.minWorkspace)
                return;

            // An absolute target rather than a relative step. Hyprland treats
            // "-1" and "+1" as a walk that wraps, so one more notch at the
            // first workspace crosses the whole set and lands on the last.
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
                    // Three weights for three states, which is what tells an
                    // occupied workspace from an empty one without a mark.
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
                    // In Lua syntax: hl.dispatch wraps what it is given, and
                    // anything that is not a call evaluates to nil and is
                    // refused with nothing reaching here to say so.
                    onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${cell.id}})`)
                }
            }
        }
    }
}
