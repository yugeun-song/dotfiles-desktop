pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// One widget: the calendar popup's card (the bar's surface and its one
// line), its content drawn in reference pixels and scaled to the card
// (Widgets.scaleFor), so it keeps its share of every screen. On the desktop a
// click opens the widget's own options, the weather's being its place panel
// (the user, 2026-11-05); in the editor the editor takes the pointer.
Item {
    id: card

    // { id, kind, size, options, x, y, w, h }, from Widgets.rects.
    required property var rect
    required property real k
    required property ShellScreen screen
    property bool clickable: true

    width: card.rect.w
    height: card.rect.h

    Rectangle {
        anchors.fill: parent
        radius: Math.round(Theme.widgetRadius * card.k)
        color: Theme.surfaceBg
        border.width: Theme.surfaceBorder
        border.color: Theme.surfaceLine
    }

    // A faint lift under the pointer: it can be clicked.
    Rectangle {
        anchors.fill: parent
        radius: Math.round(Theme.widgetRadius * card.k)
        visible: card.clickable && tap.containsMouse
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.03)
    }

    Component {
        id: clockView

        ClockWidget {
            size: card.rect.size
            options: card.rect.options
        }
    }

    Component {
        id: calendarView

        CalendarWidget {
            size: card.rect.size
            options: card.rect.options
            // The card's hover, for the day under the pointer.
            pointer: tap.containsMouse ? Qt.point(tap.mouseX / card.k, tap.mouseY / card.k) : null
        }
    }

    Component {
        id: weatherView

        WeatherWidget {
            size: card.rect.size
            options: card.rect.options
        }
    }

    Component {
        id: systemView

        SystemWidget {
            size: card.rect.size
            options: card.rect.options
        }
    }

    // The card's own size in reference pixels, so the content fills it to
    // the pixel whatever the grid's rounding.
    Loader {
        width: card.width / card.k
        height: card.height / card.k
        scale: card.k
        transformOrigin: Item.TopLeft
        sourceComponent: ({ clock: clockView, calendar: calendarView, weather: weatherView,
                            system: systemView })[card.rect.kind] ?? null
    }

    // Over the content, which takes no click.
    MouseArea {
        id: tap

        anchors.fill: parent
        visible: card.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (card.rect.kind === "weather")
                Weather.togglePanel(card.screen);
            else
                Widgets.openOptions(card.screen?.name ?? "", card.rect.id);
        }
    }
}
