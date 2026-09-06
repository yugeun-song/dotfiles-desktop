pragma Singleton

import QtQuick
import Quickshell

// Where the programs this shell opens for the user are started.
//
// Not execDetached directly: it double-forks, which leaves the child in
// bar.service's control group, and that unit kills its group on stop -- so
// `bar --restart` closed every window the launcher had opened.
// scripts/app-scope.sh gives it its own scope, or starts it in place.
//
// The pill helpers do not come through here and must not. The control group is
// what stops them polling on if quickshell is killed outright.
Singleton {
    id: root

    // The script sits beside this file, under the shell's own directory, which
    // is on no PATH at all. shellPath is what turns that into something
    // execDetached can exec.
    readonly property string wrapper: Quickshell.shellPath("scripts/app-scope.sh")

    // Handed to bash by name, so a checkout that arrived at mode 644 does not
    // stand between every click and anything happening. The argument list goes
    // through untouched behind a "--", so callers keep building it as they did
    // and a program whose name begins with a dash stays its own argv[0].
    function open(argv) {
        if (!Array.isArray(argv) || argv.length === 0) {
            console.warn("[apps] nothing to run");
            return;
        }
        Quickshell.execDetached(["bash", root.wrapper, "--"].concat(argv));
    }
}
