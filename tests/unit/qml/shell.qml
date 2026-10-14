import QtQuick
import Quickshell
import Quickshell.Io
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
        // As at the start, until the probe answers.
        KeyFeed.locked = true;
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
                KeyFeed.toggle();
            } },
            { wait: 700, run: () => {
                check("reader: Super+Y off tells it to stop", root.keyControl, "resume\npause\nresume\nstop\n");
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
                check("reader: a missing agent is waited for", KeyFeed.failure,
                      "waiting for a polkit agent to ask for the password");
                root.keyMode("ok");
            } },
            { wait: 2600, run: () => {
                check("reader: the retry starts it", [KeyFeed.failure, KeyFeed.chords.map(c => c.key)], ["", ["K"]]);
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
        check("camera: tooltip head", Camera.describe(reading("off", [cam("A", "off")]), "").split("\n")[0], "Cameras off");
        check("camera: nothing to say while on", Camera.describe(reading("on", [cam("A", "on")]), ""), "");
        check("camera: a leak names the node",
              Camera.describe(reading("off", [cam("A", "on")]), "").split("\n")[1], "On        A  video0");
        check("camera: a failed check is said",
              Camera.describe(reading("off", [cam("A", "off")]), "exited with 1").split("\n").pop(), "Not rechecked: exited with 1");
        const gaps = reading("off", [cam("A", "off")]);
        gaps.missing = ["the udev rule is not installed"];
        check("camera: setup gaps are pointed at", Camera.describe(gaps, "").indexOf("Setup     incomplete") !== -1, true);
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
                            root.testBrightness, root.testCamera, root.testBadge];
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
                .concat(root.cavaSteps())
                .concat(root.camDir !== "" ? root.cameraSteps() : [])
                .concat(root.weatherDir !== "" ? root.weatherSteps() : []);
            if (root.camDir === "")
                console.log("[test] SKIP camera events: no CAMERA_TEST_DIR");
            if (root.keyDir === "")
                console.log("[test] SKIP key reader: no KEYFEED_TEST_DIR");
            if (root.weatherDir === "")
                console.log("[test] SKIP weather: no WEATHER_TEST_DIR");
            root.runSteps();
        }
    }
}
