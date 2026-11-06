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

    PowerMenu {
        id: sessionMenu
    }

    ControlSlider {
        id: slider

        value: 0.5
    }

    // Wheel events add up to notches: one a step ran the volume to full in a swipe.
    function testSlider(check) {
        let moved = 0;
        const count = () => moved += 1;
        slider.moved.connect(count);
        for (let i = 0; i < 3; i++)
            slider.wheelBy(30);
        check("slider: a touchpad's small deltas are not a step each", moved, 0);
        slider.wheelBy(30);
        check("slider: four of them make a notch of 5%", Math.round(slider.dragValue * 100), 55);
        slider.wheelBy(0);
        check("slider: a sideways swipe moves nothing", moved, 1);
        slider.wheelBy(-240);
        check("slider: two notches down at once", Math.round(slider.dragValue * 100), 45);
        slider.moved.disconnect(count);
    }

    // Every entry offered, Lock among them: it went missing unnoticed once,
    // told as not installed by a list its probe was not on (2026-11-06).
    function testSessionMenu(check) {
        check("session dialog: every entry offered", sessionMenu.usable.map(e => e.id), sessionMenu.entries.map(e => e.id));
        check("session dialog: Lock among them", sessionMenu.usable.some(e => e.id === "lock"), true);
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

        // A drop in the picture takes the side nearest, in half sizes.
        displays.monitorsFresh = false;
        displays.overridesFresh = false;
        displays.resetPendingOnLoad = true;
        displays.parseMonitors(JSON.stringify(monitors));
        displays.parseOverrides("");
        check("drag: the panel and its external can be arranged", displays.arrangeable, true);
        const ext = { x: 100, y: 0, w: 200, h: 100 };
        check("drag: the side nearest", [
            displays.direction({ x: 310, y: 10, w: 100, h: 60 }, ext),
            displays.direction({ x: -20, y: 30, w: 100, h: 60 }, ext),
            displays.direction({ x: 150, y: 110, w: 100, h: 60 }, ext),
            displays.direction({ x: 150, y: -70, w: 100, h: 60 }, ext),
            displays.direction({ x: 0, y: 105, w: 400, h: 40 }, { x: 180, y: 0, w: 40, h: 100 })
        ], ["right", "left", "below", "above", "below"]);
        displays.dropSide({ x: -20, y: 30, w: 100, h: 60 }, ext);
        check("drag: a drop at the left sets the panel's side", displays.value("eDP-1", "side"), "left");
        check("drag: pending until Apply", displays.dirty, true);
        displays.dropSide({ x: 310, y: 10, w: 100, h: 60 }, ext);
        check("drag: back at the right is nothing to apply", displays.dirty, false);
        displays.applyPreset("mirror");
        check("drag: mirrored, nothing to arrange", displays.arrangeable, false);
        displays.dropSide({ x: -20, y: 30, w: 100, h: 60 }, ext);
        check("drag: and a drop changes nothing", displays.value("eDP-1", "side"), "auto");
        displays.applyPreset("left");
    }

}
