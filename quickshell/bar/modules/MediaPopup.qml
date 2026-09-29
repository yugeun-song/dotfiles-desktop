pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The player card, opened by hovering the media chip. Built like
// CalendarPopup: the open state is this bar's own, so the card opens under
// the chip the pointer is on and on no other screen, while what it shows
// (Media) is the same everywhere.
//
// A PopupWindow anchored to the chip, not a layer surface: a layer surface is
// placed after other exclusive zones regardless of exclusion mode (measured),
// so it could not sit flush against the bar.
Item {
    id: root

    property Item anchorItem: root.parent

    // Open while either the chip or the card is hovered.
    property bool anchorHovered: false
    property bool cardHovered: false

    readonly property bool active: root.anchorHovered || root.cardHovered

    property bool shown: false

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    // No gap: reads as the bar opening, not a floating card.
    readonly property int clearance: 0

    onActiveChanged: {
        if (root.active) {
            hide.stop();
            root.shown = true;
        } else {
            hide.restart();
        }
    }

    // Close grace: the pointer leaves one surface a frame before entering the other.
    Timer {
        id: hide

        interval: 200
        onTriggered: root.shown = false
    }

    Loader {
        active: root.shown && Media.present

        // A card torn down under the pointer (the title blanks between
        // tracks) reports no exit; a hover left set would reopen it with the
        // next track after the pointer had gone.
        onActiveChanged: {
            if (!active)
                root.cardHovered = false;
        }

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
                rect.y: -root.clearance
                rect.width: root.anchorItem?.width ?? 0
                rect.height: (root.anchorItem?.height ?? 0) + root.clearance * 2
                edges: root.edge
                gravity: root.edge
            }

            Rectangle {
                id: card

                scale: popup.fit
                transformOrigin: Item.TopLeft
                implicitWidth: Theme.mediaCardWidth
                implicitHeight: player.implicitHeight + Theme.popupPad * 2
                radius: Theme.surfaceRadius
                // The bar's colours, or it reads as a separate window.
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                MediaPlayer {
                    id: player

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.popupPad
                    anchors.rightMargin: Theme.popupPad
                }

                HoverHandler {
                    onHoveredChanged: root.cardHovered = hovered
                }
            }
        }
    }
}
