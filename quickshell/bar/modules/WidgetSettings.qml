pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The desktop widgets' settings (Super+Ctrl+W, or Settings in the edit
// mode): one layout on every display or one each, and the resets the user
// asked for (2026-11-04), back to the repository's defaults. A reset asks a
// second click, as it forgets what was arranged. Laid out as the weather's
// place panel is; Esc or a click beside the card closes it.
Scope {
    id: root

    // The reset a second click would do now: "", "layout" or "everything".
    property string confirming: ""

    function close() {
        Widgets.settingsOpen = false;
    }

    function ask(which: string): void {
        if (root.confirming === which) {
            root.confirming = "";
            Widgets.reset(which === "everything");
            return;
        }
        root.confirming = which;
        unconfirm.restart();
    }

    Timer {
        id: unconfirm

        interval: 4000
        onTriggered: root.confirming = ""
    }

    Connections {
        target: Widgets

        function onSettingsOpenChanged() {
            root.confirming = "";
        }
    }

    LazyLoader {
        active: Widgets.settingsOpen

        PanelWindow {
            id: win

            screen: Screens.focused
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:widget-settings"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property real fit: Theme.fit(win.screen)

            FittedStage {
                fit: win.fit

                // A clear backdrop (only the session dialog dims); a click closes.
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(64), Theme.widgetOptionsWidth + Theme.px(60))
                    height: body.implicitHeight + Theme.displaysPad * 2
                    radius: Theme.surfaceRadius
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine

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
                        focus: true

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.close();
                                event.accepted = true;
                            }
                        }

                        Item {
                            width: parent.width
                            height: title.implicitHeight

                            Text {
                                id: title

                                text: "Widgets"
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
                            wrapMode: Text.WordWrap
                            text: "Super+Alt+W moves and resizes them; a click on a widget opens its own options."
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(13)
                            color: Theme.muted
                        }

                        Text {
                            text: "DISPLAYS"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(11)
                            font.letterSpacing: Theme.px(2)
                            color: Theme.surfaceFaint
                        }

                        Row {
                            spacing: Theme.px(8)

                            PillButton {
                                label: "The same on every display"
                                primary: Widgets.mode === "mirror"
                                onClicked: Widgets.setMode("mirror")
                            }

                            PillButton {
                                label: "Each display its own"
                                primary: Widgets.mode === "screens"
                                onClicked: Widgets.setMode("screens")
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: Widgets.mode === "mirror"
                                ? "One layout, carried to every display at the same shares of its width and height."
                                : "A display keeps its own layout from its first edit, begun as a copy of the shared one."
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(12)
                            color: Theme.muted
                        }

                        Text {
                            text: "RESET"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(11)
                            font.letterSpacing: Theme.px(2)
                            color: Theme.surfaceFaint
                        }

                        Row {
                            spacing: Theme.px(8)

                            PillButton {
                                label: root.confirming === "layout" ? "Click again to reset" : "Reset the layout"
                                onClicked: root.ask("layout")
                            }

                            PillButton {
                                label: root.confirming === "everything" ? "Click again to reset" : "Reset everything"
                                onClicked: root.ask("everything")
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "The layout goes back to the default widgets and places; everything also forgets "
                                + "each display's own layout and the choice above, and removes the settings file."
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(12)
                            color: Theme.muted
                        }

                        Item {
                            width: parent.width
                            height: done.height

                            PillButton {
                                label: Widgets.editing ? "Back to editing" : "Edit the layout"
                                onClicked: {
                                    root.close();
                                    if (!Widgets.editing)
                                        Widgets.toggleEditing();
                                }
                            }

                            PillButton {
                                id: done

                                anchors.right: parent.right
                                label: "Done"
                                primary: true
                                onClicked: root.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
