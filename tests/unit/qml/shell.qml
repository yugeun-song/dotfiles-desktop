import QtQuick
import Quickshell
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
                            root.testBrightness];
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
            console.log(`[test] DONE passed=${root.passed} failed=${root.failed}`);
            Quickshell.execDetached(["kill", "-TERM", String(Quickshell.processId)]);
        }
    }
}
