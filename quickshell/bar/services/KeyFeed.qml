pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

// Key presses for the on-screen overlay, read by root's copy of
// keyfeed/keyfeed.py (evdev) over a JSON-lines protocol; pkexec asks for an
// administrator's password each time the reader starts. Not named "Keys":
// that would shadow the attached type and break every Keys.onPressed.
Singleton {
    id: root

    // Super+Y turns it on and off. Kept in the state directory, outside the
    // repository and the installed config: in memory only, every start or
    // reload of the bar (a reboot, install.sh) turned it off behind the
    // user's back. A missing file is off: an always-on reader is a keylogger
    // nobody asked for.
    property bool enabled: false

    // Set by the first toggle, so a read landing after it does not undo it.
    property bool chosen: false

    // The reader sits on evdev, under the compositor, so it reads what is
    // typed into the lock screen too: a chord younger than its dwell was drawn
    // the moment the session unlocked (the Enter and the last keys of the
    // password). hypridle reports the lock and the unlock (on_lock_cmd,
    // on_unlock_cmd), lock.sh the lock as it starts hyprlock; while locked the
    // reader is paused (readerOpen), so those keys never leave it. The unlock
    // comes from hypridle, or from the compositor itself (below): lock.sh also
    // returns when hyprlock crashes and the session stays locked. It starts
    // locked and asks the compositor at once: a bar restarted during a lock
    // knew nothing of it and drew the password's last keys at the unlock.
    // The keys of the milliseconds the answer takes are the cheaper loss.
    property bool locked: true

    Component.onCompleted: lockProbe.running = true

    IpcHandler {
        target: "keys"

        function lock(): void {
            root.locked = true;
            root.clear();
        }

        function unlock(): void {
            root.locked = false;
            root.clear();
        }
    }

    // With hypridle not running, no unlock would come and the overlay would
    // stay mute after the first lock. While locked, the compositor is asked
    // now and then whether the session still is. Asked, not hyprlock looked
    // for: with the locker crashed the session stays locked (a red screen
    // that takes the keys typed to recover), and its absence had counted as
    // the unlock.
    Timer {
        interval: 5000
        repeat: true
        running: root.locked

        onTriggered: {
            if (!lockProbe.running)
                lockProbe.running = true;
        }
    }

    Process {
        id: lockProbe

        command: ["hyprctl", "locked"]

        // "true" or "false"; anything else (no compositor to ask) changes
        // nothing.
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "false" && root.locked) {
                    root.locked = false;
                    root.clear();
                }
            }
        }
    }

    // A password being typed: its keys must not reach the overlay, or any
    // buffer on the way. Told apart without reading a key: a password
    // window has the focus (polkit agents, among them the one that asks
    // for this reader's password, pinentry, ssh and sudo askpass helpers,
    // the GNOME keyring's and KDE wallet's prompts), or the focused window's
    // terminal reads with its echo off (echowatch.py: sudo, su, ssh,
    // passwd, read -s). The reader is paused for it, which closes the
    // keyboards (keyfeed.py).
    readonly property var secretWindows: /polkit|policykit|pinentry|askpass|gcr-prompter|kwalletd/i

    readonly property var focusedWindow: Screens.focusedWindow

    readonly property bool secretFocused:
        root.secretWindows.test(root.focusedWindow?.wayland?.appId ?? root.focusedWindow?.lastIpcObject?.class ?? "")

    property bool promptSecret: false

    readonly property bool secretInput: root.secretFocused || root.promptSecret

    // Set the moment either says so, with whatever was drawn just before
    // cleared (a first key can beat the word to the bar), and held a moment
    // after: the last keys of the password can come after the word that it
    // is over.
    property bool guarded: false

    onSecretInputChanged: {
        if (root.secretInput) {
            guardRelease.stop();
            root.guarded = true;
            root.clear();
        } else {
            guardRelease.restart();
        }
    }

    Timer {
        id: guardRelease

        interval: 400
        onTriggered: root.guarded = root.secretInput
    }

    // The focused window's process, for echowatch.py to find its terminals.
    readonly property int focusedPid: root.focusedWindow?.lastIpcObject?.pid ?? 0

    onFocusedPidChanged: root.tellFocus()

    function tellFocus() {
        if (echoWatch.running)
            echoWatch.write(`pid ${root.focusedPid}\n`);
    }

    // quickshell fills a window's lastIpcObject, its pid included, from
    // Hyprland's client list, which it asks for when it starts and on a
    // config reload only. A window opened since had none: the watch was told
    // pid 0 and never looked at the terminals of any terminal opened after
    // the bar started (found 2026-10-17). The list is asked for again when
    // the window taking the keys has no pid yet.
    onFocusedWindowChanged: root.askForPid()

    function askForPid() {
        if (root.enabled && root.focusedWindow && !(root.focusedWindow.lastIpcObject?.pid > 0))
            Hyprland.refreshToplevels();
    }

    onEnabledChanged: root.askForPid()

    // Only while the overlay is on: nothing else wants to know.
    Process {
        id: echoWatch

        running: root.enabled
        command: ["python3", "-I", Quickshell.shellPath("scripts/echowatch.py")]
        stdinEnabled: true

        onStarted: root.tellFocus()

        stdout: SplitParser {
            onRead: line => root.promptSecret = line.trim() === "secret"
        }

        onExited: root.promptSecret = false
    }

    // {mods: [...], key: "C", id: n}, key being a jamo for a letter typed in
    // Hangul. With waiting below, the only place keys are kept: at most
    // maxVisible between the two, each chord dropped by its cap's exit
    // (dwell plus the fall, under a second), all of them on Super+Y off, on a
    // lock or unlock and when a password is being typed. Nothing reads them
    // but the overlay.
    property var chords: []

    readonly property int dwellMs: 500

    readonly property int maxVisible: 5

    // A letter typed into Hangul is drawn as the jamo fcitx5-hangul makes of
    // it, the shifted ones included. The tables are Dubeolsik, the layout
    // fcitx5/conf/hangul.conf sets; another layout there needs its own here.
    // Caps Lock is left out: the engine undoes it, so Shift alone decides.
    readonly property var dubeolsik: ({
        Q: "ㅂ", W: "ㅈ", E: "ㄷ", R: "ㄱ", T: "ㅅ", Y: "ㅛ", U: "ㅕ", I: "ㅑ", O: "ㅐ", P: "ㅔ",
        A: "ㅁ", S: "ㄴ", D: "ㅇ", F: "ㄹ", G: "ㅎ", H: "ㅗ", J: "ㅓ", K: "ㅏ", L: "ㅣ",
        Z: "ㅋ", X: "ㅌ", C: "ㅊ", V: "ㅍ", B: "ㅠ", N: "ㅜ", M: "ㅡ"
    })

    readonly property var dubeolsikShift: ({ Q: "ㅃ", W: "ㅉ", E: "ㄸ", R: "ㄲ", T: "ㅆ", O: "ㅒ", P: "ㅖ" })

    // With Ctrl, Alt or Super held the engine passes a letter on untouched:
    // it is a shortcut then, and stays latin.
    function typesJamo(mods, key) {
        return root.dubeolsik[key] !== undefined && mods.every(m => m === "Shift");
    }

    function jamoFor(mods, key) {
        if (!root.typesJamo(mods, key))
            return key;
        return (mods.indexOf("Shift") !== -1 ? root.dubeolsikShift[key] : undefined) ?? root.dubeolsik[key];
    }

    // fcitx5-hangul converting in the focused field, by a reading that is
    // not stale: with the helper gone or fcitx5 not answering, keys are
    // drawn as they always were.
    readonly property bool hangul: Ime.hangul && Ime.method === "hangul" && Ime.asOf !== 0

    // Keys waiting on the input method (Ime.ask), in the order typed: a
    // letter, and whatever came behind it before the answer. Milliseconds as
    // a rule, answerMs at most.
    property var waiting: []

    readonly property int answerMs: 100

    // A key from the reader. A letter waits for a reading taken after it was
    // typed, so the first one after a switch to Hangul is drawn as Hangul;
    // drawn with the poll's last reading, it came out latin about half the
    // time.
    function receive(mods, key) {
        if (root.locked || root.guarded)
            return;
        if (root.waiting.length === 0 && !(root.typesJamo(mods, key) && Ime.asOf !== 0)) {
            root.push(mods, key);
            return;
        }
        root.waiting = root.waiting.concat([{ mods: mods, key: key }]);
        root.fit();
        if (answerWait.running)
            return;
        if (Ime.ask())
            answerWait.start();
        else
            root.settle();
    }

    // The waiting keys drawn, with whatever reading came last: the answer,
    // or after answerMs the one before it.
    function settle() {
        answerWait.stop();
        const batch = root.waiting;
        root.waiting = [];
        for (let i = 0; i < batch.length; i++) {
            root.push(batch[i].mods, root.hangul ? root.jamoFor(batch[i].mods, batch[i].key) : batch[i].key);
            root.scrub(batch[i]);
        }
    }

    // Held to maxVisible keys between the two lists: the oldest chord goes
    // first, as push() would cut it a moment later.
    function fit() {
        while (root.chords.length + root.waiting.length > root.maxVisible) {
            if (root.chords.length > 0) {
                const next = root.chords.slice();
                root.scrub(next.shift());
                root.chords = next;
            } else {
                const next = root.waiting.slice();
                root.scrub(next.shift());
                root.waiting = next;
            }
        }
    }

    Timer {
        id: answerWait

        interval: root.answerMs
        onTriggered: root.settle()
    }

    Connections {
        target: Ime

        function onAnswered() {
            if (answerWait.running)
                root.settle();
        }
    }

    // Keys Inter has no symbol for, drawn from the icon font instead. Modifier
    // and other key symbols live in Theme.modSymbol / Theme.keySymbol.
    readonly property var keyIcon: ({
        "Playpause":  Theme.iconPlay,
        "Play":       Theme.iconPlay,
        "Pause":      Theme.iconPause,
        "Nextsong":   Theme.iconNext,
        "Previoussong": Theme.iconPrev,
        "Stopcd":     Theme.iconStop,
        "Mute":       Theme.iconVolumeOff,
        "Volumedown": Theme.iconVolumeLow,
        "Volumeup":   Theme.iconVolume,
        "Brightnessdown": Theme.iconBrightness,
        "Brightnessup":   Theme.iconBrightness,
        "Power":      Theme.iconPower,
        "Sleep":      Theme.iconSleep,
        "Search":     Theme.iconSearch,
        "Compose":    Theme.iconApps
    })

    function keyLabel(name) {
        return root.keyIcon[name] ?? Theme.keySymbol[name] ?? name;
    }

    // Tells KeyCap which font to use; the wrong one draws a box.
    function keyIsIcon(name) {
        return root.keyIcon[name] !== undefined;
    }

    // Printed order. The feed sends names; symbols are the shell's concern.
    // A scrubbed chord has none.
    function symbolsFor(mods) {
        if (!mods)
            return "";
        const order = ["Ctrl", "Alt", "Shift", "Super"];
        let out = "";
        for (let i = 0; i < order.length; i++)
            if (mods.indexOf(order[i]) !== -1)
                out += Theme.modSymbol[order[i]];
        return out;
    }

    property int nextId: 0
    property string failure: ""

    readonly property bool running: feed.running

    // A chord leaving gives its key up at once. Its object can outlive the
    // list (an older copy in the model, a delegate being torn down), and
    // nothing should lead to the key through it. This drops the reference,
    // not the bytes: the engine frees a string when it collects it and does
    // not clear it, which is why the bar never writes a core file (bin/bar).
    function scrub(chord) {
        chord.key = null;
        chord.mods = null;
    }

    function push(mods, key) {
        if (root.locked || root.guarded)
            return;
        const next = root.chords.concat([{ mods: mods, key: key, id: root.nextId }]);
        root.nextId = root.nextId + 1;
        // Overflow is cut without an exit animation; animating it kept its
        // width and stacked chords across the screen during fast typing.
        while (next.length > root.maxVisible)
            root.scrub(next.shift());
        root.chords = next;
    }

    function drop(id) {
        const next = [];
        for (let i = 0; i < root.chords.length; i++) {
            if (root.chords[i].id !== id)
                next.push(root.chords[i]);
            else
                root.scrub(root.chords[i]);
        }
        root.chords = next;
    }

    function clear() {
        for (let i = 0; i < root.chords.length; i++)
            root.scrub(root.chords[i]);
        root.chords = [];
        answerWait.stop();
        for (let i = 0; i < root.waiting.length; i++)
            root.scrub(root.waiting[i]);
        root.waiting = [];
    }

    function toggle() {
        root.chosen = true;
        root.setEnabled(!root.enabled);
    }

    function setEnabled(on) {
        // Said before the stop, which a reader of root's would not feel
        // (see feed).
        if (!on && feed.running)
            feed.write("stop\n");
        root.enabled = on;
        root.failure = "";
        supervisor.stop();
        supervisor.delay = 2000;
        if (!on)
            root.clear();
        store.setText(on ? "on\n" : "off\n");
    }

    FileView {
        id: store

        path: Paths.stateDir + "/keyoverlay"
        // A missing file is the default state, not an error worth a log line.
        printErrors: false

        onLoaded: {
            if (!root.chosen)
                root.enabled = store.text().trim() === "on";
        }
        onSaveFailed: error => console.warn("[keyfeed] could not keep the switch in", store.path, "-", error)
    }

    // Whether the reader may read keys at all: not while the session is
    // locked or a password is being typed. Said to the reader on every
    // change and as it starts; paused, it holds no keyboard open, so those
    // keys are read by nothing (keyfeed.py). push() drops any that cross on
    // the way.
    readonly property bool readerOpen: !root.locked && !root.guarded

    onReaderOpenChanged: root.steer()

    function steer() {
        if (feed.running)
            feed.write(root.readerOpen ? "resume\n" : "pause\n");
    }

    // The session's console, for the reader to hold the keys back while
    // another one is in front (a text console's login, another greeter).
    readonly property string vt: Quickshell.env("XDG_VTNR") ?? ""

    // Root's copy of the reader, put in place by install.sh's sudo step.
    // KEYFEED_SYSTEM points the tests at a stand-in (polkit judges the path
    // pkexec is handed, so another path gains nothing).
    readonly property string reader: Quickshell.env("KEYFEED_SYSTEM") || "/usr/local/libexec/keyfeed"

    // pkexec's last complaint, which tells a missing agent from a refusal.
    property string complaint: ""

    // A start that found no polkit agent to ask (the bar can come up before
    // it at login) is tried again, 2 s to a minute apart. Nothing else is:
    // every start costs a password, so a refusal or a reader that stopped
    // waits for Super+Y, with the reason in the strip until then.
    Timer {
        id: supervisor

        property int delay: 2000

        interval: supervisor.delay
        onTriggered: {
            if (!root.enabled)
                return;
            supervisor.delay = Math.min(supervisor.delay * 2, 60000);
            feed.running = true;
            // Restored, or the reader would outlive Super+Y.
            feed.running = Qt.binding(() => root.enabled);
        }
    }

    Process {
        id: feed

        running: root.enabled
        // Through bash rather than pkexec alone: once authorized, pkexec
        // becomes the reader, a process of root's that the bar cannot
        // signal. bash can be stopped, and passes the stop on while pkexec
        // still asks; after that, its end of stdin closing is the reader's
        // signal to go (keyfeed.py). stdin is passed explicitly: a
        // background job's is /dev/null otherwise. 69 (EX_UNAVAILABLE): root's
        // copy is not installed.
        command: ["bash", "-c",
            "[ -x \"$0\" ] || exit 69; " +
            "trap 'kill \"$p\" 2>/dev/null; exit 143' TERM; " +
            "pkexec \"$0\" \"$@\" 0<&0 & p=$!; wait \"$p\"",
            root.reader].concat(/^[0-9]+$/.test(root.vt) ? ["--vt", root.vt] : [])
        stdinEnabled: true

        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    root.complaint = line.trim();
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t === "")
                    return;
                let msg;
                try {
                    msg = JSON.parse(t);
                } catch (e) {
                    // Its length only: a line can carry a key, and the
                    // journal is kept on disk.
                    console.warn("[keyfeed] unparseable line of", t.length, "characters");
                    return;
                }
                if (msg.type === "key") {
                    root.failure = "";
                    root.receive(msg.mods ?? [], msg.key ?? "?");
                } else if (msg.type === "ready") {
                    root.failure = "";
                    supervisor.delay = 2000;
                    // It starts paused; it learns whether to send now.
                    root.steer();
                } else if (msg.type === "error") {
                    root.failure = msg.reason ?? "unknown";
                    console.warn("[keyfeed]", root.failure);
                }
            }
        }

        // pkexec: 126 the dialog was dismissed, 127 not authorized or no
        // agent to ask. 143 is this bar stopping it.
        onExited: code => {
            // Taken and cleared, so a later start reports only its own.
            const complaint = root.complaint;
            root.complaint = "";
            if (!root.enabled || code === 143)
                return;
            if (code === 126) {
                // The user said no: the overlay goes off rather than ask again.
                console.warn("[keyfeed] authentication dismissed; the overlay is off");
                root.setEnabled(false);
                return;
            }
            if (code === 127 && /authentication agent/i.test(complaint)) {
                root.failure = "waiting for a polkit agent to ask for the password";
                console.warn("[keyfeed]", root.failure, "- retrying");
                supervisor.restart();
                return;
            }
            if (code === 69)
                root.failure = "the key reader is not installed; ./install.sh puts it in place";
            else if (code === 127)
                root.failure = complaint !== "" ? complaint : "not authorized to read the keyboards";
            else if (root.failure === "")
                root.failure = `the key reader stopped (${code}); Super+Y twice starts it again`;
            console.warn("[keyfeed]", root.failure);
        }
    }
}
