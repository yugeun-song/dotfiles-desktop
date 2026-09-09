import QtQuick
import Quickshell
import qs.services

// The menu bar.
//
// Two groups and nothing in the middle. The left is whose window you are in,
// the right is what the machine is doing, and the centre is left empty because
// that is where Island hangs -- a separate surface, so that it can be taller
// than the bar without the bar claiming that height as its exclusive zone.
//
// The old bar had three groups and a centring problem with it: the middle had
// to be measured against whichever side was wider or it drifted under one of
// them. Nothing here is centred, so none of that arithmetic survives.
PanelWindow {
    id: root

    required property var modelData

    readonly property string previewEdge: Quickshell.env("BAR_PREVIEW") ?? ""
    readonly property bool preview: root.previewEdge !== ""
    readonly property bool atBottom: root.previewEdge === "bottom"
    readonly property int previewOffset: Number(Quickshell.env("BAR_PREVIEW_OFFSET") ?? 0)

    screen: root.modelData
    color: "transparent"
    implicitHeight: Theme.barHeight
    exclusiveZone: root.preview ? 0 : Theme.barHeight

    // In preview the bar sits at an absolute offset, so it must ignore the
    // exclusive zone another shell's bar already claimed. Otherwise the margin
    // stacks on top of that zone and the bar lands too low.
    exclusionMode: root.preview ? ExclusionMode.Ignore : ExclusionMode.Auto

    anchors {
        top: !root.atBottom
        bottom: root.atBottom
        left: true
        right: true
    }

    margins {
        top: root.preview && !root.atBottom ? root.previewOffset : 0
    }

    Component.onCompleted: {
        Theme.barAtBottom = root.atBottom;
    }

    Rectangle {
        anchors.fill: parent
        // Translucent, not the opaque slab the pill rail was. The compositor
        // blurs this layer (hypr/config/rules.lua), so what the wallpaper
        // contributes is a blurred wash rather than detail, and the bar still
        // reads as a surface rather than as text floating on the desktop.
        color: Theme.menuBarBg

        // The one line that says where the bar ends. Without it a translucent
        // bar over a dark wallpaper has no edge at all, and the status items
        // look like they are sitting on the desktop.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: root.atBottom ? undefined : parent.bottom
            anchors.top: root.atBottom ? parent.top : undefined
            height: Math.max(1, Theme.px(1))
            color: Theme.menuBarLine
        }

        // The left group, in order of how fixed each part is: the system
        // badge, then the workspaces, then the name of whatever has focus.
        // The two that never change width come first, so the one that does
        // cannot move them.
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.menuTitleGap

            SystemBadge {
                anchors.verticalCenter: parent.verticalCenter
            }

            Workspaces {
                anchors.verticalCenter: parent.verticalCenter
            }

            AppTitle {
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // What is playing, in the middle of the bar. Centred on the screen
        // rather than between the two groups, so it does not move when either
        // of them changes width.
        MediaChip {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        StatusItems {
            anchors.right: parent.right
            anchors.rightMargin: Theme.edgeMarginRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
