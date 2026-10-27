pragma Singleton

import QtQuick
import Quickshell

// Starts user programs via scripts/app-scope.sh in their own systemd scope.
// Plain execDetached keeps the child in bar.service's cgroup, which dies on
// `bar --restart`. Pill helpers must NOT come through here: that cgroup is what
// stops them if quickshell is killed.
Singleton {
    id: root

    readonly property string wrapper: Quickshell.shellPath("scripts/app-scope.sh")

    // Run via bash so a mode-644 checkout still works; "--" keeps argv intact.
    function open(argv) {
        if (!Array.isArray(argv) || argv.length === 0) {
            console.warn("[apps] nothing to run");
            return;
        }
        Quickshell.execDetached(["bash", root.wrapper, "--"].concat(argv));
    }

    // entry.command strips field codes but ignores Terminal=true, so the
    // terminal is added here: scripts/terminal.sh, the first one installed,
    // not kitty by name.
    function argvOf(entry) {
        const terminal = [Paths.hyprScripts + "/terminal.sh", "-e"];
        const argv = entry.command;
        if (Array.isArray(argv) && argv.length > 0)
            return entry.runInTerminal === true ? terminal.concat(argv) : argv;
        // Fallback: strip field codes, or an editor opens a literal "%U".
        const exec = (entry.execString ?? "").replace(/%[fFuUdDnNickvm]/g, "").trim();
        if (exec === "")
            return [];
        return entry.runInTerminal === true ? terminal.concat(["sh", "-c", exec]) : ["sh", "-c", exec];
    }
}
