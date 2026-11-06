pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// A widget's own options, opened by a click on it (the user, 2026-11-05: a
// panel to control each one): what the clock, the calendar and the machine's
// widget show. Kept with the widget (Widgets.setOptions), on the screen it
// was clicked on. Laid out as
// the weather's place panel is; Esc or a click beside the card closes it.
Scope {
    id: root

    readonly property var target: Widgets.optionsTarget
    readonly property var item: root.target ? Widgets.item(root.target.screen, root.target.id) : null
    readonly property var options: root.item ? Widgets.optionsOf(root.item) : ({})
    readonly property string kind: root.item?.kind ?? ""
    readonly property string title: Widgets.kinds.find(k => k.kind === root.kind)?.title ?? "Widget"

    function close() {
        Widgets.closeOptions();
    }

    function set(patch: var): bool {
        return root.target !== null && Widgets.setOptions(root.target.screen, root.target.id, patch);
    }

    // The widget gone (reset, removed elsewhere): nothing left to set.
    onItemChanged: {
        if (root.target !== null && root.item === null)
            root.close();
    }

    Connections {
        target: KeyFeed

        function onLockedChanged() {
            if (KeyFeed.locked)
                root.close();
        }
    }

    LazyLoader {
        active: root.target !== null && root.item !== null

        PanelWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === root.target?.screen) ?? Screens.focused
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:widget-options"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property real fit: Theme.fit(win.screen)

            FittedStage {
                fit: win.fit

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(64), Theme.widgetOptionsWidth)
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
                        spacing: Theme.px(12)
                        focus: true

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.close();
                                event.accepted = true;
                            }
                        }

                        Item {
                            width: parent.width
                            height: heading.implicitHeight

                            Text {
                                id: heading

                                text: root.title
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

                        // ---- clock ----
                        Column {
                            visible: root.kind === "clock"
                            width: parent.width

                            ToggleRow {
                                label: "24-hour time"
                                on: root.options.hours24 === true
                                onToggled: on => root.set({ hours24: on })
                            }
                        }

                        // ---- calendar ----
                        ToggleRow {
                            visible: root.kind === "calendar"
                            label: "Weeks start on Monday"
                            detail: "Off, they start on Sunday."
                            on: root.options.mondayFirst === true
                            onToggled: on => root.set({ mondayFirst: on })
                        }

                        // ---- system ----
                        Column {
                            visible: root.kind === "system"
                            width: parent.width

                            // In the widget's own order (the user, 2026-11-05).
                            ToggleRow {
                                label: "CPU"
                                on: root.options.cpu === true
                                onToggled: on => root.set({ cpu: on })
                            }

                            ToggleRow {
                                label: "RAM"
                                on: root.options.memory === true
                                onToggled: on => root.set({ memory: on })
                            }

                            ToggleRow {
                                label: "Network"
                                detail: "Received and sent, a row each."
                                on: root.options.network === true
                                onToggled: on => root.set({ network: on })
                            }

                            // The widget these are for is drawn, so its GPU has been asked.
                            ToggleRow {
                                label: "GPU load"
                                detail: SystemReadings.busyFound || !SystemReadings.probed ? "" : "This machine's GPU reports no load."
                                on: root.options.gpu === true
                                onToggled: on => root.set({ gpu: on })
                            }

                            ToggleRow {
                                label: "VRAM"
                                detail: SystemReadings.vramFound || !SystemReadings.probed ? "" : "This machine's GPU reports no memory of its own."
                                on: root.options.vram === true
                                onToggled: on => root.set({ vram: on })
                            }

                            ToggleRow {
                                label: "Battery"
                                detail: Power.present ? "" : "This machine reports no battery."
                                on: root.options.battery === true
                                onToggled: on => root.set({ battery: on })
                            }

                            ToggleRow {
                                label: "Disk"
                                detail: "The root file system's size and use."
                                on: root.options.disk === true
                                onToggled: on => root.set({ disk: on })
                            }

                            ToggleRow {
                                label: "tmpfs"
                                detail: "/tmp's size and use, where it lives in memory."
                                on: root.options.tmpfs === true
                                onToggled: on => root.set({ tmpfs: on })
                            }
                        }

                        Item {
                            width: parent.width
                            height: doneButton.height

                            PillButton {
                                label: "Edit the layout"
                                onClicked: {
                                    root.close();
                                    Widgets.toggleEditing();
                                }
                            }

                            PillButton {
                                id: doneButton

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
