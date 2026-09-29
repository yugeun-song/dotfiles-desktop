import QtQuick
import Quickshell
import qs.services

// The menu bar: focus on the left, machine status on the right, media chip
// centred on the screen.
PanelWindow {
    id: root

    required property var modelData

    readonly property string previewEdge: Quickshell.env("BAR_PREVIEW") ?? ""
    readonly property bool preview: root.previewEdge !== ""
    readonly property bool atBottom: root.previewEdge === "bottom"
    readonly property int previewOffset: Number(Quickshell.env("BAR_PREVIEW_OFFSET") ?? 0)

    // Drawn at the share of the screen the bar has on the reference output:
    // the content is laid out in reference pixels and scaled as one, so every
    // module keeps its proportions without knowing which screen it is on.
    readonly property real fit: Theme.fit(root.screen)
    readonly property int fittedHeight: Math.round(Theme.barHeight * root.fit)

    screen: root.modelData
    color: "transparent"
    implicitHeight: root.fittedHeight
    exclusiveZone: root.preview ? 0 : root.fittedHeight

    // Preview sits at an absolute offset, so ignore other bars' exclusive zones.
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
        // Opaque; hypr/config/rules.lua keeps blur off for this layer.
        color: Theme.menuBarBg

        // Reference pixels, scaled to the window; the bar's own height, not
        // the window's, since the window is already the fitted height.
        FittedStage {
            id: stage

            fit: root.fit
            height: Theme.barHeight

            // Edge line; without it the bar has no edge on a dark wallpaper.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: root.atBottom ? undefined : parent.bottom
                anchors.top: root.atBottom ? parent.top : undefined
                height: Math.max(1, Theme.px(1))
                color: Theme.menuBarLine
            }

            // Fixed-width parts first, so the focused app's name cannot shift them.
            Row {
                id: leftGroup

                anchors.left: parent.left
                anchors.leftMargin: Theme.edgeMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.menuTitleGap

                SystemBadge {
                    anchors.verticalCenter: parent.verticalCenter
                }

                Workspaces {
                    anchors.verticalCenter: parent.verticalCenter
                    screen: root.modelData
                }

                AppTitle {
                    anchors.verticalCenter: parent.verticalCenter
                    screen: root.modelData
                }
            }

            // Centred on the screen, not between the groups, so it holds still as they
            // resize. Its room is twice the distance from centre to the nearer group
            // (less gaps); no loop, since neither group depends on the chip.
            MediaChip {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter

                room: Math.max(0, parent.width
                                  - 2 * Math.max(Theme.edgeMargin + leftGroup.width,
                                                 Theme.edgeMarginRight + statusGroup.width)
                                  - 2 * Theme.groupGap)
            }

            StatusItems {
                id: statusGroup

                anchors.right: parent.right
                anchors.rightMargin: Theme.edgeMarginRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
