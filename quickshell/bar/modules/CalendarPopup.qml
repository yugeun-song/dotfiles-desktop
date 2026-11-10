pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The month, opened by hovering the clock. Built like MediaPopup. Its card is
// the desktop's large calendar widget, so the two read as one design (the
// user, 2026-11-05: the bar's month and the widget looked unalike), scaled so
// its cells are 25 of the bar's pixels on the screen's fit, a little larger
// than the 22 the bar's month first drew them at (the user, 2026-11-06); the
// day under the pointer and its distance come with it.
Item {
    id: root

    property Item anchorItem: root.parent

    // Open while either the clock or the card is hovered.
    property bool anchorHovered: false
    property bool cardHovered: false

    readonly property bool active: root.anchorHovered || root.cardHovered

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

            readonly property var screen: root.QsWindow.window?.screen ?? null
            readonly property real fit: Theme.fit(popup.screen)
            readonly property real k: Theme.px(25) * popup.fit / Math.max(1, month.cellSize)

            // Its top right corner where the other panels at the top right
            // stand (ControlCentre, NotificationCentre): notifBarGap below the
            // bar and edgeMarginRight + menuItemPadX in from the screen's
            // edge; under the clock it touched the bar and almost the edge
            // (the user, 2026-11-06: more room above and to the right). Taken
            // into the clock's own coordinates, which the bar scales, when the
            // card opens; the clock holds its place (StatusItems.clockSlack).
            readonly property point corner: {
                const win = root.QsWindow.window;
                const item = root.anchorItem;
                if (!win || !item)
                    return Qt.point(0, 0);
                const x = win.width - (Theme.edgeMarginRight + Theme.menuItemPadX) * popup.fit;
                const y = Theme.barAtBottom ? -Theme.notifBarGap * popup.fit : win.height + Theme.notifBarGap * popup.fit;
                return item.mapFromItem(null, x, y);
            }

            // Room for its shadow (Theme.shadowRoom) on the two sides away from
            // the corner it hangs from: to its left and, under a bar at the
            // top, below it. That corner stays where it was, so the card does
            // too; the shadow's right and top, short at a light from above, are
            // left out. Only the card takes the pointer (mask), so the hover
            // that holds it open is the card's alone.
            readonly property var room: Theme.shadowRoom("panel")
            readonly property int side: Math.round(popup.room.side * popup.fit)
            readonly property int below: Theme.barAtBottom ? 0 : Math.round(popup.room.bottom * popup.fit)

            visible: true
            color: "transparent"
            grabFocus: false
            implicitWidth: popup.side + Math.round(card.width)
            implicitHeight: Math.round(card.height) + popup.below
            mask: Region {
                x: popup.side
                width: Math.round(card.width)
                height: Math.round(card.height)
            }

            anchor {
                window: root.QsWindow.window
                item: root.anchorItem
                rect.x: popup.corner.x
                rect.y: popup.corner.y
                rect.width: 1
                rect.height: 1
                edges: Edges.Top | Edges.Left
                gravity: (Theme.barAtBottom ? Edges.Top : Edges.Bottom) | Edges.Left
                adjustment: PopupAdjustment.None
            }

            SurfaceShadow {
                target: card
                kind: "panel"
            }

            Rectangle {
                id: card

                x: popup.side
                width: month.width * popup.k
                height: month.height * popup.k
                radius: Math.round(Theme.widgetRadius * popup.k)
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                CalendarWidget {
                    id: month

                    width: 2 * Widgets.smallRef + Widgets.gapRef
                    height: 2 * Widgets.smallRef + Widgets.gapRef
                    scale: popup.k
                    transformOrigin: Item.TopLeft
                    size: "large"
                    options: Widgets.optionDefaults.calendar
                    pointer: hover.hovered ? Qt.point(hover.point.position.x / popup.k, hover.point.position.y / popup.k) : null
                }

                // A hand over a day, as the bar's month gave one: the pointer
                // there reads its distance (the user, 2026-11-05).
                HoverHandler {
                    id: hover

                    cursorShape: month.hoveredDay > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onHoveredChanged: root.cardHovered = hovered
                }
            }
        }
    }
}
