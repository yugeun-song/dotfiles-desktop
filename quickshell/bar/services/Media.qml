pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// What is playing, and whether the player card is open. A singleton so the
// chip and the card (separate surfaces) can pool their hover state.
Singleton {
    id: root

    // The playing player, else one with a track loaded. One rule for chip and card.
    readonly property var player: {
        const players = Mpris.players?.values ?? [];
        return players.find(p => p.isPlaying) ?? players.find(p => (p.trackTitle ?? "") !== "") ?? null;
    }

    readonly property string title: root.player?.trackTitle ?? ""
    readonly property string artist: root.player?.trackArtist ?? ""
    readonly property bool present: root.title !== ""
    readonly property bool playing: root.present && (root.player?.isPlaying ?? false)

    property bool chipHovered: false
    property bool cardHovered: false

    property bool open: false

    readonly property bool wanted: root.chipHovered || root.cardHovered

    onWantedChanged: {
        if (root.wanted) {
            close.stop();
            root.open = true;
        } else {
            close.restart();
        }
    }

    // Close grace: the pointer leaves one surface a frame before entering the other.
    Timer {
        id: close

        interval: 200
        onTriggered: root.open = false
    }
}
