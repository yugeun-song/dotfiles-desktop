import QtQuick
import Quickshell
import "modules"
import qs.services

// The suites for modules that own layer windows; loaded by shell.qml only
// when a Wayland display is there. check() is shell.qml's.
Scope {
    id: root

    Launcher {
        id: launcher
    }

    Displays {
        id: displays
    }

    function testLauncher(check) {
        const code = { name: "Visual Studio Code", genericName: "Text Editor", keywords: ["vscode", "editor"],
                       startupClass: "code", comment: "Code editing. Redefined.", execString: "/usr/bin/code %F" };
        check("score: name prefix", launcher.score(code, "visual"), 0);
        check("score: initials", launcher.score(code, "vsc"), 1);
        check("score: inside the name", launcher.score(code, "studio"), 2);
        check("score: generic name", launcher.score(code, "text"), 3);
        check("score: keyword", launcher.score(code, "vscode"), 4);
        check("score: comment, three letters or more", launcher.score(code, "redefined"), 6);
        check("score: one letter only matches the name", launcher.score(code, "x"), -1);
        check("score: subsequence", launcher.score(code, "vsde"), 8);
        check("score: nothing", launcher.score(code, "zzz"), -1);
        check("lower: keyword list", launcher.lower(["A", "b"]), "a b");
        check("lower: undefined", launcher.lower(undefined), "");
    }

    // The two outputs of the machine this was written on, as hyprctl lists
    // them, then edits as the panel makes them.
    function testDisplays(check) {
        check("mode: parse", displays.parseMode("2560x1440@144.00101Hz"), { w: 2560, h: 1440, r: 144.00101 });
        check("mode: key", displays.modeKey({ w: 2560, h: 1440, r: 144.00101 }), "2560x1440@144.00");
        check("mode: label", displays.modeLabel({ w: 1920, h: 1080, r: 59.94 }), "1920 x 1080  59.94 Hz");
        check("mode: round label", displays.modeLabel({ w: 2560, h: 1440, r: 60.0 }), "2560 x 1440  60 Hz");

        const monitors = [
            { id: 1, name: "HDMI-A-1", description: "Philips Consumer Electronics Company 27M2N5500 UK02519025698",
              width: 2560, height: 1440, refreshRate: 144.001, scale: 1, x: 0, y: 0, transform: 0, disabled: false,
              mirrorOf: "none", availableModes: ["2560x1440@144.00Hz", "1920x1080@60.00Hz"] },
            { id: 0, name: "eDP-1", description: "Samsung Display Corp. 0x419D", width: 2880, height: 1800,
              refreshRate: 120, scale: 1.5, x: 2560, y: 0, transform: 0, disabled: false, mirrorOf: "none",
              availableModes: ["2880x1800@120.00Hz"] },
            { id: 2, name: "FALLBACK", description: "", width: 1920, height: 1080, refreshRate: 60, scale: 1,
              x: 0, y: 0, transform: 0, disabled: false, mirrorOf: "none", availableModes: [] }
        ];
        displays.monitorsFresh = false;
        displays.overridesFresh = false;
        displays.resetPendingOnLoad = true;
        displays.parseMonitors(JSON.stringify(monitors));
        check("outputs: sorted by place, compositor's own left out", displays.outputs.map(o => o.name), ["HDMI-A-1", "eDP-1"]);
        check("outputs: internal", displays.outputs.map(o => o.internal), [false, true]);

        displays.parseOverrides("Samsung Display Corp. 0x419D\tenabled\ttrue\nname:HDMI-A-1\tscale\t1.25\n"
                                + "Some Absent Monitor\tmode\t1920x1080@60.00\n*\tworkspaces\tblocks\n");
        // name: lines are read first, so their outputs come first.
        check("overrides: current map", displays.currentMap(),
              { "HDMI-A-1": { scale: "1.25" }, "eDP-1": { enabled: "true" } });
        check("overrides: an absent monitor's line is kept", displays.keptLines,
              [["Some Absent Monitor", "mode", "1920x1080@60.00"]]);
        check("overrides: pending starts as the file", displays.pending, displays.currentMap());
        check("overrides: unchanged is not dirty", displays.dirty, false);
        // The panel's enabled=true is the default for an external only.
        check("tsv: written back the same", displays.pendingTsv,
              "Philips Consumer Electronics Company 27M2N5500 UK02519025698\tscale\t1.25\n"
              + "Samsung Display Corp. 0x419D\tenabled\ttrue\n"
              + "*\tworkspaces\tblocks\n"
              + "Some Absent Monitor\tmode\t1920x1080@60.00\n");
        check("refusal: everything off", displays.refusal({ "eDP-1": { enabled: "false" }, "HDMI-A-1": { enabled: "false" } }),
              "at least one display must stay on");

        // Opened with the external switched off: its line is only kept.
        const lines = "Samsung Display Corp. 0x419D\tenabled\ttrue\nname:HDMI-A-1\tscale\t1.25\n";
        // As show() does: both lists read afresh before the edits reset.
        displays.monitorsFresh = false;
        displays.overridesFresh = false;
        displays.resetPendingOnLoad = true;
        displays.parseMonitors(JSON.stringify([monitors[1]]));
        displays.parseOverrides(lines);
        check("hotplug: an absent display is not pending", displays.pending["HDMI-A-1"], undefined);
        displays.selected = 0;
        // Switched on while the panel is open: it brings its line along, and
        // the selection stays on the panel although its index moves.
        displays.parseMonitors(JSON.stringify(monitors));
        check("hotplug: a display that appears keeps its settings", displays.pending["HDMI-A-1"], { scale: "1.25" });
        check("hotplug: nothing to apply", displays.dirty, false);
        check("hotplug: the selection follows its output", displays.current?.name, "eDP-1");
        displays.parseMonitors(JSON.stringify([monitors[1]]));
        check("hotplug: and again when one goes", displays.current?.name, "eDP-1");
    }

}
