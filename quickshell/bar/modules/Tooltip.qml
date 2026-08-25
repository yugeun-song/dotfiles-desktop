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

    onActiveChanged: {
        if (root.active) {
            hideTimer.stop();
            showTimer.restart();
        } else {
            showTimer.stop();
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

            visible: true
            color: "transparent"
            grabFocus: false
            implicitWidth: body.implicitWidth
            implicitHeight: body.implicitHeight

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

                implicitWidth: label.implicitWidth + Theme.tooltipPadX * 2
                implicitHeight: label.implicitHeight + Theme.tooltipPadY * 2
                radius: Theme.tooltipRadius
                color: Theme.beige

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
                    color: Theme.ink
                }
            }
        }
    }
}
