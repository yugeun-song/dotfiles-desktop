import QtQuick
import Quickshell
import qs.services

PanelWindow {
    id: root

    required property var modelData

    readonly property string previewEdge: Quickshell.env("BAR_PREVIEW") ?? ""
    readonly property bool preview: root.previewEdge !== ""
    readonly property bool atBottom: root.previewEdge === "bottom"
    readonly property int previewOffset: Number(Quickshell.env("BAR_PREVIEW_OFFSET") ?? 0)

    // Keeping the centre truly centred means both sides must be treated as if
    // they were the wider one; otherwise the middle drifts and eventually
    // runs under whichever side grew.
    readonly property int sideWidth: Math.max(leftSection.implicitWidth, rightSection.implicitWidth)
    readonly property int centerRoom: Math.max(0, root.width - (root.sideWidth + Theme.edgeMargin + Theme.gap) * 2)

    screen: root.modelData
    color: "transparent"
    implicitHeight: Theme.barHeight
    exclusiveZone: root.preview ? 0 : Theme.barHeight

    // In preview the bar sits at an absolute offset, so it must ignore the
    // exclusive zone another shell's bar already claimed. Otherwise the
    // margin stacks on top of that zone and the bar lands too low.
    exclusionMode: root.preview ? ExclusionMode.Ignore : ExclusionMode.Auto

    anchors {
        top: !root.atBottom
        bottom: root.atBottom
        left: true
        right: true
    }

    // Lets the preview sit directly under another shell's bar instead of
    // overlapping it. Ignored once the bar owns the top edge for real.
    margins {
        top: root.preview && !root.atBottom ? root.previewOffset : 0
    }

    Component.onCompleted: {
        Theme.barAtBottom = root.atBottom;
    }

    // The reference screen used to be handed over here, and on the way out in
    // Component.onDestruction, because docking builds a bar for the laptop
    // panel and tears it down a moment later. Theme picks it from the screen
    // list itself now, so both the handover and the hazard of two bars racing
    // to set it are gone.

    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        Row {
            id: leftSection

            anchors.left: parent.left
            anchors.leftMargin: Theme.edgeMargin
            anchors.verticalCenter: parent.verticalCenter

            // Wider than Theme.gap, which is the spacing inside a group. These
            // three are separate things -- the badge, the readouts, the
            // workspaces -- and at the same gap as the pills within LeftPills
            // they read as one long row.
            spacing: Theme.groupGap

            SystemBadge {
                anchors.verticalCenter: parent.verticalCenter
            }

            LeftPills {
                anchors.verticalCenter: parent.verticalCenter
            }

            Workspaces {
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            id: centerSection

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            WindowList {
                anchors.verticalCenter: parent.verticalCenter
                maxWidth: Math.max(0, root.centerRoom - media.implicitWidth - Theme.gap)
            }

            MediaInfo {
                id: media

                anchors.verticalCenter: parent.verticalCenter
            }
        }

        SystemPills {
            id: rightSection

            anchors.right: parent.right
            anchors.rightMargin: Theme.edgeMarginRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
