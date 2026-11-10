pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.services

// The tone of the bar, its widgets and every panel (services/Appearance.qml;
// the user, 2026-11-11), laid out as the tablet's panel: the four tones as
// pictures of this desktop (the wallpaper, the tone's bar with the island,
// and a panel over it), the rule the two wallpaper tones follow, and in the
// custom tone its three colours, each set from the wallpaper's own colours,
// a few fixed ones or by hex. A pick applies at once, so the desktop round
// the panel is the preview. Opened by Super+Shift+A, the control centre's
// tile, the bar's menu and the wallpaper picker. Esc or a click beside the
// card closes it, and so does a lock.
Scope {
    id: root

    function close(): void {
        Appearance.panelOpen = false;
    }

    // A lock takes the keyboard; the panel would hold it again after.
    Connections {
        target: KeyFeed

        function onLockedChanged() {
            if (KeyFeed.locked)
                root.close();
        }
    }

    readonly property var tones: [
        { id: "black", label: "Black" },
        { id: "white", label: "White" },
        { id: "auto", label: "Automatic" },
        { id: "custom", label: "Custom" }
    ]

    // Fixed colours beside the wallpaper's: the two tones' own for a
    // background or text, the bar's accents for an accent.
    readonly property var neutrals: ["#000000", "#0f111b", "#1b1c36", "#2c2c2d", "#686f9a", "#a4a4a9", "#ecf0c1", "#f4f4f0", "#ffffff"]
    readonly property var accents: ["#7aa2f7", "#7dcfff", "#73daca", "#9ece6a", "#e0af68", "#ff9e64", "#f7768e", "#bb9af7"]

    function said(mode: string): string {
        switch (mode) {
        case "white":
            return "The same colours in white.";
        case "auto":
            return `Black or white after the wallpaper: ${Appearance.tone === "light" ? "white" : "black"} for this one.`;
        case "custom":
            return "Colours drawn from the wallpaper; each can be set by hand.";
        }
        return "The bar's own black.";
    }

    LazyLoader {
        active: Appearance.panelOpen

        PanelWindow {
            id: win

            screen: Appearance.panelScreen ?? Screens.focused

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:appearance"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property real fit: Theme.fit(win.screen)
            // The custom colour open for editing: "bg", "fg", "accent" or "".
            property string editing: ""

            FittedStage {
                fit: win.fit

                // A clear backdrop (only the session dialog dims); a click closes.
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
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

                        Column {
                            width: parent.width
                            spacing: Theme.px(2)

                            Text {
                                text: "Appearance"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(22)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Text {
                                text: "The bar, its widgets and every panel."
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(12)
                                color: Theme.muted
                            }
                        }

                        Row {
                            id: toneRow

                            readonly property real side: Math.floor((toneRow.width - 3 * toneRow.spacing) / 4)

                            width: parent.width
                            // Room above for the chosen one's ring.
                            topPadding: Theme.px(4)
                            spacing: Theme.px(12)

                            Repeater {
                                model: root.tones

                                // One tone as this desktop would look in it: the
                                // wallpaper, the tone's bar across it with the
                                // island in black and the words, and a panel with
                                // text and the accent.
                                Item {
                                    id: tone

                                    required property var modelData
                                    readonly property bool chosen: Appearance.mode === tone.modelData.id
                                    readonly property var p: Appearance.paletteFor(tone.modelData.id, Appearance.rule, Appearance.custom, Appearance.reading)

                                    width: toneRow.side
                                    height: shot.height + Theme.px(8) + name.implicitHeight

                                    // The state role: the accent round the chosen one, 2 px.
                                    Rectangle {
                                        x: -Theme.px(3)
                                        y: -Theme.px(3)
                                        width: shot.width + Theme.px(6)
                                        height: shot.height + Theme.px(6)
                                        radius: Theme.px(13)
                                        color: "transparent"
                                        border.width: Math.max(2, Theme.px(2))
                                        border.color: tone.chosen ? Theme.menuHighlight : area.containsMouse ? Theme.surfaceLine : "transparent"
                                    }

                                    Item {
                                        id: shot

                                        width: toneRow.side
                                        height: Math.round(toneRow.side * 0.62)

                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: mask
                                            maskThresholdMin: 0.5
                                            maskSpreadAtMin: 1.0
                                        }

                                        // Under a picture not read yet.
                                        Rectangle {
                                            anchors.fill: parent
                                            color: Theme.surfaceWell
                                        }

                                        // One decode for the four: the same source and size.
                                        Image {
                                            anchors.fill: parent
                                            source: `file://${Appearance.wallpaper}`
                                            sourceSize: Qt.size(Theme.px(240), Theme.px(150))
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }

                                        Rectangle {
                                            id: miniBar

                                            width: parent.width
                                            height: Math.max(4, Math.round(parent.height * 0.13))
                                            color: tone.p.bg

                                            Rectangle {
                                                x: Math.round(parent.width * 0.06)
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Math.round(parent.width * 0.14)
                                                height: Math.max(1, Math.round(parent.height * 0.24))
                                                radius: height / 2
                                                color: tone.p.fg
                                            }

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: Math.round(parent.width * 0.22)
                                                height: Math.round(parent.height * 0.62)
                                                radius: height / 2
                                                color: Theme.islandColor
                                            }

                                            Rectangle {
                                                anchors.right: parent.right
                                                anchors.rightMargin: Math.round(parent.width * 0.06)
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Math.round(parent.width * 0.10)
                                                height: Math.max(1, Math.round(parent.height * 0.24))
                                                radius: height / 2
                                                color: tone.p.fg
                                                opacity: 0.7
                                            }
                                        }

                                        Rectangle {
                                            x: Math.round(parent.width * 0.52)
                                            y: Math.round(parent.height * 0.26)
                                            width: Math.round(parent.width * 0.40)
                                            height: Math.round(parent.height * 0.58)
                                            radius: Math.round(height * 0.14)
                                            color: tone.p.bg
                                            border.width: 1
                                            border.color: Qt.rgba(tone.p.fg.r, tone.p.fg.g, tone.p.fg.b, 0.12)

                                            Column {
                                                x: Math.round(parent.width * 0.14)
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: Math.max(1, Math.round(parent.height * 0.12))

                                                Rectangle {
                                                    width: Math.round(shot.width * 0.24)
                                                    height: Math.max(1, Math.round(shot.height * 0.05))
                                                    radius: height / 2
                                                    color: tone.p.fg
                                                }

                                                Rectangle {
                                                    width: Math.round(shot.width * 0.17)
                                                    height: Math.max(1, Math.round(shot.height * 0.05))
                                                    radius: height / 2
                                                    color: tone.p.muted
                                                }

                                                Rectangle {
                                                    width: Math.round(shot.width * 0.12)
                                                    height: Math.max(2, Math.round(shot.height * 0.08))
                                                    radius: height / 2
                                                    color: tone.p.accent
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: mask

                                        width: shot.width
                                        height: shot.height
                                        radius: Theme.px(10)
                                        color: "black"
                                        visible: false
                                        layer.enabled: true
                                    }

                                    Text {
                                        id: name

                                        anchors.top: shot.bottom
                                        anchors.topMargin: Theme.px(8)
                                        anchors.horizontalCenter: shot.horizontalCenter
                                        text: tone.modelData.label
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(13)
                                        font.weight: tone.chosen ? Font.DemiBold : Font.Medium
                                        color: tone.chosen ? Theme.fg : Theme.surfaceDim
                                    }

                                    MouseArea {
                                        id: area

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            win.editing = "";
                                            Appearance.setMode(tone.modelData.id);
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: root.said(Appearance.mode)
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(12)
                            color: Theme.muted
                        }

                        Rectangle {
                            visible: Appearance.mode === "auto" || Appearance.mode === "custom"
                            width: parent.width
                            height: Theme.surfaceBorder
                            color: Theme.surfaceSeparator
                        }

                        MirrorChoice {
                            visible: Appearance.mode === "auto" || Appearance.mode === "custom"
                            label: "Tone"
                            value: Appearance.rule
                            choices: [{ label: "Like the wallpaper", value: "match" }, { label: "Opposite", value: "opposite" }]
                            onPicked: value => Appearance.setRule(value)
                        }

                        Column {
                            visible: Appearance.mode === "custom"
                            width: parent.width

                            Repeater {
                                model: [
                                    { role: "bg", label: "Background" },
                                    { role: "fg", label: "Text" },
                                    { role: "accent", label: "Accent" }
                                ]

                                // A custom colour: its name, whether the wallpaper
                                // gave it, its swatch; open, the colours to take it
                                // from and its hex.
                                Column {
                                    id: row

                                    required property var modelData
                                    readonly property string role: row.modelData.role
                                    readonly property color value: Appearance.palette[row.role === "fg" ? "fg" : row.role === "accent" ? "accent" : "bg"]
                                    readonly property bool byHand: Appearance.validHex(Appearance.custom[row.role])
                                    readonly property bool open: win.editing === row.role
                                    readonly property var offered: Appearance.swatches.concat(row.role === "accent" ? root.accents : root.neutrals)

                                    width: parent?.width ?? 0

                                    Item {
                                        width: parent.width
                                        height: Theme.px(44)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Theme.px(10)
                                            color: rowArea.containsMouse || row.open ? Theme.surfaceHover : "transparent"
                                        }

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.px(10)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.modelData.label
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.px(14)
                                            color: Theme.fg
                                        }

                                        Row {
                                            anchors.right: parent.right
                                            anchors.rightMargin: Theme.px(10)
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.px(10)

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: row.byHand ? Appearance.hexOf(row.value) : "From the wallpaper"
                                                font.family: row.byHand ? Theme.monoFont : Theme.uiFont
                                                font.pixelSize: Theme.px(12)
                                                color: Theme.muted
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Theme.px(24)
                                                height: Theme.px(24)
                                                radius: Theme.px(7)
                                                color: row.value
                                                border.width: Theme.surfaceBorder
                                                border.color: Theme.surfaceLine
                                            }
                                        }

                                        MouseArea {
                                            id: rowArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.editing = row.open ? "" : row.role
                                        }
                                    }

                                    Column {
                                        visible: row.open
                                        width: parent.width
                                        leftPadding: Theme.px(10)
                                        rightPadding: Theme.px(10)
                                        topPadding: Theme.px(6)
                                        bottomPadding: Theme.px(12)
                                        spacing: Theme.px(12)

                                        Flow {
                                            width: parent.width - Theme.px(20)
                                            spacing: Theme.px(8)

                                            Repeater {
                                                model: row.offered

                                                Rectangle {
                                                    id: swatch

                                                    required property string modelData
                                                    readonly property bool here: Appearance.hexOf(row.value) === swatch.modelData.toLowerCase()

                                                    width: Theme.px(26)
                                                    height: Theme.px(26)
                                                    radius: Theme.px(7)
                                                    color: swatch.modelData
                                                    border.width: swatch.here ? Math.max(2, Theme.px(2)) : Theme.surfaceBorder
                                                    border.color: swatch.here ? Theme.menuHighlight : swatchArea.containsMouse ? Theme.surfaceDim : Theme.surfaceLine

                                                    MouseArea {
                                                        id: swatchArea

                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Appearance.setCustom(row.role, swatch.modelData)
                                                    }
                                                }
                                            }
                                        }

                                        Row {
                                            spacing: Theme.px(10)

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Hex"
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.px(13)
                                                color: Theme.muted
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Theme.px(110)
                                                height: Theme.px(30)
                                                radius: Theme.px(8)
                                                color: Theme.surfaceWell

                                                // Taken once it is a whole colour, kept as typed
                                                // till then; Enter or leaving it puts back the
                                                // colour in use if what is there is none.
                                                TextInput {
                                                    id: hex

                                                    anchors.fill: parent
                                                    anchors.leftMargin: Theme.px(10)
                                                    anchors.rightMargin: Theme.px(10)
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    text: Appearance.hexOf(row.value)
                                                    maximumLength: 7
                                                    validator: RegularExpressionValidator {
                                                        regularExpression: /#?[0-9a-fA-F]{0,6}/
                                                    }
                                                    font.family: Theme.monoFont
                                                    font.pixelSize: Theme.px(13)
                                                    color: Theme.fg
                                                    selectionColor: Theme.menuHighlight
                                                    selectedTextColor: Theme.menuHighlightText
                                                    selectByMouse: true
                                                    onTextEdited: {
                                                        const typed = hex.text.startsWith("#") ? hex.text : `#${hex.text}`;
                                                        if (Appearance.validHex(typed))
                                                            Appearance.setCustom(row.role, typed);
                                                    }
                                                    onEditingFinished: hex.text = Qt.binding(() => Appearance.hexOf(row.value))
                                                    Keys.onEscapePressed: event => {
                                                        root.close();
                                                        event.accepted = true;
                                                    }
                                                }
                                            }

                                            PillButton {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: row.byHand
                                                label: "From the wallpaper"
                                                onClicked: Appearance.setCustom(row.role, "")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            visible: Appearance.mode === "custom" && Object.keys(Appearance.custom).length > 0
                            width: parent.width
                            height: reset.height

                            PillButton {
                                id: reset

                                anchors.right: parent.right
                                label: "All from the wallpaper"
                                onClicked: {
                                    win.editing = "";
                                    Appearance.resetCustom();
                                }
                            }
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    focus: true

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }
}
