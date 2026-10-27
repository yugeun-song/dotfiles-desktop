pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The mark the system badge draws: the distribution's own by default, or one
// picked from the badge's menu, kept across restarts in the state directory
// as the key overlay's switch is.
//
// Marks are glyphs of the icon font's Font Logos set (Nerd Fonts; the set is
// under the Unlicense), named here by code point: this repository holds no
// logo artwork. Each mark is its owner's trademark, shown only to stand for
// that distribution, as Font Logos asks.
Singleton {
    id: root

    // Menu order: the generic mark, the widely used, then the rest. The Mono
    // icon font fits every mark to one cell's width (0.586 em) and lets its
    // height run; scale brings a tall one's height down to that, measured
    // from the font's glyph boxes, so each draws as large as the others.
    readonly property var marks: [
        { id: "tux", name: "Linux", cp: 0xF31A, scale: 0.843 },
        { id: "arch", name: "Arch Linux", cp: 0xF303 },
        { id: "debian", name: "Debian", cp: 0xF306, scale: 0.805 },
        { id: "ubuntu", name: "Ubuntu", cp: 0xF31B },
        { id: "fedora", name: "Fedora", cp: 0xF30A },
        { id: "opensuse", name: "openSUSE", cp: 0xF314 },
        { id: "void", name: "Void Linux", cp: 0xF32E },
        { id: "gentoo", name: "Gentoo", cp: 0xF30D, scale: 0.945 },
        { id: "alpine", name: "Alpine Linux", cp: 0xF300 },
        { id: "nixos", name: "NixOS", cp: 0xF313 },
        { id: "linuxmint", name: "Linux Mint", cp: 0xF30E },
        { id: "manjaro", name: "Manjaro", cp: 0xF312 },
        { id: "endeavouros", name: "EndeavourOS", cp: 0xF322 },
        { id: "cachyos", name: "CachyOS", cp: 0xF385 },
        { id: "garuda", name: "Garuda Linux", cp: 0xF337 },
        { id: "artix", name: "Artix Linux", cp: 0xF31F },
        { id: "pop", name: "Pop!_OS", cp: 0xF32A },
        { id: "elementary", name: "elementary OS", cp: 0xF309 },
        { id: "zorin", name: "Zorin OS", cp: 0xF32F },
        { id: "kubuntu", name: "Kubuntu", cp: 0xF333 },
        { id: "kdeneon", name: "KDE neon", cp: 0xF331 },
        { id: "mxlinux", name: "MX Linux", cp: 0xF33F },
        { id: "kali", name: "Kali Linux", cp: 0xF327 },
        { id: "parrot", name: "Parrot OS", cp: 0xF329, scale: 0.696 },
        { id: "redhat", name: "Red Hat", cp: 0xF316 },
        { id: "centos", name: "CentOS", cp: 0xF304 },
        { id: "rocky", name: "Rocky Linux", cp: 0xF32B },
        { id: "almalinux", name: "AlmaLinux", cp: 0xF31D },
        { id: "nobara", name: "Nobara", cp: 0xF380 },
        { id: "tumbleweed", name: "openSUSE Tumbleweed", cp: 0xF37D },
        { id: "leap", name: "openSUSE Leap", cp: 0xF37E, scale: 0.773 },
        { id: "slackware", name: "Slackware", cp: 0xF318 },
        { id: "solus", name: "Solus", cp: 0xF32D },
        { id: "deepin", name: "deepin", cp: 0xF321 },
        { id: "devuan", name: "Devuan", cp: 0xF307 },
        { id: "mageia", name: "Mageia", cp: 0xF310, scale: 0.689 },
        { id: "qubes", name: "Qubes OS", cp: 0xF342, scale: 0.871 },
        { id: "tails", name: "Tails", cp: 0xF343, scale: 0.78 },
        { id: "raspberrypi", name: "Raspberry Pi OS", cp: 0xF315, scale: 0.778 },
        { id: "postmarketos", name: "postmarketOS", cp: 0xF374 }
    ]

    // os-release IDs that name a mark other than their own spelling.
    readonly property var aliases: ({
        "archarm": "arch",
        "manjaro-arm": "manjaro",
        "neon": "kdeneon",
        "mx": "mxlinux",
        "rhel": "redhat",
        "opensuse-tumbleweed": "tumbleweed",
        "opensuse-leap": "leap",
        "opensuse-slowroll": "opensuse",
        "sles": "opensuse",
        "suse": "opensuse",
        "raspbian": "raspberrypi",
        "pureos": "debian"
    })

    // The installed icon font's coverage, from fontconfig, so a mark the
    // font does not have (an older Nerd Font) is not offered as a blank box.
    // Unknown until read; everything is offered if it cannot be read.
    property var coverage: null

    readonly property var offered: root.marks.filter(m => root.covers(m.cp))

    // "auto" or a mark's id, as chosen; "auto" until a choice is read or made.
    property string choice: "auto"
    property bool chosen: false

    readonly property var autoMark: root.markFor(Resources.distroId, Resources.distroLike)
    readonly property var current: root.choice === "auto" ? root.autoMark
                                                          : (root.byId(root.choice) ?? root.autoMark)
    readonly property string glyph: String.fromCodePoint(root.current.cp)

    function byId(id) {
        return root.marks.find(m => m.id === id) ?? null;
    }

    // The distribution's own mark, else the first ID_LIKE word with one, else Tux.
    function markFor(id, like) {
        for (const word of [id].concat(like ?? [])) {
            const mark = root.byId(root.aliases[word] ?? word);
            if (mark && root.covers(mark.cp))
                return mark;
        }
        return root.byId("tux");
    }

    // fc-query's charset: space-separated hex code points and a-b ranges.
    function parseCharset(text) {
        const ranges = [];
        for (const part of text.trim().split(/\s+/)) {
            const m = part.match(/^([0-9a-f]+)(?:-([0-9a-f]+))?$/i);
            if (m)
                ranges.push([parseInt(m[1], 16), parseInt(m[2] ?? m[1], 16)]);
        }
        return ranges;
    }

    function covers(cp) {
        if (root.coverage === null || root.coverage.length === 0)
            return true;
        return root.coverage.some(r => cp >= r[0] && cp <= r[1]);
    }

    function choose(id) {
        root.chosen = true;
        root.choice = id === "auto" || root.byId(id) !== null ? id : "auto";
        store.setText(root.choice + "\n");
    }

    FileView {
        id: store

        path: Paths.stateDir + "/badge"
        // A missing file is the automatic mark, not an error worth a line.
        printErrors: false

        onLoaded: {
            if (root.chosen)
                return;
            const id = store.text().trim();
            root.choice = id === "auto" || root.byId(id) !== null ? id : "auto";
        }
        onSaveFailed: error => console.warn("[badge] could not keep the choice in", store.path, "-", error)
    }

    Process {
        running: true
        command: ["sh", "-c", "f=$(fc-match -f '%{file}' \"$1\") && fc-query --format='%{charset}' \"$f\"", "badge", Theme.iconFont]

        stdout: StdioCollector {
            onStreamFinished: root.coverage = root.parseCharset(this.text)
        }
    }
}
