pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.services

// The island: a surface hanging below the centre of the menu bar.
//
// Its own PanelWindow rather than part of the bar, because the bar claims its
// height as an exclusive zone and the island is four times that when open. A
// bar tall enough to hold it would push every window down forever. So this
// claims nothing, ignores the bar's zone, and is masked to what it draws.
//
// Only the bottom corners are round -- four round ones below the bar read as
// a separate window rather than as something the bar opened. Done by clipping
// rather than with per-corner radii, which are newer than the Qt here.
Scope {
    id: root

    // The player the island speaks for: whatever is playing, or failing that
    // whatever has a track loaded. The same rule MediaInfo used, kept so that
    // the two never disagree about which player is "the" one.
    readonly property var player: {
        const players = Mpris.players?.values ?? [];
        return players.find(p => p.isPlaying) ?? players.find(p => (p.trackTitle ?? "") !== "") ?? null;
    }

    readonly property bool hasMedia: (root.player?.trackTitle ?? "") !== ""
    readonly property bool playing: root.hasMedia && (root.player?.isPlaying ?? false)

    property bool expanded: false

    // Cava is shared by every surface that draws a waveform, so it is bound
    // rather than written: a copy torn down on a monitor change used to switch
    // cava off while a surviving one was still playing. RestoreNone keeps the
    // departing copy from putting a value back.
    Binding {
        target: Cava
        property: "active"
        value: root.playing
        restoreMode: Binding.RestoreNone
    }

    PanelWindow {
        id: surface

        // Follows the focused screen, for the same reason the launcher and the
        // OSD do: an island on a monitor nobody is looking at is not an island.
        screen: {
            const name = Hyprland.focusedMonitor?.name ?? "";
            const match = Quickshell.screens.find(s => s.name === name);
            return match ?? Quickshell.screens[0] ?? null;
        }

        color: "transparent"
        // Claims nothing and ignores what the bar claimed, so the window under
        // it keeps the geometry it had and the island simply covers a strip of
        // it while it is open.
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        focusable: false
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell:island"

        // Anchored to the top edge only, which layer-shell centres
        // horizontally. Measured from the screen edge, not from the bar,
        // because the exclusive zone is ignored above.
        anchors {
            top: !Theme.barAtBottom
            bottom: Theme.barAtBottom
        }

        margins {
            top: Theme.barAtBottom ? 0 : Theme.barHeight
            bottom: Theme.barAtBottom ? Theme.barHeight : 0
        }

        implicitWidth: body.width
        implicitHeight: body.height

        // Only the card takes input. Without this the surface would be a
        // full-width rectangle swallowing clicks meant for the window under it
        // -- and it is the whole reason the island can be this size at all.
        mask: Region {
            item: body
        }

        Item {
            id: body

            // Clips the card's top corners. See the note at the top: the
            // card is taller than this by its radius and offset upwards by
            // the same amount, so what is cut off is exactly the round part
            // that would otherwise show above the island.
            clip: true

            width: root.expanded ? Theme.islandExpandedWidth
                                 : root.hasMedia ? Theme.islandCollapsedWidth
                                                 : Theme.islandHandleWidth
            height: root.expanded ? Theme.islandExpandedHeight : Theme.islandCollapsedHeight

            // Opening is slower than closing. An island that snaps open feels
            // like a popup; one that lingers on the way out gets in the way of
            // the pointer that already left.
            Behavior on width {
                NumberAnimation {
                    duration: root.expanded ? Theme.islandOpenMs : Theme.islandCloseMs
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on height {
                NumberAnimation {
                    duration: root.expanded ? Theme.islandOpenMs : Theme.islandCloseMs
                    easing.type: Easing.OutCubic
                }
            }

            HoverHandler {
                id: hover

                onHoveredChanged: {
                    if (hover.hovered) {
                        close.stop();
                        root.expanded = true;
                    } else {
                        close.restart();
                    }
                }
            }

            // A grace period on the way out only. The pointer leaves the card
            // for a moment whenever it crosses a gap inside it, and closing on
            // that made the island flicker under a pointer that had not gone
            // anywhere.
            Timer {
                id: close

                interval: 220
                onTriggered: root.expanded = false
            }

            Rectangle {
                id: card

                // Pushed out of the container by its own radius, on whichever
                // side the bar is: the clip then removes exactly the two
                // corners that would otherwise round away from the bar. With
                // the bar at the bottom the island grows upward, so it is the
                // bottom pair that has to go.
                y: Theme.barAtBottom ? 0 : -Theme.islandRadius
                width: parent.width
                height: parent.height + Theme.islandRadius
                radius: Theme.islandRadius
                color: Theme.islandBg

                // The collapsed face: album art and a waveform, or a bare
                // handle when nothing is playing. Crossfaded rather than
                // swapped, so the thing that grows is the same object.
                Item {
                    anchors.fill: parent
                    // Keeps the content out of the strip the clip removes,
                    // which is on whichever side the card was pushed towards.
                    anchors.topMargin: Theme.barAtBottom ? 0 : Theme.islandRadius
                    anchors.bottomMargin: Theme.barAtBottom ? Theme.islandRadius : 0
                    opacity: root.expanded ? 0 : 1
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.islandCloseMs
                            easing.type: Easing.OutCubic
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.px(8)

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.hasMedia
                            width: Theme.islandCollapsedArt
                            height: Theme.islandCollapsedArt
                            radius: Theme.px(4)
                            color: Qt.rgba(1, 1, 1, 0.10)
                            clip: true

                            Image {
                                anchors.fill: parent
                                // Local files only; see Theme.localArt.
                                source: Theme.localArt(root.player?.trackArtUrl ?? "")
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }
                        }

                        Visualizer {
                            anchors.verticalCenter: parent.verticalCenter
                            // An empty level list draws the same flat row of
                            // stubs a silent passage does, so it collapses
                            // instead of claiming the track went quiet when
                            // cava is simply not feeding it.
                            visible: root.hasMedia && Cava.levels.length > 0
                            barColor: Qt.rgba(1, 1, 1, 0.85)
                        }

                        // What is left when nothing is playing: a short bar
                        // that says there is something here to open. Without
                        // it the island would vanish and the calendar and the
                        // tray would have no door.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.hasMedia
                            width: Theme.px(22)
                            height: Math.max(2, Theme.px(3))
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.35)
                        }
                    }
                }

                // The open face.
                Item {
                    anchors.fill: parent
                    anchors.topMargin: Theme.barAtBottom ? 0 : Theme.islandRadius
                    anchors.bottomMargin: Theme.barAtBottom ? Theme.islandRadius : 0
                    opacity: root.expanded ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.islandOpenMs
                            easing.type: Easing.OutCubic
                        }
                    }

                    IslandPanes {
                        anchors.fill: parent
                        anchors.margins: Theme.islandPad
                        player: root.player
                        hasMedia: root.hasMedia
                        playing: root.playing
                        parentWindow: surface
                    }
                }
            }
        }
    }
}
