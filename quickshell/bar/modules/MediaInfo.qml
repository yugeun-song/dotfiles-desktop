pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.services

Rectangle {
    id: root

    readonly property var player: {
        const players = Mpris.players?.values ?? [];
        return players.find(p => p.isPlaying) ?? players.find(p => (p.trackTitle ?? "") !== "") ?? null;
    }

    readonly property string title: root.player?.trackTitle ?? ""
    readonly property string artist: root.player?.trackArtist ?? ""
    readonly property bool hasMedia: root.title !== ""
    readonly property bool playing: root.hasMedia && (root.player?.isPlaying ?? false)

    readonly property string summary: {
        if (!root.hasMedia)
            return "No media";
        return root.artist === "" ? root.title : `${root.artist} - ${root.title}`;
    }

    // Width is computed rather than left to the Row: the title is arbitrarily
    // long, so the pill claims only what is left after the icon and the
    // visualizer, and the label elides inside that.
    readonly property int pad: Theme.mediaPadding
    readonly property int itemSpacing: Theme.mediaItemGap
    readonly property int leadWidth: glyph.implicitWidth + (viz.visible ? root.itemSpacing + viz.implicitWidth : 0)
    readonly property int textRoom: Math.max(0, Theme.mediaMaxWidth - root.pad * 2 - root.leadWidth - root.itemSpacing)
    // Measured with TextMetrics, not label.implicitWidth. A Text with elide
    // set reports the already-shortened width, so feeding that back into the
    // width calculation shrinks the label a little more on every pass until
    // even a short string like "No media" ends up truncated.
    readonly property int textWidth: Math.min(Math.ceil(metrics.width), root.textRoom)

    TextMetrics {
        id: metrics

        font.family: Theme.uiFont
        font.pixelSize: Theme.textSize
        font.weight: Font.Medium
        text: root.summary
    }

    // Cava.active is shared by every bar, so it is bound rather than written:
    // a copy torn down on a monitor change used to switch cava off while the
    // surviving bar was still playing, and only a pause and resume brought it
    // back. RestoreNone keeps the departing copy from putting a value back.
    Binding {
        target: Cava
        property: "active"
        value: root.playing
        restoreMode: Binding.RestoreNone
    }

    implicitHeight: Theme.pillHeight
    implicitWidth: root.pad * 2 + root.leadWidth + root.itemSpacing + root.textWidth
    radius: Theme.pillRadius
    color: root.hasMedia ? Theme.purple : "transparent"

    Row {
        x: root.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.itemSpacing

        Text {
            id: glyph

            anchors.verticalCenter: parent.verticalCenter
            // Shows the action a click performs, not the current state:
            // playing offers pause, paused offers play.
            text: !root.hasMedia ? Theme.iconMusic : root.playing ? Theme.iconPause : Theme.iconPlay
            font.family: Theme.iconFont
            font.pixelSize: Theme.iconSize
            color: root.hasMedia ? Theme.ink : Theme.muted
        }

        Visualizer {
            id: viz

            anchors.verticalCenter: parent.verticalCenter
            // An empty level list draws the same flat row of stubs a silent
            // passage does, so the well collapses instead of claiming the
            // track went quiet when cava is simply not feeding it.
            visible: root.hasMedia && Cava.levels.length > 0
            barColor: Theme.ink
        }

        Text {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            width: root.textWidth
            text: root.summary
            elide: Text.ElideRight
            font.family: Theme.uiFont
            font.pixelSize: Theme.textSize
            font.weight: Font.Medium
            color: root.hasMedia ? Theme.ink : Theme.muted
        }
    }

    HoverHandler {
        id: hover
    }

    Tooltip {
        anchorItem: root
        active: hover.hovered
        text: {
            if (!root.hasMedia)
                return "Nothing is playing";
            const lines = [`Title     ${root.title}`];
            if (root.artist !== "")
                lines.push(`Artist    ${root.artist}`);
            const album = root.player?.trackAlbum ?? "";
            if (album !== "")
                lines.push(`Album     ${album}`);
            const who = root.player?.identity ?? "";
            if (who !== "")
                lines.push(`Player    ${who}`);
            lines.push(root.playing ? "Playing, click to pause" : "Paused, click to play");
            return lines.join("\n");
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.hasMedia && (root.player?.canTogglePlaying ?? false)
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.player.isPlaying = !root.player.isPlaying
    }
}
