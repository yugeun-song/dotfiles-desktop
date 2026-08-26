pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Item {
    id: root

    readonly property int chipWidth: Theme.chipWidth
    readonly property int chipSpacing: Theme.chipSpacing
    readonly property int chipStride: root.chipWidth + root.chipSpacing
    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? 1

    readonly property int groupSize: Theme.workspaceCount
    readonly property int groupIndex: Math.max(0, Math.floor((root.activeId - 1) / root.groupSize))
    readonly property int firstId: root.groupIndex * root.groupSize + 1
    readonly property int lastId: root.firstId + root.groupSize - 1

    readonly property real targetLeft: (root.activeId - root.firstId) * root.chipStride
    readonly property real targetRight: root.targetLeft + root.chipWidth

    property int previousId: root.activeId
    property bool movingRight: true
    property real slideLeft: root.targetLeft
    property real slideRight: root.targetRight

    implicitWidth: Theme.workspaceCount * root.chipWidth + (Theme.workspaceCount - 1) * root.chipSpacing
    implicitHeight: Theme.pillHeight

    function firstIdFor(id: int): int {
        return Math.max(0, Math.floor((id - 1) / root.groupSize)) * root.groupSize + 1;
    }

    function relayout(animate: bool) {
        const first = root.firstIdFor(root.activeId);
        const left = (root.activeId - first) * root.chipStride;
        snap.enabled = !animate;
        root.slideLeft = left;
        root.slideRight = left + root.chipWidth;
        snap.enabled = false;
    }

    onActiveIdChanged: {
        const groupChanged = root.firstIdFor(root.activeId) !== root.firstIdFor(root.previousId);
        root.movingRight = root.activeId > root.previousId;
        root.previousId = root.activeId;
        root.relayout(!groupChanged);
    }

    Component.onCompleted: root.relayout(false)

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

    // How far the indicator is stretched beyond a single chip, 0 at rest and
    // 1 when it spans a couple of chips mid-travel. The trail is tinted by
    // this so a settled indicator stays flat yellow and only a moving one
    // picks up the lighter smear.
    readonly property real stretch: Math.min(1, Math.max(0, (root.slideRight - root.slideLeft - root.chipWidth) / (root.chipStride * 2)))
    readonly property color trailTint: Qt.lighter(Theme.yellow, 1 + root.stretch * 0.6)

    Rectangle {
        id: indicatorShadow

        x: indicator.x
        // One pixel, not two. The shadow is the only thing in the bar that
        // reaches below the pills, and at two it was enough to make the whole
        // left side read as sitting lower than the right.
        y: Theme.px(1)
        width: indicator.width
        height: indicator.height
        radius: indicator.radius
        visible: indicator.visible
        color: Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.18 + root.stretch * 0.22)
        scale: 1 + root.stretch * 0.04
    }

    Rectangle {
        id: indicator

        x: root.slideLeft
        width: Math.max(root.chipWidth, root.slideRight - root.slideLeft)
        height: Theme.pillHeight
        radius: Theme.pillRadius
        visible: root.activeId >= root.firstId && root.activeId <= root.lastId

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0.0
                color: root.movingRight ? root.trailTint : Theme.yellow
            }

            GradientStop {
                position: 0.45
                color: Theme.yellow
            }

            GradientStop {
                position: 1.0
                color: root.movingRight ? Theme.yellow : root.trailTint
            }
        }
    }

    WheelHandler {
        id: wheel

        // A touchpad sends one gesture as a stream of small deltas followed by
        // a kinetic tail, so acting on each event walks several workspaces for
        // one flick. A notch is 120, and only a full notch moves.
        property real notch: 0

        // The bounds the keyboard walk uses, so a wheel and Ctrl+Super+H land in
        // the same place. hypr/scripts/workspace-walk.sh holds the same two.
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

            // A special workspace has a negative id. Stepping from one lands on
            // whatever number happens to be next, which is not a step from
            // anywhere the user is.
            const current = Hyprland.focusedWorkspace?.id ?? 0;
            if (current < wheel.minWorkspace)
                return;

            // An absolute target rather than a relative step. Hyprland treats
            // "-1" and "+1" as a walk that wraps, so one more notch at the first
            // workspace crosses the whole set and lands on the last. That is not
            // a step, and it happens at exactly the moment someone is checking
            // whether they have reached the end.
            const target = Math.min(wheel.maxWorkspace,
                                    Math.max(wheel.minWorkspace, current + step));
            if (target === current)
                return;
            Hyprland.dispatch(`hl.dsp.focus({workspace = ${target}})`);
        }
    }

    Row {
        anchors.fill: parent
        spacing: root.chipSpacing

        Repeater {
            model: Theme.workspaceCount

            Item {
                id: chip

                required property int index

                readonly property int workspaceId: root.firstId + chip.index
                readonly property real centerX: chip.index * root.chipStride + root.chipWidth / 2
                readonly property bool litByIndicator: indicator.visible && chip.centerX >= root.slideLeft && chip.centerX <= root.slideRight
                readonly property var workspace: {
                    const list = Hyprland.workspaces?.values ?? [];
                    return list.find(w => w.id === chip.workspaceId) ?? null;
                }
                readonly property bool occupied: (chip.workspace?.toplevels?.values?.length ?? 0) > 0

                width: root.chipWidth
                height: Theme.pillHeight

                Text {
                    anchors.centerIn: parent
                    text: chip.workspaceId
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.textSize
                    font.weight: chip.litByIndicator ? Font.Bold : Font.Medium
                    color: chip.litByIndicator ? Theme.ink : chip.occupied ? Theme.fg : Theme.muted
                }

                HoverHandler {
                    id: hover
                }

                Tooltip {
                    anchorItem: chip
                    active: hover.hovered
                    text: {
                        const windows = chip.workspace?.toplevels?.values ?? [];
                        const head = `Workspace ${chip.workspaceId}`;
                        if (windows.length === 0)
                            return `${head}\nempty`;
                        const titles = windows.slice(0, 5).map(w => `  ${Theme.shorten(w.title ?? "untitled", 44)}`);
                        if (windows.length > 5)
                            titles.push(`  and ${windows.length - 5} more`);
                        return [`${head}   ${windows.length} window${windows.length === 1 ? "" : "s"}`, ...titles].join("\n");
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${chip.workspaceId}})`)
                }
            }
        }
    }
}
