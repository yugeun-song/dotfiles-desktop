pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// The music half of the island: art, what is playing, and the transport.
//
// The bar used to carry this as one line of text in a purple pill, elided to
// whatever room was left after the window chips. Here it has two lines and the
// art, which is what the pill could never show and what makes the thing
// recognisable without reading it.
Item {
    id: root

    property var player: null
    property bool hasMedia: false
    property bool playing: false

    readonly property string title: root.player?.trackTitle ?? ""
    readonly property string artist: root.player?.trackArtist ?? ""
    readonly property string album: root.player?.trackAlbum ?? ""

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.islandGap
        visible: root.hasMedia

        Rectangle {
            id: art

            anchors.verticalCenter: parent.verticalCenter
            width: Theme.islandArtSize
            height: Theme.islandArtSize
            radius: Theme.px(6)
            // Something under the art, so a track whose art has not arrived
            // yet is a placeholder rather than a hole in the surface.
            color: Qt.rgba(1, 1, 1, 0.10)
            clip: true

            Image {
                anchors.fill: parent
                // Local files only. Theme.localArt carries the reason: the
                // URL is chosen by the player, which for a browser means it
                // is chosen by the page, and an Image handed an http URL
                // fetches it.
                source: Theme.localArt(root.player?.trackArtUrl ?? "")
                fillMode: Image.PreserveAspectCrop
                // Even a local file is read off a disk that may be busy, and
                // this frame is one the island is animating.
                asynchronous: true
                smooth: true
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - art.width - Theme.islandGap
            spacing: Theme.px(2)

            Text {
                width: parent.width
                text: root.title
                // Title and artist are set by the player, and for a browser
                // that means whatever the page says. Nothing here wanted
                // markup, and a page that supplies some would be fetching its
                // own images out of this surface.
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font.family: Theme.uiFont
                font.pixelSize: Theme.islandTitleSize
                font.weight: Font.DemiBold
                color: "#ffffff"
            }

            Text {
                width: parent.width
                visible: root.artist !== ""
                text: root.artist
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.uiFont
                font.pixelSize: Theme.islandSubSize
                color: Qt.rgba(1, 1, 1, 0.70)
            }

            Text {
                width: parent.width
                visible: root.album !== "" && root.album !== root.title
                text: root.album
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.uiFont
                font.pixelSize: Theme.islandSubSize
                color: Qt.rgba(1, 1, 1, 0.45)
            }

            Row {
                spacing: Theme.px(14)
                topPadding: Theme.px(4)

                Repeater {
                    model: [
                        { key: "prev", icon: Theme.iconPrev },
                        { key: "toggle", icon: root.playing ? Theme.iconPause : Theme.iconPlay },
                        { key: "next", icon: Theme.iconNext }
                    ]

                    Text {
                        id: control

                        required property var modelData

                        // Whether the player says it can do this. A control
                        // that is drawn and does nothing is worse than one
                        // that is visibly unavailable, and Mpris publishes
                        // the answer for all three.
                        readonly property bool usable: {
                            switch (control.modelData.key) {
                            case "prev":
                                return root.player?.canGoPrevious ?? false;
                            case "next":
                                return root.player?.canGoNext ?? false;
                            default:
                                return root.player?.canTogglePlaying ?? false;
                            }
                        }

                        text: control.modelData.icon
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.px(15)
                        color: !control.usable ? Qt.rgba(1, 1, 1, 0.25)
                                               : controlHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)

                        Behavior on color {
                            ColorAnimation {
                                duration: 90
                                easing.type: Easing.OutCubic
                            }
                        }

                        HoverHandler {
                            id: controlHover

                            enabled: control.usable
                        }

                        MouseArea {
                            anchors.fill: parent
                            // A little larger than the glyph. At 15 px these
                            // are small targets and the gap between them is
                            // dead space the pointer keeps landing in.
                            anchors.margins: -Theme.px(5)
                            enabled: control.usable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                switch (control.modelData.key) {
                                case "prev":
                                    root.player.previous();
                                    break;
                                case "next":
                                    root.player.next();
                                    break;
                                default:
                                    root.player.togglePlaying();
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Nothing playing. Said once, quietly, rather than with a placeholder
    // player whose buttons do nothing.
    Text {
        anchors.centerIn: parent
        visible: !root.hasMedia
        text: "Nothing playing"
        font.family: Theme.uiFont
        font.pixelSize: Theme.islandSubSize
        color: Qt.rgba(1, 1, 1, 0.40)
    }
}
