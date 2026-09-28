pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Item {
    id: root

    property string text: ""
    property bool active: false
    property Item anchorItem: root.parent

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    readonly property int clearance: Theme.pillMargin + Theme.tooltipGap

    property bool shown: false

    // Skip the hide delay when a menu opens on the same click, or the two
    // surfaces overlap briefly.
    property bool immediate: false

    onActiveChanged: {
        if (root.active) {
            hideTimer.stop();
            showTimer.restart();
            return;
        }
        showTimer.stop();
        if (root.immediate) {
            root.shown = false;
            hideTimer.stop();
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: showTimer

        interval: 260
        onTriggered: root.shown = true
    }

    Timer {
        id: hideTimer

        interval: 90
        onTriggered: root.shown = false
    }

    Loader {
        active: root.shown && root.text !== ""

        sourceComponent: PopupWindow {
            id: popup

            // The tip's share of the bar's screen, as on the reference output.
            readonly property real fit: Theme.fit(root.QsWindow.window?.screen)

            visible: true
            color: "transparent"
            grabFocus: false
            implicitWidth: Math.round(body.implicitWidth * popup.fit)
            implicitHeight: Math.round(body.implicitHeight * popup.fit)

            anchor {
                window: root.QsWindow.window
                item: root.anchorItem
                rect.x: 0
                rect.y: -root.clearance
                rect.width: root.anchorItem?.width ?? 0
                rect.height: (root.anchorItem?.height ?? 0) + root.clearance * 2
                edges: root.edge
                gravity: root.edge
            }

            mask: Region {
                item: null
            }

            Rectangle {
                id: body

                scale: popup.fit
                transformOrigin: Item.TopLeft
                implicitWidth: label.implicitWidth + Theme.tooltipPadX * 2
                implicitHeight: label.implicitHeight + Theme.tooltipPadY * 2
                radius: Theme.tooltipRadius
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                Text {
                    id: label

                    anchors.centerIn: parent
                    text: root.text
                    textFormat: Text.PlainText
                    lineHeight: 1.3
                    horizontalAlignment: Text.AlignLeft
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.textSize
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }
        }
    }
}
