pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The month, opened by hovering the clock. Built like MediaPopup.
Item {
    id: root

    property Item anchorItem: root.parent

    // Open while either the clock or the card is hovered.
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

    // Grace period for crossing from the clock into the card.
    Timer {
        id: hide

        interval: 200
        onTriggered: root.shown = false
    }

    Loader {
        active: root.shown

        sourceComponent: PopupWindow {
            id: popup

            // The card's share of the bar's screen, as on the reference output.
            readonly property real fit: Theme.fit(root.QsWindow.window?.screen)

            visible: true
            color: "transparent"
            grabFocus: false
            implicitWidth: Math.round(card.implicitWidth * popup.fit)
            implicitHeight: Math.round(card.implicitHeight * popup.fit)

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

                scale: popup.fit
                transformOrigin: Item.TopLeft
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
