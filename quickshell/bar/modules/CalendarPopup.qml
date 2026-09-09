pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The month, opened by hovering the clock.
//
// Same construction as MediaPopup and for the same reason: anchored to the
// item that opened it, in the bar's own colours, with no gap under the bar.
Item {
    id: root

    property Item anchorItem: root.parent

    // Two hover sources -- the clock and the month itself -- and the union
    // decides, so crossing from one into the other does not close it.
    property bool anchorHovered: false
    property bool cardHovered: false

    readonly property bool active: root.anchorHovered || root.cardHovered

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom

    property bool shown: false

    onActiveChanged: {
        if (root.active) {
            hide.stop();
            root.shown = true;
        } else {
            hide.restart();
        }
    }

    // A grace period on the way out, so crossing from the clock into the month
    // does not close it in the frame between the two.
    Timer {
        id: hide

        interval: 200
        onTriggered: root.shown = false
    }

    Loader {
        active: root.shown

        sourceComponent: PopupWindow {
            visible: true
            color: "transparent"
            grabFocus: false
            implicitWidth: card.implicitWidth
            implicitHeight: card.implicitHeight

            anchor {
                window: root.QsWindow.window
                item: root.anchorItem
                rect.x: 0
                rect.y: 0
                rect.width: root.anchorItem?.width ?? 0
                rect.height: root.anchorItem?.height ?? 0
                edges: root.edge
                gravity: root.edge
            }

            Rectangle {
                id: card

                // Contents plus the same pad on every side, which is what
                // makes the four margins equal without a size to maintain.
                implicitWidth: month.implicitWidth + Theme.popupPad * 2
                implicitHeight: month.implicitHeight + Theme.popupPad * 2
                radius: Theme.surfaceRadius
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                CalendarMonth {
                    id: month

                    anchors.centerIn: parent
                }

                HoverHandler {
                    onHoveredChanged: root.cardHovered = hovered
                }
            }
        }
    }
}
