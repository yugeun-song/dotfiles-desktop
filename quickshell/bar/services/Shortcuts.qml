pragma Singleton
// QtQuick is not used here; see Paths.qml for why the import stays.
import QtQuick
import Quickshell

// The key bindings as the cheatsheet lists them (modules/Cheatsheet.qml),
// from `hyprctl -j binds`: plain values in and out, so the grouping is
// tested without Hyprland (tests/unit/qml/shell.qml). Grouped as a system's
// keyboard settings group them, in the order keybinds.lua gives them, an
// action's several chords on its one row, and numbered actions on the same
// modifiers in one row ("Workspace 1-10"), as the user asked (2026-11-04:
// searchable, more intuitive, keys drawn as keys).
Singleton {
    id: root

    // Hyprland's modmask bits, in the order a keyboard's labels are read.
    readonly property var modNames: [
        { bit: 64, name: "Super" },
        { bit: 4,  name: "Ctrl"  },
        { bit: 8,  name: "Alt"   },
        { bit: 1,  name: "Shift" }
    ]

    readonly property var groups: ["Shell", "Applications", "Windows", "Workspaces", "Capture",
                                   "Media and devices", "Session"]

    // From the descriptions keybinds.lua gives; what is none of these opens
    // a program.
    function groupOf(what: string): string {
        if (/^Capture/.test(what))
            return "Capture";
        if (/workspace|scratchpad/i.test(what))
            return "Workspaces";
        if (/^(Focus|Move window|Close window|Pick a window|Fullscreen|Maximize|Tell the window|Toggle floating|Pin window|Split ratio|Drag window|Resize window|Zoom)/.test(what))
            return "Windows";
        if (/^(Play\/pause|Next track|Previous track|Mute|Volume (up|down)|Brightness|Cameras|Lid:)/.test(what))
            return "Media and devices";
        if (/^(Lock|Session|Shut down|Restart)/.test(what))
            return "Session";
        if (/^(Show|Pick the wallpaper|Edit the desktop widgets|Desktop widget settings|Display settings|Application launcher|Clipboard history)/.test(what))
            return "Shell";
        return "Applications";
    }

    // A key as its keycap prints it, not as X11 spells it. Mouse buttons by
    // their side: Hyprland names them by evdev code (272 is BTN_LEFT), which
    // told a reader nothing (the user, 2026-11-04).
    function keyCap(key: string): string {
        const named = {
            "Return": "Enter", "slash": "/", "comma": ",", "period": ".",
            "semicolon": ";", "apostrophe": "'", "grave": "`", "minus": "-",
            "equal": "=", "bracketleft": "[", "bracketright": "]",
            "backslash": "\\", "Print": "PrtSc", "Escape": "Esc", "Delete": "Del",
            "Page_Up": "PgUp", "Page_Down": "PgDn", "space": "Space", "Tab": "Tab",
            "Up": "↑", "Down": "↓", "Left": "←", "Right": "→",
            "mouse_up": "Wheel up", "mouse_down": "Wheel down",
            "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
            "XF86MonBrightnessDown": "Brightness −", "XF86MonBrightnessUp": "Brightness +",
            "XF86AudioLowerVolume": "Volume −", "XF86AudioRaiseVolume": "Volume +",
            "XF86AudioMute": "Mute", "XF86AudioMicMute": "Mic mute", "XF86PowerOff": "Power",
            "XF86AudioPlay": "Play", "XF86AudioNext": "Next", "XF86AudioPrev": "Previous",
            "XF86WebCam": "Camera", "XF86Display": "Display"
        };
        if (named[key] !== undefined)
            return named[key];
        // Punctuation by its keysym in any case: the binds spell it both
        // ways (BracketLeft beside bracketleft).
        const punctuation = Object.keys(named).find(k => /^[a-z]+$/.test(k) && named[k].length === 1
                                                      && k === key.toLowerCase());
        if (punctuation !== undefined)
            return named[punctuation];
        if (key.indexOf("mouse:") === 0)
            return `Button ${key.slice(6)}`;
        if (key.indexOf("XF86") === 0)
            return key.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2");
        return key.length === 1 ? key.toUpperCase() : key;
    }

    // One chord: its caps in order, and a word for what is no key pressed
    // and let go (a lone Super tapped, the lid).
    function chord(mask: int, key: string): var {
        if (key.indexOf("switch:") === 0)
            return { caps: [], note: key.indexOf("switch:on:") === 0 ? "Lid closed" : "Lid opened" };
        const caps = root.modNames.filter(m => (mask & m.bit) !== 0).map(m => m.name);
        if ((key === "SUPER_L" || key === "SUPER_R") && caps.indexOf("Super") !== -1)
            return { caps: caps, note: "tap" };
        return { caps: caps.concat([root.keyCap(key)]), note: "" };
    }

    function sameChord(a: var, b: var): bool {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    // The groups in their order, each { name, rows }, a row { what, chords,
    // to }: `to` is a numbered range's last key, its first in chords[0].
    function build(binds: var): var {
        const rows = [];
        const byWhat = {};
        for (const b of binds ?? []) {
            if (!b || !b.description)
                continue;
            const c = root.chord(b.modmask || 0, b.key || "");
            const what = b.description;
            const numbered = what.match(/^(.*\S)\s+(\d+)$/);
            if (numbered) {
                // One row per action and modifiers, the range from the first
                // number to the last.
                const id = `${numbered[1]}#${b.modmask || 0}`;
                const at = byWhat[id];
                if (at) {
                    at.last = Number(numbered[2]);
                    at.to = c.caps[c.caps.length - 1];
                    continue;
                }
                byWhat[id] = { what: numbered[1], first: Number(numbered[2]), last: Number(numbered[2]),
                               chords: [c], to: "", range: true };
                rows.push(byWhat[id]);
                continue;
            }
            const at = byWhat[what];
            if (at) {
                if (!at.chords.some(x => root.sameChord(x, c)))
                    at.chords.push(c);
                continue;
            }
            byWhat[what] = { what: what, chords: [c], to: "" };
            rows.push(byWhat[what]);
        }
        const out = root.groups.map(name => ({ name: name, rows: [] }));
        for (const r of rows) {
            const what = r.range ? (r.last > r.first ? `${r.what} ${r.first}–${r.last}` : `${r.what} ${r.first}`) : r.what;
            const row = { what: what, chords: r.chords, to: r.range && r.last > r.first ? r.to : "" };
            out.find(g => g.name === root.groupOf(r.what)).rows.push(row);
        }
        return out.filter(g => g.rows.length > 0);
    }

    // Hangul typed where latin was meant, as the keys of the two-set layout
    // spell it: with the input method left in Hangul, "lock" arrives as the
    // jamo of those four keys, the last two composed into one syllable.
    // Syllables are taken apart into their jamo first.
    readonly property var jamoKeys: ({
        "ㄱ": "r", "ㄲ": "R", "ㄴ": "s", "ㄷ": "e", "ㄸ": "E", "ㄹ": "f", "ㅁ": "a", "ㅂ": "q", "ㅃ": "Q",
        "ㅅ": "t", "ㅆ": "T", "ㅇ": "d", "ㅈ": "w", "ㅉ": "W", "ㅊ": "c", "ㅋ": "z", "ㅌ": "x", "ㅍ": "v",
        "ㅎ": "g", "ㅏ": "k", "ㅐ": "o", "ㅑ": "i", "ㅒ": "O", "ㅓ": "j", "ㅔ": "p", "ㅕ": "u", "ㅖ": "P",
        "ㅗ": "h", "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅛ": "y", "ㅜ": "n", "ㅝ": "nj", "ㅞ": "np",
        "ㅟ": "nl", "ㅠ": "b", "ㅡ": "m", "ㅢ": "ml", "ㅣ": "l", "ㄳ": "rt", "ㄵ": "sw", "ㄶ": "sg",
        "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq", "ㄽ": "ft", "ㄾ": "fx", "ㄿ": "fv", "ㅀ": "fg", "ㅄ": "qt"
    })
    readonly property string initials: "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
    readonly property string medials: "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
    readonly property var finals: ["", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ",
                                   "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ",
                                   "ㅍ", "ㅎ"]

    function latinOf(text: string): string {
        let out = "";
        for (const ch of text) {
            const code = ch.codePointAt(0);
            if (code >= 0xAC00 && code <= 0xD7A3) {
                const n = code - 0xAC00;
                const jamo = [root.initials[Math.floor(n / 588)], root.medials[Math.floor((n % 588) / 28)],
                              root.finals[n % 28]];
                out += jamo.map(j => root.jamoKeys[j] ?? "").join("");
            } else {
                out += root.jamoKeys[ch] ?? ch;
            }
        }
        return out.toLowerCase();
    }

    // A query matches a row by its words, its group's name or any cap, as
    // typed or as the keys under the Hangul it came out as.
    function filter(groups: var, query: string): var {
        const typed = query.trim().toLowerCase();
        if (typed === "")
            return groups;
        const needles = [typed, root.latinOf(typed)].filter((n, i, all) => n !== "" && all.indexOf(n) === i);
        const hit = (g, r, needle) => r.what.toLowerCase().includes(needle)
            || g.name.toLowerCase().includes(needle)
            || r.chords.some(c => c.caps.some(k => k.toLowerCase() === needle || (needle.length > 1 && k.toLowerCase().includes(needle))))
            || (r.to !== "" && r.to.toLowerCase() === needle);
        return groups.map(g => ({ name: g.name, rows: g.rows.filter(r => needles.some(n => hit(g, r, n))) }))
            .filter(g => g.rows.length > 0);
    }
}
