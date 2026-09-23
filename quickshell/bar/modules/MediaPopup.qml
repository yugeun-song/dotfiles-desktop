pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The player card, opened by hovering the media chip.
//
// A PopupWindow anchored to the chip, not a layer surface: a layer surface is
// placed after other exclusive zones regardless of exclusion mode (measured),
// so it could not sit flush against the bar.
Item {
    id: root

    property Item anchorItem: root.parent

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    // No gap: reads as the bar opening, not a floating card.
    readonly property int clearance: 0

    Loader {
        active: Media.open && Media.present

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
                rect.y: -root.clearance
                rect.width: root.anchorItem?.width ?? 0
                rect.height: (root.anchorItem?.height ?? 0) + root.clearance * 2
                edges: root.edge
                gravity: root.edge
            }

            Rectangle {
                id: card

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
                    onHoveredChanged: Media.cardHovered = hovered
                }
            }
        }
    }
}
