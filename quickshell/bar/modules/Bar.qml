import QtQuick
import Quickshell
import qs.services

// The menu bar: focus on the left, machine status on the right, the island
// centred on the screen. A hover opens only the clock's month and the grown
// island, as the user chose: no tooltips.
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

            // No edge line: on a dark wallpaper the line marked the bar off
            // more than the user wanted (2026-10-27).

            // Fixed-width parts first, so nothing after them can shift them: the
            // tray's icons come and go with their applications, and the
            // focused app's name changes with focus.
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

                TrayIcons {
                    anchors.verticalCenter: parent.verticalCenter
                }

                AppTitle {
                    id: appTitle

                    anchors.verticalCenter: parent.verticalCenter
                    screen: root.modelData
                }
            }

            // Centred on the screen, not between the groups, so it holds still
            // as they resize; its room is twice the way to the nearer group,
            // less gaps (no loop: neither group depends on it). Its widths are
            // shares of the idle width between the groups, the app's name and
            // the clock counted at their widest (Theme.appNameWidth,
            // StatusItems.clockSlack), so neither focus nor the minutes move
            // them. On a whole pixel, which anchors can miss by a half: the
            // grown island is placed by its corner and must meet it exactly.
            MediaChip {
                x: Math.round((parent.width - width) / 2)
                anchors.verticalCenter: parent.verticalCenter
                screenName: root.modelData?.name ?? ""

                room: Math.max(0, parent.width
                                  - 2 * Math.max(Theme.edgeMargin + leftGroup.width,
                                                 Theme.edgeMarginRight + statusGroup.width)
                                  - 2 * Theme.groupGap)
                idle: Math.max(0, parent.width
                                  - Theme.edgeMargin - (leftGroup.width - appTitle.width + Theme.appNameWidth)
                                  - Theme.edgeMarginRight - (statusGroup.width + statusGroup.clockSlack)
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
