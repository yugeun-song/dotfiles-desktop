pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray

// Applications that go on running with no window, for the icons at the left
// of the bar (modules/TrayIcons.qml). Closing Zoom's or KakaoTalk's window
// leaves the application running, and with no tray on the bar it could be
// neither seen nor quit (Zoom held 1.4 GiB that way, 2026-10-18). Two kinds:
//
// - Tray items (StatusNotifierItem) of applications. Hardware and system
//   service items are left out: the right side already shows the input
//   method, the network and Bluetooth, and fcitx5's item is one of them.
// - Processes known to hide their window without registering a tray item,
//   found by name. KakaoTalk under Wine in its sandbox reaches neither an
//   XEmbed tray nor the session bus. Running its desktop entry again brings
//   the hidden window back (its launcher script sees to that), so Open is
//   that entry. SIGTERM to its process ends the whole sandbox (checked
//   2026-10-18), so Quit is that signal.
Singleton {
    id: root

    readonly property var items: (SystemTray.items?.values ?? []).filter(i => root.isApplication(i))

    function isApplication(item): bool {
        return item.category !== Category.SystemServices && item.category !== Category.Hardware;
    }

    // Programs that hide their window without a tray item, by the kernel's
    // process name (comm, at most 15 characters), with the desktop entry
    // that names them, gives their icon and opens them. BAR_TRAY_HIDERS
    // replaces the list with JSON, entries of the same shape, with an icon
    // path beside the entry or in its place: the tests' stand-ins must never
    // be confused with a real KakaoTalk.
    readonly property var hiders: {
        const override = Quickshell.env("BAR_TRAY_HIDERS");
        if (override) {
            try {
                return JSON.parse(override);
            } catch (e) {
                console.warn("[tray] BAR_TRAY_HIDERS is not JSON:", e);
            }
        }
        return [{ process: "KakaoTalk.exe", entry: "kakaotalk", name: "KakaoTalk" }];
    }

    // The hiders running now: { process, name, icon, entry, pid, quitting,
    // stuck }, entry "" when no desktop entry was found for it. Replaced,
    // never changed in place, so bindings see every change.
    property var running: []

    // An item's own menu as PopupMenu entries. Its top level only, since
    // PopupMenu has no submenus, and only what can be clicked: a disabled
    // line in an application's menu is a heading or a status.
    function menuEntries(children): var {
        const out = [];
        for (const child of children) {
            if (child.isSeparator) {
                if (out.length > 0 && !out[out.length - 1].separator)
                    out.push({ separator: true });
                continue;
            }
            const label = root.plainLabel(child.text ?? "");
            if (!child.enabled || child.hasChildren || label === "")
                continue;
            out.push({ label: label, checkable: child.buttonType !== QsMenuButtonType.None,
                       checked: child.checkState === Qt.Checked, action: () => child.triggered() });
        }
        while (out.length > 0 && out[out.length - 1].separator)
            out.pop();
        return out;
    }

    // dbusmenu marks a mnemonic with "_" and writes a literal one as "__".
    function plainLabel(text: string): string {
        return text.split("__").map(part => part.replace(/_/g, "")).join("_");
    }

    function canOpen(proc): bool {
        return !!proc?.entry && !proc.quitting;
    }

    // Open only for one with a desktop entry that is not quitting; Force
    // quit only once Quit has been given its time.
    function processEntries(proc): var {
        if (!proc)
            return [];
        const entries = [];
        if (root.canOpen(proc))
            entries.push({ label: `Open ${proc.name}`, icon: Theme.iconApps, action: () => root.open(proc.entry) });
        entries.push({ label: `Quit ${proc.name}`, icon: Theme.iconPower, action: () => root.quit(proc.pid, false) });
        if (proc.stuck)
            entries.push({ label: `Force quit ${proc.name}`, icon: Theme.iconPower, detail: "SIGKILL",
                           action: () => root.quit(proc.pid, true) });
        return entries;
    }

    function open(id: string) {
        const entry = DesktopEntries.byId(id);
        const argv = entry ? Apps.argvOf(entry) : [];
        if (argv.length === 0) {
            console.warn("[tray] nothing to run for", id);
            return;
        }
        Apps.open(argv);
    }

    // The signal goes only to a process that still has the hider's name: a
    // pid freed and taken by another program in the meantime is left alone.
    function quit(pid: int, force: bool) {
        const proc = root.running.find(p => p.pid === pid);
        if (!proc)
            return;
        Quickshell.execDetached(["sh", "-c", '[ "$(cat "/proc/$1/comm" 2>/dev/null)" = "$2" ] && kill -s "$3" "$1"',
                                 "sh", String(pid), proc.process, force ? "KILL" : "TERM"]);
        root.change(pid, { quitting: true, stuck: false, askedAt: Date.now() });
    }

    function change(pid: int, fields) {
        root.running = root.running.map(p => p.pid === pid ? Object.assign({}, p, fields) : p);
    }

    function gone(pid: int) {
        if (root.running.some(p => p.pid === pid))
            root.running = root.running.filter(p => p.pid !== pid);
    }

    function scan() {
        if (root.hiders.length > 0 && !lookup.running)
            lookup.running = true;
    }

    // A zombie is passed over: it has ended, and keeps its name only until
    // its parent reaps it.
    function take(text: string) {
        const found = [];
        for (const line of text.split("\n")) {
            const parts = line.trim().split(/\s+/);
            const pid = Number(parts[0]);
            const hider = root.hiders.find(h => h.process === parts[2]);
            if (!(pid > 0) || !hider || (parts[1] ?? "").startsWith("Z"))
                continue;
            const known = root.running.find(p => p.pid === pid);
            found.push(Object.assign(known ? Object.assign({}, known) : { process: hider.process, pid: pid, quitting: false, stuck: false },
                                     root.looks(hider)));
        }
        // Kept when nothing changed: a new list rebuilds the icons, and a
        // menu open on one would close under the pointer.
        if (JSON.stringify(found) !== JSON.stringify(root.running))
            root.running = found;
    }

    // Looked up again on every scan, in case the desktop entries were not
    // read yet the first time.
    function looks(hider): var {
        const entry = hider.entry ? DesktopEntries.byId(hider.entry) : null;
        const themed = entry?.icon ? Quickshell.iconPath(entry.icon, true) : "";
        const icon = hider.icon ? (hider.icon.startsWith("/") ? `file://${hider.icon}` : hider.icon) : themed;
        return { name: entry?.name || hider.name || hider.process, icon: icon, entry: entry ? hider.entry : "" };
    }

    Process {
        id: lookup

        command: ["ps", "-o", "pid=,stat=,comm=", "-C", root.hiders.map(h => h.process).join(",")]

        stdout: StdioCollector {
            onStreamFinished: root.take(this.text)
        }
    }

    Component.onCompleted: root.scan()

    // A hider shows a window as it starts, so window events are when to
    // look; the slow scan is for one started straight into hiding.
    Timer {
        id: settle

        interval: 1500
        onTriggered: root.scan()
    }

    Timer {
        running: root.hiders.length > 0
        repeat: true
        interval: 60000
        onTriggered: root.scan()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow")
                settle.restart();
        }
    }

    // Whether each one still runs, from its own stat (cheaper than a scan):
    // gone once the pid is free, has another name, or is a zombie, which
    // keeps its name until reaped. Briskly while one is quitting, so its
    // icon goes with it.
    Instantiator {
        id: watchers

        model: root.running

        delegate: FileView {
            id: watcher

            required property var modelData

            path: `/proc/${watcher.modelData.pid}/stat`
            printErrors: false

            onLoaded: {
                const stat = watcher.text();
                const end = stat.lastIndexOf(")");
                const name = stat.slice(stat.indexOf("(") + 1, end);
                if (name !== watcher.modelData.process || stat.charAt(end + 2) === "Z")
                    root.gone(watcher.modelData.pid);
            }
            onLoadFailed: root.gone(watcher.modelData.pid)
        }
    }

    Timer {
        running: root.running.length > 0
        repeat: true
        interval: root.running.some(p => p.quitting) ? 300 : 5000

        onTriggered: {
            for (let i = 0; i < watchers.count; i++)
                watchers.objectAt(i)?.reload();
            const late = Date.now() - Theme.trayQuitGraceMs;
            for (const p of root.running) {
                if (p.quitting && !p.stuck && p.askedAt < late)
                    root.change(p.pid, { stuck: true });
            }
        }
    }
}
