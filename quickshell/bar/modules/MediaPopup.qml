pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The player, opened by hovering the chip in the bar.
//
// A PopupWindow anchored to the chip rather than a layer surface of its own.
// A layer surface is placed after other surfaces' exclusive zones whatever its
// exclusion mode -- measured, not assumed -- so one could never be put where
// this needs to be. A popup is anchored to an item instead, which is exactly
// the relationship this has to the chip.
Item {
    id: root

    property Item anchorItem: root.parent

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    // The popup hangs from the bar's edge with no gap: it should read as the
    // bar opening rather than as a card floating under it.
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
                // The bar's own colours. A card the bar opened that is a
                // different dark reads as a separate window sitting under it.
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
