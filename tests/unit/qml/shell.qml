import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import "modules"
import qs.services

// Unit tests for the bar's own logic, run by tests/unit/qml.sh in a copy of
// quickshell/bar with this file as its shell.qml: offscreen, on no bus, with
// state and config in a temporary directory. What is tested is the code that
// decides (URL filters, the override file the Displays panel writes, launcher
// ranking, notification markup), not what is drawn.
ShellRoot {
    id: root

    property int passed: 0
    property int failed: 0

    // Values compare as JSON, so arrays and objects compare by content.
    function check(name, got, want) {
        const a = JSON.stringify(got);
        const b = JSON.stringify(want);
        if (a === b) {
            root.passed += 1;
            return;
        }
        root.failed += 1;
        console.log(`[test] FAIL ${name}: got ${a}, want ${b}`);
    }

    // Launcher and Displays own layer windows, which need a Wayland display:
    // offscreen there is no PanelWindow backend and the file would not load.
    // Their suites run when a display is there (the nested session of
    // tests/e2e), and are left out otherwise.
    Loader {
        id: modules

        active: Quickshell.env("WAYLAND_DISPLAY") !== null && Quickshell.env("WAYLAND_DISPLAY") !== ""
        source: "TestModules.qml"
    }

    function testTheme() {
        check("battery: charging is one glyph at any level", Theme.batteryIcon(37, true), String.fromCodePoint(0xF0084));
        check("battery: empty", Theme.batteryIcon(2, false), String.fromCodePoint(0xF008E));
        check("battery: a level", Theme.batteryIcon(44, false), String.fromCodePoint(0xF007D));
        check("battery: full", Theme.batteryIcon(100, false), String.fromCodePoint(0xF0079));
        check("volume: muted is off at any level", Theme.volumeIcon(80, true), Theme.iconVolumeOff);
        check("art: an allowed host", Theme.localArt("https://i.scdn.co/image/x"), "https://i.scdn.co/image/x");
        check("art: a local file", Theme.localArt("file:///tmp/cover.png"), "file:///tmp/cover.png");
        check("art: plain http", Theme.localArt("http://i.scdn.co/image/x"), "");
        check("art: an allowed name as a prefix of another host", Theme.localArt("https://i.scdn.co.evil.example/x"), "");
        check("art: an allowed name as userinfo", Theme.localArt("https://i.scdn.co@evil.example/x"), "");
        check("art: userinfo before an allowed host", Theme.localArt("https://user@i.scdn.co/x"), "https://user@i.scdn.co/x");
        check("art: a port on an allowed host", Theme.localArt("https://i.scdn.co:8443/x"), "https://i.scdn.co:8443/x");
        check("art: upper case host", Theme.localArt("https://I.SCDN.CO/x"), "https://I.SCDN.CO/x");
        check("art: empty", Theme.localArt(""), "");
        check("art: an allowed host after ?@", Theme.localArt("https://evil.example?@i.scdn.co/x"), "");
        check("art: an allowed host after #@", Theme.localArt("https://evil.example#@i.scdn.co/x"), "");
        check("art: not a URL", Theme.localArt("https://"), "");
        check("shorten: short", Theme.shorten("kitty", 8), "kitty");
        check("shorten: long", Theme.shorten("abcdefghij", 5), "abcd…");
        check("fit: no screen", Theme.fit(null), 1);
    }

    function testNotifications() {
        check("img: removed", Notifications.withoutImages("a<img src=\"https://x/y.png\">b"), "ab");
        check("img: upper case", Notifications.withoutImages("<IMG SRC=x>text"), "text");
        check("img: spaces", Notifications.withoutImages("< img src=x >text"), "text");
        check("img: unclosed", Notifications.withoutImages("text<img src=https://x"), "text");
        check("img: other markup kept", Notifications.withoutImages("<b>bold</b>"), "<b>bold</b>");
        check("img: nested to survive one pass", Notifications.withoutImages("a<im<img>g src=\"http://x/y\">b"), "ab");
        const saved = Notifications.history;
        const now = Date.now();
        const stale = { id: 901, key: 901, summary: "old", body: "code 1234", actions: [{ text: "Open", identifier: "o" }],
                        at: now - 25 * 3600000, read: true, live: null };
        const recent = { id: 902, key: 902, summary: "new", body: "b", actions: [], at: now - 3600000, read: false, live: null };
        Notifications.history = [recent, stale];
        Notifications.expire();
        check("history: an entry a day old expires", Notifications.history.map(e => e.id), [902]);
        check("history: and gives its text up", [stale.summary, stale.body, stale.actions], ["", "", []]);
        Notifications.dismiss(902);
        check("history: so does a dismissed one", recent.summary, "");
        Notifications.history = saved;
        const fake = { id: 9901, appName: "t", appIcon: "", summary: "old", body: "b", urgency: 0, actions: [], tracked: true };
        Notifications.history = [Object.assign(Notifications.snapshot(fake), { at: 5, read: true })].concat(Notifications.history);
        const firstKey = Notifications.history[0].key;
        fake.summary = "new";
        Notifications.refresh(fake);
        const replaced = Notifications.history.find(e => e.id === 9901);
        check("replace: the entry is refreshed in place", replaced.summary, "new");
        check("replace: it keeps its arrival", replaced.at, 5);
        check("replace: it is unread again", replaced.read, false);
        check("replace: its toast is a new card", replaced.key !== firstKey, true);
        check("invoke: a gone sender is refused", Notifications.invoke({ id: 1, live: { tracked: false } }, "x"), false);
        Notifications.dismiss(9901);
        check("sender: notify-send", Notifications.senderName("notify-send"), "");
        check("sender: named", Notifications.senderName("Firefox"), "Firefox");
    }

    function testScreensaver() {
        Screensaver.parse("# kept\nSamsung Display Corp. 0x419D\t3\nname:HDMI-A-1\t10\nname:DP-1\t0\nbad line\n");
        check("saver: entries", Screensaver.entries,
              [{ selector: "Samsung Display Corp. 0x419D", minutes: 3 }, { selector: "name:HDMI-A-1", minutes: 10 }]);
        check("saver: kept lines", Screensaver.kept, ["# kept", "name:DP-1\t0", "bad line"]);
        check("saver: by description", Screensaver.minutesOf("eDP-1", "Samsung Display Corp. 0x419D"), 3);
        check("saver: by connector", Screensaver.minutesOf("HDMI-A-1", "Philips 27M2N5500"), 10);
        check("saver: none", Screensaver.minutesOf("DP-2", ""), 0);
        Screensaver.parse("name:eDP-1\t5\nSamsung Display Corp. 0x419D\t3\n");
        check("saver: a description line wins", Screensaver.minutesOf("eDP-1", "Samsung Display Corp. 0x419D"), 3);
        check("saver: commas dropped", Screensaver.normalize("Acme, Inc. Model, 1 "), "Acme Inc. Model 1");
    }

    function testKeyFeed() {
        // hyprctl holds its answer until keyLockSteps lets it go.
        check("keys: a bar starts locked until it knows there is no lock", KeyFeed.locked, true);
        KeyFeed.locked = false;
        check("mods: printed order", KeyFeed.symbolsFor(["Super", "Shift", "Ctrl"]),
              Theme.modSymbol.Ctrl + Theme.modSymbol.Shift + Theme.modSymbol.Super);
        check("keys: icon", KeyFeed.keyIsIcon("Playpause"), true);
        check("keys: word", KeyFeed.keyIsIcon("Esc"), false);
        KeyFeed.clear();
        for (let i = 0; i < 8; i++)
            KeyFeed.push([], String(i));
        check("chords: capped", KeyFeed.chords.map(c => c.key), ["3", "4", "5", "6", "7"]);
        KeyFeed.clear();
        KeyFeed.locked = true;
        KeyFeed.push([], "p");
        check("chords: none while locked", KeyFeed.chords.length, 0);
        KeyFeed.locked = false;
        KeyFeed.push([], "x");
        check("chords: back after the unlock", KeyFeed.chords.map(c => c.key), ["x"]);
        KeyFeed.clear();
        // A chord that leaves gives its key up, wherever its object went.
        KeyFeed.push(["Ctrl"], "s");
        const dropped = KeyFeed.chords[0];
        KeyFeed.drop(dropped.id);
        check("scrub: a dropped chord keeps no key", [dropped.key, dropped.mods], [null, null]);
        KeyFeed.push([], "a");
        const cleared = KeyFeed.chords[0];
        KeyFeed.clear();
        check("scrub: nor does a cleared one", cleared.key, null);
        for (let i = 0; i < 5; i++)
            KeyFeed.push([], String(i));
        const oldest = KeyFeed.chords[0];
        KeyFeed.push([], "5");
        check("scrub: nor one cut by the cap", oldest.key, null);
        KeyFeed.clear();
        check("mods: a scrubbed chord prints none", KeyFeed.symbolsFor(null), "");
        const dialogs = ["org.kde.polkit-kde-authentication-agent-1", "hyprpolkitagent", "lxqt-policykit-agent",
                         "org.gnupg.pinentry-qt", "org.kde.ksshaskpass", "gcr-prompter", "org.kde.kwalletd6"];
        check("secret: password windows are known", dialogs.filter(c => !KeyFeed.secretWindows.test(c)), []);
        check("secret: other windows are not", ["kitty", "firefox", "org.kde.dolphin", "code-oss"]
              .filter(c => KeyFeed.secretWindows.test(c)), []);
        KeyFeed.guarded = true;
        KeyFeed.push([], "p");
        check("chords: none while a password is typed", KeyFeed.chords.length, 0);
        KeyFeed.guarded = false;
        // As at the start, until the probe answers.
        KeyFeed.locked = true;
        check("hangul: letters", ["R", "K", "M", "Z"].map(k => KeyFeed.jamoFor([], k)), ["ㄱ", "ㅏ", "ㅡ", "ㅋ"]);
        check("hangul: with Shift", ["R", "T", "O", "K"].map(k => KeyFeed.jamoFor(["Shift"], k)), ["ㄲ", "ㅆ", "ㅒ", "ㅏ"]);
        check("hangul: a shortcut stays latin", [KeyFeed.jamoFor(["Ctrl"], "R"), KeyFeed.jamoFor(["Shift", "Super"], "R")],
              ["R", "R"]);
        check("hangul: not a letter", [KeyFeed.jamoFor([], "1"), KeyFeed.jamoFor(["Shift"], "Space")], ["1", "Space"]);
        const jamo = Object.values(KeyFeed.dubeolsik);
        check("hangul: 26 letters, 26 jamo", [jamo.length, jamo.filter((j, i) => jamo.indexOf(j) !== i)], [26, []]);
        check("hangul: shifted keys are letters",
              Object.keys(KeyFeed.dubeolsikShift).filter(k => KeyFeed.dubeolsik[k] === undefined), []);
        check("caps: Hangul ones are as tall as latin ones",
              [jamoCap.implicitHeight, wordCap.implicitHeight], [latinCap.implicitHeight, latinCap.implicitHeight]);
    }

    KeyCap {
        id: latinCap

        visible: false
        mods: Theme.modSymbol.Shift
        text: "R"
    }

    KeyCap {
        id: jamoCap

        visible: false
        mods: Theme.modSymbol.Shift
        text: "ㄲ"
    }

    KeyCap {
        id: wordCap

        visible: false
        text: "한/영"
    }

    function keyLockSteps() {
        return [
            { wait: 50, run: () => Quickshell.execDetached(["touch", Quickshell.env("QML_TEST_LOCK_GO")]) },
            { wait: 500, run: () => check("keys: a session the compositor calls unlocked unlocks them", KeyFeed.locked, false) }
        ];
    }

    // The reader through pkexec, with the stand-ins of tests/unit/qml.sh.
    readonly property string keyDir: Quickshell.env("KEYFEED_TEST_DIR") ?? ""
    property string keyLog: ""
    property string keyControl: ""

    FileView {
        id: keyControlFile

        path: root.keyDir + "/control"
        watchChanges: true
        printErrors: false

        onFileChanged: keyControlFile.reload()
        onLoaded: root.keyControl = keyControlFile.text()
        onLoadFailed: root.keyControl = ""
    }

    FileView {
        id: keyLogFile

        path: root.keyDir + "/log"
        watchChanges: true
        printErrors: false

        onFileChanged: keyLogFile.reload()
        onLoaded: root.keyLog = keyLogFile.text()
        onLoadFailed: root.keyLog = ""
    }

    FileView {
        id: keyArgsFile

        path: root.keyDir + "/args"
        blockLoading: true
        printErrors: false
    }

    readonly property string echoFlag: Quickshell.env("ECHOWATCH_TEST_FLAG") ?? ""

    FileView {
        id: echoLog

        path: Quickshell.env("ECHOWATCH_TEST_LOG") ?? ""
        blockLoading: true
        printErrors: false
    }

    function keyMode(mode) {
        Quickshell.execDetached(["sh", "-c", `printf %s "$2" > "$1/mode"`, "sh", root.keyDir, mode]);
    }

    function keyFeedSteps() {
        const reader = Quickshell.env("KEYFEED_SYSTEM");
        return [
            { wait: 0, run: () => {
                root.keyMode("ok");
                KeyFeed.toggle();
            } },
            { wait: 700, run: () => {
                keyArgsFile.reload();
                check("reader: told the session's console", keyArgsFile.text().trim(), "--vt 7");
                check("reader: told to send once it is ready", root.keyControl, "resume\n");
                check("reader: its keys reach the overlay", KeyFeed.chords.map(c => c.key), ["K"]);
                check("reader: started once", root.keyLog, "started\n");
                KeyFeed.clear();
                KeyFeed.locked = true;
            } },
            { wait: 300, run: () => {
                check("reader: a lock pauses it", root.keyControl, "resume\npause\n");
                KeyFeed.locked = false;
            } },
            { wait: 300, run: () => {
                check("reader: the unlock resumes it", root.keyControl, "resume\npause\nresume\n");
                check("reader: and its keys come again", KeyFeed.chords.map(c => c.key), ["K"]);
                echoLog.reload();
                check("prompt: the watcher is told the focused window", echoLog.text(), "pid 0\n");
                Quickshell.execDetached(["touch", root.echoFlag]);
            } },
            { wait: 400, run: () => {
                check("prompt: a terminal asking for a password pauses the reader",
                      [KeyFeed.guarded, root.keyControl], [true, "resume\npause\nresume\npause\n"]);
                check("prompt: and what was drawn goes", KeyFeed.chords.length, 0);
                KeyFeed.push([], "p");
                check("prompt: nothing is drawn meanwhile", KeyFeed.chords.length, 0);
                Quickshell.execDetached(["rm", "-f", root.echoFlag]);
            } },
            { wait: 250, run: () => check("prompt: held a moment after", KeyFeed.guarded, true) },
            { wait: 500, run: () => {
                check("prompt: then the reader resumes", root.keyControl, "resume\npause\nresume\npause\nresume\n");
                KeyFeed.toggle();
            } },
            { wait: 700, run: () => {
                check("reader: Super+Y off tells it to stop", root.keyControl,
                      "resume\npause\nresume\npause\nresume\nstop\n");
                check("reader: and it stops, though the bar cannot signal it", root.keyLog, "started\nstopped\n");
                root.keyMode("dismiss");
            } },
            { wait: 100, run: () => KeyFeed.toggle() },
            { wait: 700, run: () => {
                check("reader: a dismissed password turns the overlay off", KeyFeed.enabled, false);
                root.keyMode("refuse");
            } },
            { wait: 100, run: () => KeyFeed.toggle() },
            { wait: 700, run: () => {
                check("reader: a refusal leaves it on with pkexec's reason", [KeyFeed.enabled, KeyFeed.failure],
                      [true, "Error executing command as another user: Not authorized"]);
                check("reader: and asks no more", KeyFeed.running, false);
                root.keyMode("noagent");
                KeyFeed.toggle();
            } },
            { wait: 100, run: () => KeyFeed.toggle() },
            { wait: 700, run: () => {
                check("reader: a missing agent is said, and not asked for again by itself", KeyFeed.failure,
                      "no polkit agent to ask for the password; Super+Y twice tries again");
                root.keyMode("ok");
                KeyFeed.toggle();
            } },
            { wait: 100, run: () => KeyFeed.toggle() },
            { wait: 700, run: () => {
                check("reader: Super+Y twice starts it", [KeyFeed.failure, KeyFeed.chords.map(c => c.key)], ["", ["K"]]);
                KeyFeed.toggle();
                Quickshell.execDetached(["chmod", "-x", reader]);
            } },
            { wait: 300, run: () => KeyFeed.toggle() },
            { wait: 600, run: () => {
                check("reader: one not installed is said", KeyFeed.failure,
                      "the key reader is not installed; ./install.sh puts it in place");
                KeyFeed.toggle();
                Quickshell.execDetached(["chmod", "+x", reader]);
            } }
        ];
    }

    // The input method helper of tests/unit/qml.sh, which answers only when
    // asked: a reading changed behind the bar's back stands for a switch the
    // poll has not seen yet.
    readonly property string imeDir: Quickshell.env("IME_TEST_DIR") ?? ""
    property int imeAsks: 0

    FileView {
        id: imeAskLog

        path: root.imeDir + "/asks"
        watchChanges: true
        printErrors: false

        onFileChanged: imeAskLog.reload()
        onLoaded: root.imeAsks = imeAskLog.text().split("\n").filter(l => l === "ask").length
        onLoadFailed: root.imeAsks = 0
    }

    function imeReading(line) {
        Quickshell.execDetached(["sh", "-c", line === null ? `rm -f "$1/reading"` : `printf '%s\\n' "$2" > "$1/reading"`,
                                 "sh", root.imeDir, line ?? ""]);
    }

    function imeMute(on) {
        Quickshell.execDetached(on ? ["touch", root.imeDir + "/mute"] : ["rm", "-f", root.imeDir + "/mute"]);
    }

    function imeSteps() {
        return [
            { wait: 0, run: () => {
                check("ime: the helper's reading at the start", [Ime.state, Ime.method], ["1", "keyboard-kr-kr104"]);
                check("ime: latin is not drawn as Hangul", KeyFeed.hangul, false);
                KeyFeed.clear();
                root.imeReading("2\thangul");
            } },
            { wait: 300, run: () => {
                check("ime: a switch not seen yet", Ime.state, "1");
                KeyFeed.receive([], "R");
                check("ime: a letter waits for the answer", [KeyFeed.chords.length, KeyFeed.waiting.length], [0, 1]);
            } },
            { wait: 300, run: () => {
                check("ime: it asked", root.imeAsks, 1);
                check("ime: the first letter after a switch is Hangul", KeyFeed.chords.map(c => c.key), ["ㄱ"]);
                KeyFeed.receive(["Shift"], "R");
                KeyFeed.receive([], "Space");
                KeyFeed.receive(["Ctrl"], "R");
            } },
            { wait: 300, run: () => {
                check("ime: what came behind a waiting letter keeps its place",
                      KeyFeed.chords.map(c => [c.mods, c.key]), [[[], "ㄱ"], [["Shift"], "ㄲ"], [[], "Space"], [["Ctrl"], "R"]]);
                check("ime: one ask for the lot", root.imeAsks, 2);
                KeyFeed.clear();
                root.imeReading("1\tkeyboard-kr-kr104");
            } },
            { wait: 300, run: () => KeyFeed.receive([], "R") },
            { wait: 300, run: () => {
                check("ime: switched back, latin again", KeyFeed.chords.map(c => c.key), ["R"]);
                KeyFeed.clear();
                root.imeMute(true);
                root.imeReading("2\thangul");
            } },
            { wait: 300, run: () => KeyFeed.receive([], "A") },
            { wait: 50, run: () => check("ime: unanswered, it waits", KeyFeed.waiting.length, 1) },
            { wait: 250, run: () => {
                check("ime: then is drawn with the last reading", [KeyFeed.waiting.length, KeyFeed.chords.map(c => c.key)],
                      [0, ["A"]]);
                KeyFeed.clear();
                root.imeMute(false);
            } },
            { wait: 300, run: () => {
                for (let i = 0; i < 5; i++)
                    KeyFeed.push([], String(i));
                KeyFeed.receive([], "R");
                check("ime: five keys at most, waiting ones counted", [KeyFeed.chords.length, KeyFeed.waiting.length], [4, 1]);
                // What lock() does.
                KeyFeed.locked = true;
                KeyFeed.clear();
            } },
            { wait: 300, run: () => {
                check("ime: a letter waiting at a lock is never drawn", KeyFeed.chords.length, 0);
                KeyFeed.locked = false;
                root.imeReading(null);
            } },
            { wait: 300, run: () => KeyFeed.receive([], "R") },
            { wait: 300, run: () => {
                check("ime: fcitx5 not answering reads latin", [Ime.asOf, KeyFeed.chords.map(c => c.key)], [0, ["R"]]);
                KeyFeed.receive([], "K");
                check("ime: and nothing waits for it", [KeyFeed.waiting.length, KeyFeed.chords.map(c => c.key)],
                      [0, ["R", "K"]]);
                KeyFeed.clear();
            } }
        ];
    }

    function testCamera() {
        const cam = (name, state) => ({ name: name, state: state, nodes: state === "on" ? ["video0"] : [] });
        const reading = (sw, cameras, switches) => ({ switch: sw, busy: false, cameras: cameras,
                                                      power_switches: switches ?? [], missing: [] });
        check("camera: no reading", Camera.classify(null), "unknown");
        check("camera: no cameras list", Camera.classify({ switch: "off" }), "unknown");
        check("camera: on", Camera.classify(reading("on", [cam("A", "on")])), "on");
        check("camera: on with none", Camera.classify(reading("on", [])), "on");
        check("camera: off with none", Camera.classify(reading("off", [])), "none");
        check("camera: off", Camera.classify(reading("off", [cam("A", "off"), cam("B", "off")])), "off");
        check("camera: off, one live", Camera.classify(reading("off", [cam("A", "off"), cam("B", "on")])), "leak");
        check("camera: on, one dark", Camera.classify(reading("on", [cam("A", "on"), cam("B", "off")])), "stuck");
        check("camera: off by firmware alone", Camera.classify(reading("off", [], [{ name: "fw", state: "off" }])), "off");
        check("camera: on, firmware still off", Camera.classify(reading("on", [], [{ name: "fw", state: "off" }])), "stuck");
    }

    // The camera stand-ins of tests/unit/qml.sh, driven through files.
    readonly property string camDir: Quickshell.env("CAMERA_TEST_DIR") ?? ""

    function sh(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd, "sh", root.camDir]);
    }

    function camStatus(sw, state) {
        const r = { switch: sw, busy: false, cameras: [{ name: "Cam A", state: state, nodes: state === "on" ? ["video0"] : [] }],
                    power_switches: [], missing: [] };
        root.sh(`printf '%s\\n' '${JSON.stringify(r)}' > "$1/status.new" && mv "$1/status.new" "$1/status.json"`);
    }

    function camBusy() {
        const r = { switch: "off", busy: true, cameras: [{ name: "Cam A", state: "on", nodes: ["video0"] }],
                    power_switches: [], missing: [] };
        root.sh(`printf '%s\\n' '${JSON.stringify(r)}' > "$1/status.new" && mv "$1/status.new" "$1/status.json"`);
    }

    function camEvents(n) {
        root.sh(`i=0; while [ $i -lt ${n} ]; do i=$((i+1)); echo "UDEV  [1.$i] add      /devices/test/video4linux/video$i (video4linux)" >> "$1/events"; done`);
    }

    // Counted as the stand-in appends: text() right after reload() still
    // returns the previous load.
    property int camCallCount: 0

    function camCalls() {
        return root.camCallCount;
    }

    FileView {
        id: calls

        path: root.camDir + "/calls"
        watchChanges: true
        printErrors: false

        onFileChanged: calls.reload()
        onLoaded: root.camCallCount = calls.text().split("\n").filter(l => l === "run").length
        onLoadFailed: root.camCallCount = 0
    }

    // The camera service on events: a step waits, then acts or checks. The
    // reading starts as switch off, camera off (tests/unit/qml.sh).
    // Caps Lock, from the same helper: the stub prints what $WORK/caps
    // holds, on change.
    readonly property string capsFile: Quickshell.env("CAPS_TEST_FILE") ?? ""

    function capsWrite(value) {
        Quickshell.execDetached(["sh", "-c", `printf '%s\\n' "$2" > "$1"`, "sh", root.capsFile, value]);
    }

    function capsSteps() {
        return [
            { wait: 0, run: () => {
                check("caps: off at the start", [InputWatch.caps, InputWatch.capsAsOf > 0], [false, true]);
                root.capsWrite("1");
            } },
            { wait: 300, run: () => {
                check("caps: on", [InputWatch.caps, InputWatch.capsAsOf > 0], [true, true]);
                root.capsWrite("-");
            } },
            { wait: 300, run: () => {
                check("caps: no LED readable keeps the reading, marked unknown",
                      [InputWatch.caps, InputWatch.capsAsOf], [true, 0]);
                root.capsWrite("0");
            } },
            { wait: 300, run: () => check("caps: off again", [InputWatch.caps, InputWatch.capsAsOf > 0], [false, true]) }
        ];
    }

    function cameraSteps() {
        return [
            { wait: 600, run: () => {
                check("camera events: one read at start", root.camCalls(), 1);
                check("camera events: off at start", Camera.state, "off");
                check("camera events: shown while off", Camera.shown, true);
                root.camStatus("on", "on");
            } },
            { wait: 150, run: () => root.camEvents(1) },
            { wait: 700, run: () => {
                check("camera events: a device event reads", root.camCalls(), 2);
                check("camera events: on after it", Camera.state, "on");
                check("camera events: hidden while on", Camera.shown, false);
                root.camEvents(6);
            } },
            { wait: 900, run: () => {
                check("camera events: a burst is one read", root.camCalls(), 3);
                root.camBusy();
            } },
            { wait: 150, run: () => Camera.refresh() },
            { wait: 300, run: () => {
                check("camera events: refresh reads at once", root.camCalls(), 4);
                check("camera events: a reading under the lock is not shown", Camera.state, "on");
                root.camStatus("off", "off");
            } },
            { wait: 800, run: () => {
                check("camera events: read again once the lock is free", Camera.state, "off");
                root.camStatus("off", "on");
            } },
            { wait: 150, run: () => root.camEvents(1) },
            { wait: 700, run: () => {
                check("camera events: a live camera under an off switch", Camera.state, "leak");
                root.sh(`echo 1 > "$1/exit"`);
            } },
            { wait: 150, run: () => Camera.refresh() },
            { wait: 400, run: () => {
                check("camera events: a failed read is noted", Camera.failure !== "", true);
                check("camera events: the last reading stays", Camera.state, "leak");
                root.sh(`echo 0 > "$1/exit"`);
                root.camStatus("off", "off");
            } },
            { wait: 2400, run: () => {
                check("camera events: the retry clears the failure", Camera.failure, "");
                check("camera events: the retry reads the new state", Camera.state, "off");
                root.sh(`: > "$1/calls"; touch "$1/state/off"`);
            } },
            { wait: 800, run: () => {
                check("camera events: the switch file is an event", root.camCalls(), 1);
                root.sh(`echo 127 > "$1/exit"`);
            } },
            { wait: 150, run: () => Camera.refresh() },
            { wait: 400, run: () => {
                check("camera events: nothing installed, nothing shown", Camera.shown, false);
                check("camera events: nothing installed", Camera.installed, false);
                root.sh(`echo 0 > "$1/exit"`);
            } },
            { wait: 150, run: () => Camera.refresh() },
            { wait: 400, run: () => check("camera events: back once installed", Camera.state, "off") }
        ];
    }

    readonly property string weatherDir: Quickshell.env("WEATHER_TEST_DIR") ?? ""
    property int weatherCallCount: 0

    FileView {
        id: weatherCalls

        path: root.weatherDir + "/calls"
        watchChanges: true
        printErrors: false

        onFileChanged: weatherCalls.reload()
        onLoaded: root.weatherCallCount = weatherCalls.text().split("\n").filter(l => l === "run").length
        onLoadFailed: root.weatherCallCount = 0
    }

    // The place panel's asks of weather.sh, a line each.
    property var weatherAsks: []

    FileView {
        id: weatherAskLog

        path: root.weatherDir + "/asks"
        watchChanges: true
        printErrors: false

        onFileChanged: weatherAskLog.reload()
        onLoaded: root.weatherAsks = weatherAskLog.text().split("\n").filter(l => l !== "")
        onLoadFailed: root.weatherAsks = []
    }

    // A link or the internet coming up during a fetch (Weather.kick) is not
    // dropped: it fetches again at once if that fetch failed, and not at all
    // if it succeeded. The stand-in takes 0.4 s; the first fetch starts as
    // the service does.
    function weatherSteps() {
        return [
            { wait: 0, run: () => check("weather: nothing before the first fetch", Weather.ready, false) },
            { wait: 150, run: () => {
                check("weather: a fetch at start", Weather.fetching, true);
                Weather.kick();
                check("weather: a kick during it is kept", Weather.kickQueued, true);
            } },
            { wait: 1300, run: () => {
                check("weather: a failed fetch is followed at once", root.weatherCallCount, 2);
                check("weather: the kick is spent", Weather.kickQueued, false);
                Quickshell.execDetached(["sh", "-c", `echo true > "$1/live"`, "sh", root.weatherDir]);
            } },
            { wait: 150, run: () => {
                Weather.kick();
                Weather.kick();
            } },
            { wait: 1300, run: () => {
                check("weather: after a live fetch the kick fetches nothing more", root.weatherCallCount, 3);
                check("weather: live resets the failures", Weather.failures, 0);
                check("weather: the reading is shown", Weather.ready, true);
            } },
            // The place panel's search: one letter asks nothing; a name
            // typed while a search runs is asked after it, and the answer to
            // the older name is dropped; a pick is kept by weather.sh and
            // fetched at once; Seoul comes back through it too.
            { wait: 0, run: () => {
                Weather.find("B");
                check("weather: one letter asks nothing", Weather.searching, false);
                check("weather: and finds nothing", Weather.places.length, 0);
                Weather.find("Bus");
            } },
            { wait: 100, run: () => {
                check("weather: two letters ask", Weather.searching, true);
                Weather.find(" Busan ");
                check("weather: a name typed meanwhile waits for that ask", Weather.searchAgain, true);
            } },
            { wait: 1000, run: () => {
                check("weather: the answer is the last name's", Weather.answered, "Busan");
                check("weather: the older name's places are dropped", Weather.places.map(p => p.name).join(), "Busan");
                check("weather: both names were asked, trimmed", root.weatherAsks.join("|"), "search Bus|search Busan");
                Weather.choose(Weather.places[0]);
            } },
            { wait: 1300, run: () => {
                check("weather: the pick goes to weather.sh", root.weatherAsks[root.weatherAsks.length - 1], "set Busan 35.1 129 Asia/Seoul");
                check("weather: and its weather is fetched at once", root.weatherCallCount, 4);
                Weather.forget();
            } },
            { wait: 500, run: () => {
                check("weather: Seoul again through weather.sh", root.weatherAsks[root.weatherAsks.length - 1], "reset");
                check("weather: and fetched again", root.weatherCallCount, 5);
            } }
        ];
    }

    // Playback paused and resumed four times, each resume before the stopped
    // cava has exited: no failure is counted, and the meter runs at the end.
    function cavaSteps() {
        const flips = [{ wait: 100, run: () => { Cava.active = true; } }];
        for (let i = 0; i < 4; i++) {
            flips.push({ wait: 500, run: () => { Cava.active = false; } });
            flips.push({ wait: 100, run: () => { Cava.active = true; } });
        }
        return flips.concat([{ wait: 1500, run: () => {
            check("cava: a pause and a quick resume are no failure", Cava.quickExits, 0);
            check("cava: the meter runs after them", Cava.levels.length, 3);
            Cava.active = false;
        } }]);
    }

    // Steps run one after another, each after its wait; DONE follows the last.
    property var steps: []
    property int step: 0

    function runSteps() {
        if (root.step >= root.steps.length) {
            console.log(`[test] DONE passed=${root.passed} failed=${root.failed}`);
            Quickshell.execDetached(["kill", "-TERM", String(Quickshell.processId)]);
            return;
        }
        stepTimer.interval = root.steps[root.step].wait;
        stepTimer.start();
    }

    Timer {
        id: stepTimer

        onTriggered: {
            const current = root.steps[root.step];
            root.step += 1;
            try {
                current.run();
            } catch (e) {
                root.failed += 1;
                console.log(`[test] FAIL step ${root.step}: threw ${e}`);
            }
            root.runSteps();
        }
    }

    function testBadge() {
        const ids = Badge.marks.map(m => m.id);
        check("badge: ids are unique", ids.filter((id, i) => ids.indexOf(id) !== i), []);
        check("badge: every mark is a Font Logos code point",
              Badge.marks.filter(m => m.cp < 0xF300 || m.cp > 0xF3FF).map(m => m.id), []);
        check("badge: aliases name marks", Object.values(Badge.aliases).filter(id => !Badge.byId(id)), []);
        check("badge: an id of its own", Badge.markFor("arch", []).id, "arch");
        check("badge: an alias", Badge.markFor("opensuse-tumbleweed", []).id, "tumbleweed");
        check("badge: rhel", Badge.markFor("rhel", ["fedora"]).id, "redhat");
        check("badge: a derivative by ID_LIKE", Badge.markFor("someremix", ["ubuntu", "debian"]).id, "ubuntu");
        check("badge: nothing known is Tux", Badge.markFor("plan9", []).id, "tux");
        check("badge: fc-query's charset", Badge.parseCharset("d 20-7e f000-f385\n"),
              [[13, 13], [32, 126], [61440, 62341]]);
        const saved = Badge.coverage;
        Badge.coverage = Badge.parseCharset("20-7e f000-f37f");
        check("badge: a mark the font lacks is not offered", Badge.offered.some(m => m.id === "cachyos"), false);
        check("badge: one it has is", Badge.offered.some(m => m.id === "void"), true);
        check("badge: a missing own mark falls to ID_LIKE", Badge.markFor("cachyos", ["arch"]).id, "arch");
        Badge.coverage = saved;
        Badge.choose("void");
        check("badge: a choice", Badge.current.id, "void");
        Badge.choose("no-such-mark");
        check("badge: an unknown choice is automatic", Badge.choice, "auto");
        check("badge: automatic is the system's", Badge.current.id, Badge.autoMark.id);
    }

    function testApps() {
        const terminal = [Paths.hyprScripts + "/terminal.sh", "-e"];
        check("apps: an entry's command", Apps.argvOf({ command: ["kakaotalk"], runInTerminal: false }), ["kakaotalk"]);
        check("apps: in a terminal when it asks for one", Apps.argvOf({ command: ["htop"], runInTerminal: true }),
              terminal.concat(["htop"]));
        check("apps: else its Exec line, field codes out", Apps.argvOf({ command: [], execString: "app %U --new" }),
              ["sh", "-c", "app  --new"]);
        check("apps: and nothing with neither", Apps.argvOf({ command: [], execString: " %f " }), []);
    }

    function testTray() {
        check("tray: mnemonics", ["_Exit", "Save__as", "a_b__c", "plain"].map(t => Tray.plainLabel(t)),
              ["Exit", "Save_as", "ab_c", "plain"]);
        let clicked = "";
        const entry = (text, extra) => Object.assign({ text: text, enabled: true, isSeparator: false, hasChildren: false,
                                                       checkState: Qt.Unchecked, triggered: () => { clicked = text; } },
                                                     extra ?? {});
        const sep = { isSeparator: true };
        const menu = Tray.menuEntries([sep, entry("_Open"), sep, sep, entry("Languages", { hasChildren: true }),
                                       entry("Signed in", { enabled: false }), entry("_Mute", { checkState: Qt.Checked }),
                                       sep, entry("_Exit"), sep]);
        check("tray: an item's menu, its top level, separators collapsed", menu.map(e => e.separator ? "-" : e.label),
              ["Open", "-", "Mute", "-", "Exit"]);
        check("tray: a checked entry", menu[2].checked, true);
        menu[4].action();
        check("tray: an entry triggers its own", clicked, "_Exit");
        check("tray: applications' items only", [Category.ApplicationStatus, Category.Communications, Category.SystemServices,
                                                Category.Hardware].map(c => Tray.isApplication({ category: c })),
              [true, true, false, false]);
        check("tray: Quit for a hider", Tray.processEntries({ name: "Hider", pid: 1, stuck: false }).map(e => e.label),
              ["Quit Hider"]);
        check("tray: Force quit once Quit has failed", Tray.processEntries({ name: "Hider", pid: 1, stuck: true }).map(e => e.label),
              ["Quit Hider", "Force quit Hider"]);
        const hider = { name: "Hider", pid: 1, entry: "hider", quitting: false, stuck: false };
        check("tray: Open first for a hider with a desktop entry", Tray.processEntries(hider).map(e => e.label),
              ["Open Hider", "Quit Hider"]);
        check("tray: no Open while it quits",
              Tray.processEntries(Object.assign({}, hider, { quitting: true })).map(e => e.label), ["Quit Hider"]);
        check("tray: nor once it is stuck, Force quit after Quit",
              Tray.processEntries(Object.assign({}, hider, { quitting: true, stuck: true })).map(e => e.label),
              ["Quit Hider", "Force quit Hider"]);
        check("tray: a click opens only a hider with an entry that is not quitting",
              [hider, Object.assign({}, hider, { entry: "" }), Object.assign({}, hider, { quitting: true })].map(p => Tray.canOpen(p)),
              [true, false, false]);
        check("tray: an entry id with no desktop entry behind it opens nothing",
              Tray.looks({ process: "qs-tray-hider", entry: "qs-no-such-entry" }).entry, "");
        check("tray: the suite's own hider list", Tray.hiders.map(h => h.process), ["qs-tray-hider"]);
    }

    readonly property string trayDir: Quickshell.env("TRAY_TEST_DIR") ?? ""

    // The stand-ins as the kernel sees them, read by trayLook() and kept in
    // trayProcs for the next step: a FileView moved from file to file gave
    // the previous file's text back for a file that was gone.
    property var trayProcs: ({})

    Process {
        id: trayProbe

        command: ["sh", "-c", 'for f in "$1"/*.pid; do [ -f "$f" ] || continue; t=${f##*/}; p=$(cat "$f"); '
                  + 'n=$(cat "/proc/$p/comm" 2>/dev/null); s=$(cut -d" " -f3 "/proc/$p/stat" 2>/dev/null); '
                  + 'echo "${t%.pid} $p ${n:--} ${s:--}"; done', "sh", root.trayDir]

        stdout: StdioCollector {
            onStreamFinished: {
                const procs = {};
                for (const line of this.text.split("\n")) {
                    const [tag, pid, name, state] = line.trim().split(" ");
                    if (tag)
                        procs[tag] = { pid: Number(pid), name: name, running: name !== "-" && state !== "Z" };
                }
                root.trayProcs = procs;
            }
        }
    }

    function trayLook() {
        trayProbe.running = true;
    }

    function trayPid(tag): int {
        return root.trayProcs[tag]?.pid ?? 0;
    }

    function trayRuns(tag): bool {
        return root.trayProcs[tag]?.running ?? false;
    }

    // A stand-in by its binary's name (qml.sh's copies of sleep), its pid in
    // TRAY_TEST_DIR/TAG.pid; one ignoring TERM as a hung application would.
    function trayStart(tag, binary, ignoreTerm) {
        Quickshell.execDetached(["sh", "-c", `${ignoreTerm ? "trap '' TERM; " : ""}"$1" 20 & echo $! > "$2"`,
                                 "sh", binary, `${root.trayDir}/${tag}.pid`]);
    }

    // Found by name, quit by TERM; one that ignores TERM is offered Force
    // quit after the grace; a pid that has changed hands is not signalled.
    function traySteps() {
        return [
            { wait: 0, run: () => {
                check("tray: no hider at the start", Tray.running.length, 0);
                root.trayStart("hider", "qs-tray-hider", false);
            } },
            { wait: 300, run: () => {
                Tray.scan();
                root.trayLook();
            } },
            { wait: 500, run: () => {
                check("tray: a hider is found by its name", Tray.running.map(p => [p.name, p.pid]),
                      [["Hider", root.trayPid("hider")]]);
                check("tray: with the icon it was given", Tray.running[0]?.icon, "file:///nonexistent/hider.png");
                check("tray: and no desktop entry, so no Open", Tray.processEntries(Tray.running[0]).map(e => e.label),
                      ["Quit Hider"]);
                Tray.quit(root.trayPid("hider"), false);
            } },
            { wait: 1000, run: () => root.trayLook() },
            { wait: 300, run: () => {
                check("tray: Quit ends it", root.trayRuns("hider"), false);
                check("tray: and its icon goes", Tray.running.length, 0);
                root.trayStart("stubborn", "qs-tray-hider", true);
            } },
            { wait: 300, run: () => {
                Tray.scan();
                root.trayLook();
            } },
            { wait: 500, run: () => {
                check("tray: one that ignores TERM", Tray.running.map(p => p.pid), [root.trayPid("stubborn")]);
                Tray.quit(root.trayPid("stubborn"), false);
            } },
            { wait: 1000, run: () => check("tray: is quitting, not stuck, within the grace",
                                           Tray.running.map(p => [p.quitting, p.stuck]), [[true, false]]) },
            { wait: Theme.trayQuitGraceMs, run: () => {
                check("tray: is stuck after it", Tray.running.map(p => p.stuck), [true]);
                check("tray: and is offered Force quit", Tray.processEntries(Tray.running[0]).length, 2);
                Tray.quit(root.trayPid("stubborn"), true);
            } },
            { wait: 1000, run: () => root.trayLook() },
            { wait: 300, run: () => {
                check("tray: Force quit ends it", [root.trayRuns("stubborn"), Tray.running.length], [false, 0]);
                root.trayStart("other", "qs-tray-other", false);
            } },
            { wait: 300, run: () => root.trayLook() },
            { wait: 300, run: () => {
                const pid = root.trayPid("other");
                Tray.running = [{ process: "qs-tray-hider", name: "Hider", icon: "", pid: pid, quitting: false, stuck: false }];
                Tray.quit(pid, false);
            } },
            { wait: 800, run: () => root.trayLook() },
            { wait: 300, run: () => {
                check("tray: Quit leaves a pid that changed hands alone", root.trayRuns("other"), true);
                check("tray: and drops its icon", Tray.running.length, 0);
                Quickshell.execDetached(["kill", String(root.trayPid("other"))]);
            } }
        ];
    }

    // Hyprland's screencastv2 data, as ScreenShare takes it.
    function testScreenShare() {
        ScreenShare.take("1,monitor,HEADLESS-1");
        check("share: not before it has lasted", ScreenShare.active, false);
        ScreenShare.take("0,monitor,HEADLESS-1");
        check("share: a screenshot's copy leaves nothing", Object.keys(ScreenShare.shares), []);
        ScreenShare.take("0,monitor,HEADLESS-1");
        check("share: a stop with no start is passed over", Object.keys(ScreenShare.shares), []);
        ScreenShare.take("1");
        ScreenShare.take("1,monitor");
        check("share: data without a type and a name is passed over", Object.keys(ScreenShare.shares), []);
        ScreenShare.take("1,window,a title, with commas");
        check("share: every window under one key", Object.keys(ScreenShare.shares), ["window,"]);
        ScreenShare.take("0,window,the title it has now");
        check("share: a window share stops under another name", Object.keys(ScreenShare.shares), []);
        check("share: the clock under an hour", ScreenShare.clockText(61000), "1:01");
        check("share: the clock past an hour", ScreenShare.clockText(3723000), "1:02:03");
        check("share: the clock before its first second", ScreenShare.clockText(-5), "0:00");
    }

    // Two shares at once, which last, and who shares them, from the
    // stand-in pw-dump (tests/unit/qml.sh).
    property real shareRead: 0

    function shareSteps() {
        return [
            { wait: 10, run: () => {
                ScreenShare.take("1,monitor,HEADLESS-1");
                ScreenShare.take("1,window,a call");
            } },
            { wait: Theme.shareLastsMs + 300, run: () => {
                check("share: counted once it has lasted", ScreenShare.lasting.map(s => s.type).sort(), ["monitor", "window"]);
                check("share: a whole screen named before a window", ScreenShare.kind, "monitor");
                check("share: the clock runs from the start", ScreenShare.now - ScreenShare.since >= Theme.shareLastsMs, true);
                root.shareRead = ScreenShare.now;
            } },
            { wait: 1500, run: () => {
                // Read last when the share came to count, a little after a
                // whole second of it; the next reading is on the next one.
                check("share: the clock read again on the next second", ScreenShare.now - root.shareRead > 500, true);
                check("share: on the share's own seconds", (ScreenShare.now - ScreenShare.since) % 1000 < 300, true);
                check("share: the program at the screen's far end in PipeWire", ScreenShare.apps, [{ name: "Share Test", icon: "" }]);
                ScreenShare.take("0,monitor,HEADLESS-1");
                check("share: one of two stopped, the other goes on", ScreenShare.kind, "window");
                ScreenShare.take("0,window,a call renamed");
                check("share: over when both have stopped", ScreenShare.active, false);
                check("share: and who shared goes with it", ScreenShare.apps, []);
            } }
        ];
    }

    // The island's system events (services/Island.qml): what comes first,
    // what waits, what replaces what, and how long each stays.
    function islandSteps() {
        return [
            { wait: 10, run: () => {
                // As the bar starts: testIsland made the arbiter seconds ago.
                Island.quiet = true;
                Island.alert("power", "", "Charging", "81%", 0.81, Theme.accentGreen);
                check("island: an alert as the bar starts is the state, not news", Island.kind, "");
                Island.quiet = false;
                Island.show("volume", "", "Volume", "40", 0.4, -1, Theme.islandBlue, true);
                Island.alert("power", "", "Charging", "81%", 0.81, Theme.accentGreen);
                check("island: a readout comes at once", Island.kind, "volume");
                check("island: an alert waits while a readout is up", Island.text, "Volume");
            } },
            { wait: Theme.islandReadoutMs + 200, run: () => {
                check("island: the alert once the readout has gone", Island.text, "Charging");
                check("island: with its value and its cell", [Island.value, Island.battery, Island.level], ["81%", 0.81, -1]);
                Island.alert("bluetooth", "", "Headphones", "Connected", -1, Theme.accentAzure);
                check("island: a newer alert replaces an older one", Island.text, "Headphones");
                Island.show("brightness", "", "Brightness", "60", 0.6, -1, Theme.accentAmber, true);
                check("island: a readout comes over an alert", Island.kind, "brightness");
            } },
            { wait: Theme.islandReadoutMs + 200, run: () => {
                check("island: an alert a readout came over comes back while time is left", Island.text, "Headphones");
            } },
            { wait: Theme.islandAlertMs, run: () => {
                check("island: and goes when its time is up", Island.kind, "");
            } }
        ];
    }

    // The island's colours and what the power and Bluetooth say on it
    // (Theme, services/Island.qml, services/Media.qml), and OBS's protocol
    // as services/Obs.qml reads it, fed by hand: no OBS here.
    function testIsland() {
        check("island: a colour's companion is it times 0.40", String(Theme.islandDim(Theme.islandRed)), "#641514");
        check("island: a tinted button is it times 0.23", String(Theme.islandTint(Theme.islandRed)), "#3a0c0c");
        check("island: the clock under an hour", Theme.clockText(61000), "1:01");
        check("island: the clock past an hour", Theme.clockText(3723000), "1:02:03");

        const plugged = { charging: true, full: false, onBattery: false, percent: 64 };
        const unplugged = { charging: false, full: false, onBattery: true, percent: 64 };
        const first = Island.powerStep(null, unplugged);
        check("power: the first look is the state, not news", first.alert, null);
        const inStep = Island.powerStep(first.state, plugged);
        check("power: the cord in says charging", [inStep.alert?.text, inStep.alert?.value], ["Charging", "64%"]);
        const outStep = Island.powerStep(inStep.state, unplugged);
        check("power: the cord out says so too", [outStep.alert?.text, outStep.alert?.battery], ["Unplugged", 0.64]);
        check("power: nothing changed, nothing said", Island.powerStep(outStep.state, unplugged).alert, null);
        const full = Island.powerStep(inStep.state, { charging: false, full: true, onBattery: false, percent: 100 });
        check("power: full on the cord", full.alert?.text, "Fully charged");
        const low = Island.powerStep(outStep.state, { charging: false, full: false, onBattery: true, percent: 9 });
        check("power: low on the cell", low.alert?.text, "Low battery");

        const bt0 = Island.btStep(null, [{ address: "A", name: "Earbuds", battery: 0.75 }]);
        check("bluetooth: the first look is the state", bt0.alerts, []);
        const bt1 = Island.btStep(bt0.state, [{ address: "A", name: "Earbuds", battery: 0.75 },
                                              { address: "B", name: "Mouse", battery: -1 }]);
        check("bluetooth: a device in, with its battery or without",
              bt1.alerts.map(a => [a.text, a.value]), [["Mouse", "Connected"]]);
        const bt2 = Island.btStep(bt1.state, [{ address: "B", name: "Mouse", battery: -1 }]);
        check("bluetooth: a device gone is said too", bt2.alerts.map(a => [a.text, a.value]), [["Earbuds", "Disconnected"]]);

        check("meter: an island colour stays itself", String(Media.vivid([Theme.islandBlue])), String(Theme.islandBlue));
        check("meter: a grey cover gives white", String(Media.vivid([Qt.rgba(0.5, 0.5, 0.5, 1)])), String(Theme.islandText));
        const island = Theme.islandColor;
        check("meter: an all-black cover gives the black island's complement",
              String(Media.vivid([Qt.rgba(0, 0, 0, 1), Qt.rgba(0, 0, 0, 1)])),
              String(Qt.rgba(1 - island.r, 1 - island.g, 1 - island.b, 1)));
        check("meter: and only then: a red cover keeps its hue", Media.lch(Media.vivid([Qt.rgba(0.8, 0.1, 0.1, 1)])).h < 40, true);
        const dull = Media.lch(Media.vivid([Qt.rgba(0.5, 0.25, 0.25, 1)]));
        check("meter: a dull cover is made as strong as the island's colours", dull.c > 0.2, true);

        Obs.receive("not json");
        Obs.receive(JSON.stringify({ op: 2, d: { negotiatedRpcVersion: 1 } }));
        check("obs: told who this is", Obs.identified, true);
        Obs.receive(JSON.stringify({ op: 7, d: { requestType: "GetRecordStatus", requestId: "record",
            requestStatus: { result: true, code: 100 },
            responseData: { outputActive: true, outputPaused: false, outputDuration: 61000 } } }));
        check("obs: recording, and for how long", [Obs.active, Obs.recording, Obs.recordMs], [true, true, 61000]);
        Obs.receive(JSON.stringify({ op: 5, d: { eventType: "RecordStateChanged",
            eventData: { outputActive: true, outputState: "OBS_WEBSOCKET_OUTPUT_PAUSED" } } }));
        check("obs: paused at once", Obs.paused, true);
        Obs.receive(JSON.stringify({ op: 5, d: { eventType: "RecordStateChanged",
            eventData: { outputActive: false, outputState: "OBS_WEBSOCKET_OUTPUT_STOPPED" } } }));
        check("obs: stopped", [Obs.recording, Obs.paused, Obs.active], [false, false, false]);
        Obs.receive(JSON.stringify({ op: 7, d: { requestType: "GetStreamStatus", requestId: "stream",
            requestStatus: { result: true, code: 100 },
            responseData: { outputActive: true, outputDuration: 5000 } } }));
        check("obs: live alone", [Obs.active, Obs.streaming], [true, true]);
        Obs.receive(JSON.stringify({ op: 7, d: { requestType: "GetStreamStatus", requestId: "stream",
            requestStatus: { result: false, code: 600 }, responseData: { outputActive: false } } }));
        check("obs: a failed request changes nothing", Obs.streaming, true);
        Obs.lost();
        check("obs: the connection gone, nothing shows", [Obs.identified, Obs.active], [false, false]);

        check("event: unbounded, as wide as it holds", freeEvent.natural > tightEvent.room, true);
        check("event: held to its room", tightEvent.natural, tightEvent.room);
        check("event: the words give way, not the level or the value", tightEvent.others, freeEvent.others);
    }

    // One readout twice: free, and given less room than it holds.
    IslandEvent {
        id: freeEvent

        visible: false
        glyph: Theme.iconVolume
        text: "Brightness"
        value: "75%"
        level: 0.75
    }

    IslandEvent {
        id: tightEvent

        visible: false
        room: freeEvent.natural - Theme.px(30)
        glyph: Theme.iconVolume
        text: "Brightness"
        value: "75%"
        level: 0.75
    }

    function testBrightness() {
        check("internal: eDP", Brightness.isInternal("eDP-1"), true);
        check("internal: HDMI", Brightness.isInternal("HDMI-A-1"), false);
        check("internal: a prefix only", Brightness.isInternal("eDPX-1"), false);
    }

    // After the modules are complete, so every function they own is there.
    Timer {
        running: true
        interval: 50

        onTriggered: {
            const suites = [root.testTheme, root.testNotifications, root.testScreensaver, root.testKeyFeed,
                            root.testBrightness, root.testCamera, root.testBadge, root.testApps, root.testTray,
                            root.testScreenShare, root.testIsland];
            if (modules.item)
                suites.push(() => modules.item.testLauncher(root.check), () => modules.item.testDisplays(root.check));
            else
                console.log("[test] SKIP Launcher and Displays: no Wayland display");
            for (const suite of suites) {
                try {
                    suite();
                } catch (e) {
                    root.failed += 1;
                    console.log(`[test] FAIL ${suite.name}: threw ${e}`);
                }
            }
            root.steps = root.keyLockSteps()
                .concat(root.keyDir !== "" ? root.keyFeedSteps() : [])
                .concat(root.imeDir !== "" ? root.imeSteps() : [])
                .concat(root.capsFile !== "" ? root.capsSteps() : [])
                .concat(root.cavaSteps())
                .concat(root.shareSteps())
                .concat(root.islandSteps())
                .concat(root.camDir !== "" ? root.cameraSteps() : [])
                .concat(root.weatherDir !== "" ? root.weatherSteps() : [])
                .concat(root.trayDir !== "" ? root.traySteps() : []);
            if (root.camDir === "")
                console.log("[test] SKIP camera events: no CAMERA_TEST_DIR");
            if (root.keyDir === "")
                console.log("[test] SKIP key reader: no KEYFEED_TEST_DIR");
            if (root.imeDir === "")
                console.log("[test] SKIP input method: no IME_TEST_DIR");
            if (root.weatherDir === "")
                console.log("[test] SKIP weather: no WEATHER_TEST_DIR");
            if (root.trayDir === "")
                console.log("[test] SKIP tray hiders: no TRAY_TEST_DIR");
            root.runSteps();
        }
    }
}
