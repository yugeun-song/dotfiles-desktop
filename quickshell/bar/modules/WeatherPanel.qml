pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The weather's place, chosen on a panel laid out as the Displays panel is
// (Super+O; the user, 2026-10-27, after a dropdown read awkwardly): a card
// over the dimmed screen whose bar was clicked, with a search field, the
// places Open-Meteo's geocoder finds by that name (Weather.find, through
// weather.sh) as two-line rows, the place the weather is for checked, and
// Seoul, the default, offered back while another place is kept. A pick is
// kept by weather.sh in the bar's state, never in the repository, and its
// weather fetched at once. Typing goes to the field; Up and Down, or Ctrl+P
// and Ctrl+N as in a terminal, walk the rows; Enter takes one; Esc or a click
// beside the card closes the panel, and so does a lock.
Scope {
    id: root

    property int highlighted: 0
    property string typed: ""
    // Enter pressed before the places for what was typed came: taken then.
    property bool enterPending: false

    readonly property bool asking: Weather.query.length >= 2

    // The places found while a name is asked, else where the weather is now
    // and, while that is a kept place, Seoul back.
    readonly property var rows: {
        if (root.asking)
            return Weather.places.map(p => ({ label: p.name, detail: root.where(p), checked: root.isHere(p), place: p }));
        const now = [{ label: Weather.place !== "" ? Weather.place : "Seoul", detail: "Now", checked: true }];
        if ((Weather.data?.source ?? "default") === "saved")
            now.push({ label: "Seoul", detail: "Default", checked: false, reset: true });
        return now;
    }

    // Under the rows: what the search has come to, while no row says it.
    readonly property string status: {
        if (!root.asking || Weather.places.length > 0)
            return "";
        if (Weather.searching || Weather.answered !== Weather.query)
            return "Searching…";
        return Weather.searchError !== "" ? "Search failed" : "No place found";
    }

    // Region and country, the region left out where it repeats the name.
    function where(place): string {
        const parts = [];
        if (place.admin && place.admin !== place.name)
            parts.push(place.admin);
        if (place.country)
            parts.push(place.country);
        return parts.join(", ");
    }

    // Within about a hundred metres of the weather's own coordinates.
    function isHere(place): bool {
        const lat = Weather.data?.lat;
        const lon = Weather.data?.lon;
        return typeof lat === "number" && typeof lon === "number"
               && Math.abs(place.lat - lat) < 0.001 && Math.abs(place.lon - lon) < 0.001;
    }

    function close() {
        Weather.panelOpen = false;
    }

    function take(row) {
        if (row?.reset)
            Weather.forget();
        else if (row?.place)
            Weather.choose(row.place);
        root.close();
    }

    function enter() {
        // Asked at once, the typing pause not waited out, and taken when the
        // places come.
        if (ask.running || Weather.answered !== root.typed.trim()) {
            ask.stop();
            root.enterPending = true;
            Weather.find(root.typed);
            return;
        }
        root.take(root.rows[root.highlighted]);
    }

    function step(by) {
        const n = root.rows.length;
        if (n > 0)
            root.highlighted = (root.highlighted + by + n) % n;
    }

    // Each opening starts empty, on the place the weather is for.
    Connections {
        target: Weather

        function onPanelOpenChanged() {
            root.highlighted = 0;
            root.typed = "";
            root.enterPending = false;
            ask.stop();
            Weather.find("");
        }

        function onAnsweredChanged() {
            if (!root.enterPending || Weather.answered !== root.typed.trim())
                return;
            root.enterPending = false;
            if (Weather.places.length > 0)
                root.take(root.rows[0]);
        }
    }

    // A lock takes the keyboard; the panel would hold it again after.
    Connections {
        target: KeyFeed

        function onLockedChanged() {
            if (KeyFeed.locked)
                root.close();
        }
    }

    // Asked a moment after the typing stops, not at every letter: each ask
    // is a request to the geocoder.
    Timer {
        id: ask

        interval: 250
        onTriggered: Weather.find(root.typed)
    }

    LazyLoader {
        active: Weather.panelOpen

        PanelWindow {
            id: win

            // The screen whose bar was clicked, else the focused one.
            screen: Weather.panelScreen ?? Screens.focused

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:weather"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property real fit: Theme.fit(win.screen)

            FittedStage {
                fit: win.fit

                // Dim backdrop; clicking it closes the panel.
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.78)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(64), Theme.weatherPanelWidth)
                    height: body.implicitHeight + Theme.displaysPad * 2
                    radius: Theme.surfaceRadius
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine

                    // Swallows clicks so a near miss does not hit the backdrop.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: body

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.displaysPad
                        spacing: Theme.px(14)

                        Item {
                            width: parent.width
                            height: title.implicitHeight

                            Text {
                                id: title

                                text: "Weather"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(22)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Esc to close"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(13)
                                color: Theme.surfaceFaint
                            }
                        }

                        Text {
                            width: parent.width
                            text: "Search for a place to show its weather"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(13)
                            color: Theme.muted
                        }

                        Rectangle {
                            width: parent.width
                            height: Theme.px(44)
                            radius: Theme.px(12)
                            color: Theme.surfaceRaised

                            Text {
                                id: glyph

                                x: Theme.px(14)
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.iconSearch
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.px(16)
                                color: Theme.muted
                            }

                            TextInput {
                                id: field

                                anchors.left: glyph.right
                                anchors.leftMargin: Theme.px(10)
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.px(14)
                                anchors.verticalCenter: parent.verticalCenter
                                focus: true
                                clip: true
                                maximumLength: 100
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(15)
                                color: Theme.fg
                                selectionColor: Theme.accentIndigo
                                selectedTextColor: Theme.ink

                                onTextChanged: {
                                    root.typed = field.text;
                                    root.highlighted = 0;
                                    ask.restart();
                                }

                                // The hint, gone at the first letter, a
                                // composing Hangul syllable's included.
                                Text {
                                    anchors.fill: parent
                                    visible: field.text === "" && field.preeditText === ""
                                    text: "City or town"
                                    font: field.font
                                    color: Theme.muted
                                }

                                Keys.onPressed: event => {
                                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                                    switch (event.key) {
                                    case Qt.Key_Escape:
                                        root.close();
                                        break;
                                    case Qt.Key_Down:
                                        root.step(1);
                                        break;
                                    case Qt.Key_Up:
                                        root.step(-1);
                                        break;
                                    // Ctrl+N/P step; plain N/P go to the field.
                                    case Qt.Key_N:
                                        if (!ctrl)
                                            return;
                                        root.step(1);
                                        break;
                                    case Qt.Key_P:
                                        if (!ctrl)
                                            return;
                                        root.step(-1);
                                        break;
                                    case Qt.Key_Return:
                                    case Qt.Key_Enter:
                                        root.enter();
                                        break;
                                    default:
                                        return;
                                    }
                                    event.accepted = true;
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.px(2)

                            Repeater {
                                model: root.rows

                                Rectangle {
                                    id: row

                                    required property var modelData
                                    required property int index

                                    width: parent.width
                                    height: Theme.px(52)
                                    radius: Theme.px(8)
                                    color: root.highlighted === row.index ? Theme.surfaceHover : "transparent"

                                    Column {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.px(14)
                                        anchors.right: check.left
                                        anchors.rightMargin: Theme.px(10)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.px(2)

                                        // Names come from the geocoder; never markup.
                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                            text: row.modelData.label
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.px(15)
                                            font.weight: row.modelData.checked ? Font.DemiBold : Font.Normal
                                            color: Theme.fg
                                        }

                                        Text {
                                            width: parent.width
                                            visible: text !== ""
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                            text: row.modelData.detail
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.px(12)
                                            color: Theme.muted
                                        }
                                    }

                                    Text {
                                        id: check

                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.px(14)
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: row.modelData.checked
                                        text: Theme.iconCheck
                                        font.family: Theme.iconFont
                                        font.pixelSize: Theme.px(16)
                                        color: Theme.accentIndigo
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.highlighted = row.index
                                        onClicked: root.take(row.modelData)
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.status !== ""
                            width: parent.width
                            leftPadding: Theme.px(14)
                            text: root.status
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(13)
                            color: Theme.muted
                        }
                    }
                }
            }
        }
    }
}
