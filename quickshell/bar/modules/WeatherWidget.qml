import QtQuick
import qs.services

// The weather widget, in WidgetCard's reference pixels: the temperature huge
// (HeroText), the place, the sky's glyph and the day's high and low small
// around it (the user, 2026-11-05: what a widget stresses huge, the rest
// small); the medium card adds what the reading says besides, small too.
// The bar's own reading (services/Weather.qml, fetched for the bar every
// fifteen minutes), so a widget asks for nothing more. A click opens the
// place panel, the weather's own control (WidgetCard).
Item {
    id: root

    required property string size
    required property var options

    readonly property bool wide: root.size !== "small"
    readonly property color tint: Theme.weatherColor(Weather.code, Weather.day)

    function degrees(v: int): string {
        return v > -999 ? `${v}°` : "--";
    }

    Item {
        id: main

        readonly property real gap: 8

        x: Theme.widgetPad
        y: Theme.widgetPad
        width: (root.wide ? root.width / 2 : root.width) - Theme.widgetPad * 2
        height: root.height - Theme.widgetPad * 2

        Text {
            id: placeText

            width: parent.width - sky.width - 6
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: Weather.place !== "" ? Weather.place : "Weather"
            font.family: Theme.uiFont
            font.pixelSize: Theme.widgetTitleSize
            font.weight: Font.DemiBold
            color: Theme.fg
        }

        Text {
            id: sky

            anchors.right: parent.right
            anchors.verticalCenter: placeText.verticalCenter
            text: Weather.ready ? Theme.weatherIcon(Weather.code, Weather.day) : ""
            font.family: Theme.iconFont
            // 18, then larger three times (the user, 2026-11-05).
            font.pixelSize: 28
            color: root.tint
        }

        HeroText {
            y: placeText.height + main.gap
            width: parent.width
            height: parent.height - placeText.height - foot.height - main.gap * 2
            text: Weather.ready ? root.degrees(Weather.temp) : String.fromCodePoint(0x2014)
            probe: "00°"
        }

        Text {
            id: foot

            anchors.bottom: parent.bottom
            width: parent.width
            elide: Text.ElideRight
            text: !Weather.ready ? (Weather.unknown !== "" ? Weather.unknown : "Waiting for the weather")
                                 : `H ${root.degrees(Weather.todayMax)}  L ${root.degrees(Weather.todayMin)}`
            font.family: Theme.uiFont
            font.pixelSize: Theme.widgetSmallText + 1
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.65)
        }
    }

    // The medium card's right half: what the reading says besides.
    Column {
        visible: root.wide && Weather.ready
        x: root.width / 2 + Theme.widgetPad / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.width / 2 - Theme.widgetPad * 1.5
        spacing: 10

        Repeater {
            model: [
                { label: "Feels like", value: root.degrees(Weather.feels) },
                { label: "Humidity", value: Weather.humidity >= 0 ? `${Weather.humidity}%` : "--" },
                { label: "Wind", value: Weather.wind >= 0 ? `${Math.round(Weather.wind * 10) / 10} m/s` : "--" }
            ]

            Item {
                id: fact

                required property var modelData

                width: parent.width
                height: factLabel.implicitHeight

                Text {
                    id: factLabel

                    text: fact.modelData.label
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.widgetSmallText + 1
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
                }

                Text {
                    anchors.right: parent.right
                    text: fact.modelData.value
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.widgetSmallText + 1
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                    color: Theme.fg
                }
            }
        }
    }
}
