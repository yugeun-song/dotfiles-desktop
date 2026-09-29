pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// What is playing, the same on every screen. Whether the player card is open
// is not here: it belongs to the bar whose chip is hovered (MediaPopup), or
// hovering one screen's chip opened the card on every screen.
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
}
