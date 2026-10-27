pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services

// What is playing, the same on every screen. Whether the player card is open
// is not here: it belongs to the bar whose island is hovered (MediaPopup), or
// hovering one screen's island opened the card on every screen.
Singleton {
    id: root

    // The playing player, else the one that last played while it stays open
    // (paused however long: the user, 2026-10-26), else one with a track
    // loaded. One rule for the island and the card.
    readonly property var player: {
        const players = Mpris.players?.values ?? [];
        const playing = players.find(p => p.isPlaying);
        if (playing)
            return playing;
        if (root.lastPlayer && players.indexOf(root.lastPlayer) !== -1)
            return root.lastPlayer;
        return players.find(p => (p.trackTitle ?? "") !== "") ?? null;
    }
    property var lastPlayer: null

    onPlayerChanged: {
        if (root.player?.isPlaying)
            root.lastPlayer = root.player;
        root.hold();
    }

    readonly property string title: root.player?.trackTitle ?? ""
    readonly property string artist: root.player?.trackArtist ?? ""
    // A track with a title, or an untitled one while it plays: some players
    // give none (the user, 2026-10-26), and the island then holds the cover
    // and the meter, at its floor at least (Theme.islandFloorWidth).
    readonly property bool present: root.title !== "" || (root.player?.isPlaying ?? false)
    readonly property bool playing: root.present && (root.player?.isPlaying ?? false)

    // A seek or a change of track takes some players through Paused or a
    // blank title for a moment, and the island went and came back (the user,
    // 2026-10-26). So what the island goes by follows a start at once and an
    // end only once it has lasted Theme.mediaGapMs, and the title, artist and
    // cover shown stay until others arrive.
    property bool steadyPlaying: false
    property bool steadyPresent: false
    property string shownTitle: ""
    property string shownArtist: ""
    property string shownArtUrl: ""

    onPlayingChanged: root.follow()
    onPresentChanged: root.follow()
    onTitleChanged: root.hold()
    onArtistChanged: root.hold()

    function follow(): void {
        if (root.playing)
            root.steadyPlaying = true;
        if (root.present)
            root.steadyPresent = true;
        if (root.steadyPlaying !== root.playing || root.steadyPresent !== root.present)
            gap.restart();
        else
            gap.stop();
    }

    Timer {
        id: gap

        interval: Theme.mediaGapMs
        onTriggered: {
            root.steadyPlaying = root.playing;
            root.steadyPresent = root.present;
            root.hold();
        }
    }

    function hold(): void {
        if (root.present) {
            root.shownTitle = root.title;
            root.shownArtist = root.artist;
            root.shownArtUrl = root.player?.trackArtUrl ?? "";
        } else if (!root.steadyPresent) {
            root.shownTitle = "";
            root.shownArtist = "";
            root.shownArtUrl = "";
        }
    }

    Connections {
        target: root.player

        function onTrackArtUrlChanged(): void {
            root.hold();
        }
    }

    Component.onCompleted: {
        root.follow();
        root.hold();
    }

    // The colour of the island's meters: the cover's most colourful hue, as
    // light and strong as the island's own colours are at that hue, which the
    // user found nearer the primaries than the cover's own (2026-10-26). A
    // cover of greys, or none, gives white, as on the references' phone; so
    // does an all-black one, the black island's complement, which the user
    // asked for that case alone (2026-10-26). artDim is the companion for
    // the meter at rest while paused.
    ColorQuantizer {
        id: quantizer

        depth: 3
        rescaleSize: 64
    }

    // Never handed an empty source, which it tries to open as a file.
    Binding {
        target: quantizer
        property: "source"
        when: root.artFile !== ""
        value: root.artFile
        restoreMode: Binding.RestoreNone
    }

    readonly property color artColor: root.artFile !== "" ? root.vivid(quantizer.colors) : Theme.islandText

    // The cover as a local file, as the picker opens files only (a web cover
    // left the meter white). One on the web, from a host Theme.artHosts
    // allows, is fetched once into the runtime directory (tmpfs) under two
    // names in turn: the picker sees a new file, and at most two are kept.
    readonly property string artUrl: Theme.localArt(root.shownArtUrl)
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    property string artFile: ""
    property int artTurn: 0
    property bool artAgain: false

    onArtUrlChanged: root.fetchArt()

    function fetchArt(): void {
        const url = root.artUrl;
        if (url.startsWith("file://") || url === "" || root.runtimeDir === "") {
            root.artFile = url.startsWith("file://") ? url : "";
            return;
        }
        if (artFetch.running) {
            root.artAgain = true;
            return;
        }
        root.artTurn = 1 - root.artTurn;
        artFetch.url = url;
        artFetch.target = `${root.runtimeDir}/quickshell-bar/cover-${root.artTurn}`;
        artFetch.command = ["sh", "-c",
            'mkdir -p -m 700 "${1%/*}" && exec curl -sS --fail --location --proto =https ' +
            '--max-time 5 --max-filesize 5000000 -o "$1" -- "$2"', "sh", artFetch.target, url];
        artFetch.running = true;
    }

    Process {
        id: artFetch

        property string url: ""
        property string target: ""

        onExited: code => {
            if (code === 0 && artFetch.url === root.artUrl)
                root.artFile = `file://${artFetch.target}`;
            if (root.artAgain) {
                root.artAgain = false;
                root.fetchArt();
            }
        }
    }
    readonly property color artDim: Theme.islandDim(root.artColor)

    // The island's colours in OKLCH, in order of hue: what lightness and
    // chroma the references give each hue, between them read off the line.
    readonly property var anchors: [Theme.islandRed, Theme.islandYellow, Theme.islandGreen,
                                    Theme.islandMint, Theme.islandBlue].map(c => root.lch(c))
                                                                       .sort((a, b) => a.h - b.h)

    function vivid(colors): color {
        let best = null;
        let bestScore = 0;
        for (const c of colors ?? []) {
            const p = root.lch(c);
            // Hue from a swatch with colour in it, not from near black or white.
            const score = p.c * (1 - Math.abs(p.l - 0.65));
            if (p.c >= 0.05 && score > bestScore) {
                best = p;
                bestScore = score;
            }
        }
        if (best === null || root.anchors.length === 0)
            return Theme.islandText;
        const a = root.anchors;
        let i = a.findIndex(x => x.h > best.h);
        if (i < 0)
            i = 0;
        const hi = a[i];
        const lo = a[(i + a.length - 1) % a.length];
        const span = (hi.h - lo.h + 360) % 360 || 360;
        const t = ((best.h - lo.h + 360) % 360) / span;
        return root.fromLch(lo.l + (hi.l - lo.l) * t, lo.c + (hi.c - lo.c) * t, best.h);
    }

    // OKLab (Björn Ottosson's matrices), on the encoded sRGB values QML keeps.
    function lch(c: color): var {
        const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        const r = lin(c.r), g = lin(c.g), b = lin(c.b);
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
        const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
        return { l: L, c: Math.hypot(A, B), h: (Math.atan2(B, A) * 180 / Math.PI + 360) % 360 };
    }

    // Back to sRGB, the chroma given up until the colour is one the screen
    // can show: a hue's references may sit at the edge of the gamut.
    function fromLch(L: real, C: real, h: real): color {
        const enc = v => v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
        const rgb = chroma => {
            const A = chroma * Math.cos(h * Math.PI / 180);
            const B = chroma * Math.sin(h * Math.PI / 180);
            const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
            const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
            const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3);
            return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
        };
        let lo = 0, hi = C, out = rgb(0);
        for (let k = 0; k < 16; ++k) {
            const mid = (lo + hi) / 2;
            const v = rgb(mid);
            if (v.every(x => x >= -0.0005 && x <= 1.0005)) {
                lo = mid;
                out = v;
            } else {
                hi = mid;
            }
        }
        const inside = rgb(C);
        if (inside.every(x => x >= -0.0005 && x <= 1.0005))
            out = inside;
        const clamp = x => Math.max(0, Math.min(1, enc(Math.max(0, x))));
        return Qt.rgba(clamp(out[0]), clamp(out[1]), clamp(out[2]), 1);
    }

    // The island's switch (Super+M, shell.qml), for all of it (MediaChip),
    // kept across restarts. On unless switched off: a missing file is the
    // default, so a fresh install shows the island.
    property bool islandOn: true
    property bool islandChosen: false

    function toggleIsland(): void {
        root.islandChosen = true;
        root.islandOn = !root.islandOn;
        islandStore.setText(root.islandOn ? "on\n" : "off\n");
    }

    FileView {
        id: islandStore

        path: Paths.stateDir + "/island"
        printErrors: false

        onLoaded: {
            if (!root.islandChosen)
                root.islandOn = islandStore.text().trim() !== "off";
        }
        onSaveFailed: error => console.warn("[media] could not keep the island switch in", islandStore.path, "-", error)
    }
}
