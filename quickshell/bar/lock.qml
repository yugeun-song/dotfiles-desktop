import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.services
import qs.modules
import "modules/lockout.js" as Lockout

// The lock screen, rebuilt in Quickshell (the user, 2026-11-05) so that a
// wrong password shakes the typed dots and the island, and a lockout counts
// down. A process of its own, apart from the bar: hypr/scripts/lock.sh runs
// it as `qs -p .../lock.qml` while the session locks, and it ends with the
// unlock, so nothing of it runs or stays otherwise and the bar going down
// leaves it standing. It draws hyprlock.conf's design on every screen with
// the sizes and colours lock-fit.sh and lock-colours.py fit to it, through
// hypr/scripts/lock-spec.py (LOCK_SPEC): one design for this and for
// hyprlock, which lock.sh falls back to when this does not lock.
//
// Safe by construction: the session lock is the compositor's
// (ext-session-lock), so a crash here leaves it locked; the surfaces are
// opaque black under everything, so nothing of the desktop shows through
// even if a picture fails; keys reach no input method (an Item takes them,
// not a text field), so a password is never composed as Hangul. PAM decides
// every unlock, pam_faillock's steps included; the countdown only says how
// long it will refuse.
//
// LOCK_GLASS=1 makes it the see-through lock instead (lock.sh --glass; the
// user, 2026-11-12): the same lock, PAM and lockouts, but its surfaces are
// clear and draw only a prompt on demand (LockGlass), with the compositor
// drawing the live desktop under them (session_lock_xray, which lock.sh
// turns on for this lock alone). The desktop showing is that lock's whole
// point; what it cannot do is take a key or a click, which stay the lock's.
//
// LOCK_READY names a file written once the compositor has the session
// locked with every screen covered, lock.sh's sign that this holds the lock.
// Test hooks: LOCK_PAM_SERVICE and LOCK_PAM_DIR (a PAM stack of the tests'
// own: never the user's password), LOCK_FAILLOCK_DIR and LOCK_PAM_STEPS (the
// tally and the steps read for the countdown), LOCK_RUN (where the bar's
// island parts are), LOCK_WEATHER (the weather command), LOCK_GLASS_REST
// (how long the see-through lock's prompt stays, in ms).
ShellRoot {
    id: root

    readonly property bool glass: Quickshell.env("LOCK_GLASS") === "1"

    // ---- what to draw -----------------------------------------------------
    FileView {
        id: specFile

        path: Quickshell.env("LOCK_SPEC") ?? ""
        blockLoading: true
        printErrors: false
    }

    readonly property var spec: {
        try {
            return JSON.parse(specFile.text());
        } catch (e) {
            return null;
        }
    }

    readonly property string runDir: Quickshell.env("LOCK_RUN") || Quickshell.env("XDG_RUNTIME_DIR") || ""

    // The bar's island event, as LockIsland.qml writes it while locked;
    // the lock alone before one comes (lock.sh removes the file first). Not
    // watched by the see-through lock, which has no notch: the bar's own
    // island shows through it.
    FileView {
        id: islandFile

        path: root.runDir === "" || root.glass ? "" : root.runDir + "/lock-island.json"
        watchChanges: true
        printErrors: false
        onFileChanged: islandFile.reload()
    }

    readonly property var island: {
        try {
            const got = JSON.parse(islandFile.text());
            if (got && typeof got.lead === "string")
                return got;
        } catch (e) {}
        return { lead: Theme.iconLock, trail: "", mark: "", tone: "" };
    }

    // The bar's weather, from its cache (weather.sh --bar), as the
    // hyprlock card's script reads it; again every ten minutes. Not for the
    // see-through lock, which shows none.
    property var weather: null

    Process {
        id: weatherRead

        running: !root.glass
        command: ["sh", "-c", Quickshell.env("LOCK_WEATHER") || `exec "${Quickshell.shellDir}/scripts/weather.sh" --bar`]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const lines = this.text.trim().split("\n");
                    const d = JSON.parse(lines[lines.length - 1]);
                    root.weather = { code: Number(d.code), temp: Math.round(Number(d.temp)), day: d.day === 1 };
                } catch (e) {
                    root.weather = null;
                }
            }
        }
    }

    Timer {
        interval: 600000
        repeat: true
        running: !root.glass
        onTriggered: weatherRead.running = true
    }

    // ---- the password, one for every screen ------------------------------
    // Kept only until it is handed to PAM, then dropped.
    property string typed: ""
    property string pending: ""
    property string message: ""
    property bool checking: false
    property bool unlocking: false
    // Each failure adds one: every screen shakes at the change.
    property int shakes: 0
    property string failText: ""
    // The dots of a password handed over stay through the check and the
    // shake, so what shakes is what was typed.
    property int heldDots: 0
    readonly property int shownDots: root.typed !== "" ? Array.from(root.typed).length : root.heldDots
    property string afterText: ""
    property real lockedUntil: 0
    property real now: Date.now()
    readonly property bool lockedOut: root.lockedUntil > root.now
    readonly property bool busy: root.checking || root.unlocking || root.lockedOut

    function type(text: string): void {
        if (root.busy)
            return;
        root.failText = "";
        root.typed += text;
    }

    // By code point: a character outside the basic plane is two halves.
    function erase(): void {
        if (root.busy)
            return;
        const chars = Array.from(root.typed);
        chars.pop();
        root.typed = chars.join("");
    }

    function clear(): void {
        if (!root.busy)
            root.typed = "";
    }

    function submit(): void {
        if (root.busy || root.typed === "")
            return;
        root.pending = root.typed;
        root.heldDots = Array.from(root.typed).length;
        root.typed = "";
        root.message = "";
        root.failText = "";
        root.checking = true;
        if (!pam.start()) {
            root.pending = "";
            root.checking = false;
            root.fail("Could not ask for the password");
        }
    }

    // A key on either lock (LockScreen, LockGlass): Enter hands the password
    // over, Backspace takes a character back, Ctrl+Backspace or Escape all of
    // them, anything printable is typed. Caps Lock is read for the field's
    // mark at its press and its release.
    function key(event: var): void {
        if (event.key === Qt.Key_CapsLock)
            root.readCaps(true);
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.submit();
        else if (event.key === Qt.Key_Backspace && (event.modifiers & Qt.ControlModifier))
            root.clear();
        else if (event.key === Qt.Key_Backspace)
            root.erase();
        else if (event.key === Qt.Key_Escape)
            root.clear();
        else if (event.text !== "" && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127)
            root.type(event.text);
    }

    function keyReleased(event: var): void {
        if (event.key === Qt.Key_CapsLock)
            root.readCaps(true);
    }

    // ---- the see-through lock's prompt ----------------------------------------
    // LockGlass shows its prompt while this is set: from any key, motion or
    // click until restMs after the last, and for startMs as the lock takes
    // hold, the one sign that it did. At rest the prompt goes and takes what
    // was typed with it: a password half typed and left is nobody's to finish.
    property bool awake: false
    readonly property int restMs: Number(Quickshell.env("LOCK_GLASS_REST")) || 8000
    readonly property int startMs: 2500

    function wake(): void {
        root.awake = true;
        rest.interval = root.restMs;
        rest.restart();
    }

    Timer {
        id: rest

        onTriggered: {
            // Not while PAM checks or the unlock comes.
            if (root.checking || root.unlocking) {
                rest.restart();
                return;
            }
            root.typed = "";
            root.awake = false;
        }
    }

    // The shake first, the words after it.
    function fail(text: string): void {
        root.shakes += 1;
        root.afterText = text;
        afterShake.restart();
        root.readLockout();
    }

    Timer {
        id: afterShake

        interval: 380
        onTriggered: {
            root.heldDots = 0;
            // Typing again already: the new dots, not the words over them.
            root.failText = root.typed === "" ? root.afterText : "";
            failShown.restart();
        }
    }

    PamContext {
        id: pam

        config: Quickshell.env("LOCK_PAM_SERVICE") || "login"
        configDirectory: Quickshell.env("LOCK_PAM_DIR") || "/etc/pam.d"

        // The stack asks for the password once; anything it asks after
        // that gets an empty answer and fails as it should.
        onResponseRequiredChanged: {
            if (!pam.responseRequired)
                return;
            pam.respond(root.pending);
            root.pending = "";
        }
        onPamMessage: {
            if (!pam.responseRequired && pam.message !== "")
                root.message = pam.message;
        }
        onCompleted: result => {
            root.pending = "";
            root.checking = false;
            if (result === PamResult.Success) {
                root.unlock();
                return;
            }
            // onError has said so: a broken stack is not a wrong password.
            if (result === PamResult.Error)
                return;
            // pam_faillock's refusal names the lock; a plain failure says
            // nothing worth showing.
            root.fail(/lock/i.test(root.message) ? root.message : "Wrong password");
        }
        onError: error => {
            root.pending = "";
            root.checking = false;
            root.fail("Could not check the password");
        }
    }

    // A failure's words for two seconds, as hyprlock's fail_timeout.
    Timer {
        id: failShown

        interval: 2000
        onTriggered: {
            if (!root.lockedOut)
                root.failText = "";
        }
    }

    // ---- Caps Lock --------------------------------------------------------
    // Lit or not, for the field's mark (LockField; the user, 2026-11-11): any
    // keyboard's Caps Lock LED, which Hyprland lights on every keyboard alike
    // and the bar reads too (scripts/inputstate.py). Read once the lock holds
    // and at each press and release of the key, never on a timer: while the
    // session is locked every key comes here, and Hyprland sets the LED in
    // the same pass that hands the key over (0.57.2,
    // CInputManager::onKeyboardKey), so the press already reads the new
    // state; the release reads it again. No LED to read shows no mark, never
    // a guess. LOCK_LEDS is the tests' stand-in for /sys/class/leds.
    readonly property string ledsDir: Quickshell.env("LOCK_LEDS") || "/sys/class/leds"
    property var capsLeds: []
    property bool capsLock: false

    // The LED nodes, looked for again when none of them reads: a keyboard
    // plugged in again comes back under another name.
    Process {
        id: capsFind

        command: ["sh", "-c", 'for f in "$1"/*::capslock/brightness; do [ -r "$f" ] && printf "%s\\n" "$f"; done; exit 0', "sh", root.ledsDir]

        stdout: StdioCollector {
            onStreamFinished: {
                root.capsLeds = this.text.split("\n").filter(p => p !== "");
                root.readCaps(false);
            }
        }
    }

    // One reader for every node in turn: a read blocks for the few bytes, so
    // the key's own frame already has the answer.
    FileView {
        id: capsFile

        blockAllReads: true
        printErrors: false
    }

    function readCaps(findAgain: bool): void {
        let known = false;
        let lit = false;
        for (const led of root.capsLeds) {
            if (capsFile.path === led)
                capsFile.reload();
            else
                capsFile.path = led;
            const value = capsFile.text().trim();
            if (value === "")
                continue;
            known = true;
            if (value !== "0") {
                lit = true;
                break;
            }
        }
        root.capsLock = lit;
        if (!known && findAgain && !capsFind.running)
            capsFind.running = true;
    }

    // ---- a lockout --------------------------------------------------------
    // pam_faillock's steps from the stack the lock authenticates through,
    // and the user's tally as faillock lists it: read after each failure and
    // once at the start, so a lock already in force shows at once.
    FileView {
        id: stepsFile

        path: Quickshell.env("LOCK_PAM_STEPS") || "/etc/pam.d/system-auth"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: faillockConf

        path: "/etc/security/faillock.conf"
        blockLoading: true
        printErrors: false
    }

    readonly property var steps: Lockout.steps(stepsFile.text(), faillockConf.text())

    Process {
        id: tally

        command: ["faillock"].concat(Quickshell.env("LOCK_FAILLOCK_DIR") ? ["--dir", Quickshell.env("LOCK_FAILLOCK_DIR")] : [],
                                      ["--user", Quickshell.env("USER") || ""])

        stdout: StdioCollector {
            onStreamFinished: {
                root.now = Date.now();
                root.lockedUntil = Lockout.until(Lockout.failures(this.text), root.steps, root.now);
                if (root.lockedOut) {
                    root.typed = "";
                    countdown.restart();
                    // How long, and nothing else: the tests read it.
                    console.info(`[lock] locked out for ${Math.ceil((root.lockedUntil - root.now) / 1000)} s`);
                }
            }
        }
    }

    function readLockout(): void {
        if (!tally.running)
            tally.running = true;
    }

    Timer {
        id: countdown

        interval: 250
        repeat: true
        onTriggered: {
            root.now = Date.now();
            if (!root.lockedOut) {
                countdown.stop();
                root.failText = "";
            }
        }
    }

    readonly property string lockoutText: root.lockedOut
        ? (Number.isFinite(root.lockedUntil) ? `Try again in ${Lockout.clock(root.lockedUntil - root.now)}` : "Locked")
        : ""

    // ---- the power panel ----------------------------------------------------
    // The power panel's actions (LockPower), run as the bar's session menu
    // runs them (PowerMenu.qml): restart, shut down and sign out through
    // session-power.sh (its header says why not systemctl straight away),
    // sleep at once, the session being locked already. LOCK_SESSION_POWER is
    // the tests' stand-in, a program handed the action's name, so that no
    // test ever powers this machine off.
    Process {
        id: powerRun

        property string action: ""

        onExited: code => {
            if (code !== 0)
                console.warn(`[lock] ${powerRun.action} exited ${code}`);
        }
    }

    function power(action: string): void {
        const hook = Quickshell.env("LOCK_SESSION_POWER") ?? "";
        powerRun.action = action;
        powerRun.command = hook !== "" ? [hook, action]
            : action === "suspend" ? ["systemctl", "suspend"]
            : [Paths.hyprScripts + "/session-power.sh", action];
        powerRun.running = true;
    }

    // ---- locking ----------------------------------------------------------
    // Each screen as it was, captured before the lock, so the lock screen
    // comes in over the desktop (the user, 2026-10-26; LockScreen's way in),
    // and dropped once it is in. The compositor draws nothing of the
    // desktop under the lock screen (lock.sh keeps session_lock_xray off for
    // it), so a failed capture leaves black, never the live desktop. The
    // see-through lock has no way in to draw, the desktop staying as it is.
    property var captures: ({})
    property bool capturing: !root.glass
    readonly property bool ready: root.spec !== null && !root.capturing

    function captured(name: string, result: var): void {
        const next = Object.assign({}, root.captures);
        next[name] = result;
        root.captures = next;
        if (Object.keys(next).length >= Quickshell.screens.length)
            root.capturing = false;
    }

    // Never waits long: past this the lock goes on without the desktop's
    // picture.
    Timer {
        running: root.capturing
        interval: 400
        onTriggered: root.capturing = false
    }

    Variants {
        model: root.capturing ? Quickshell.screens : []

        PanelWindow {
            id: shotWindow

            required property ShellScreen modelData

            screen: shotWindow.modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:lock-capture"
            mask: Region {}

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            ScreencopyView {
                id: shot

                anchors.fill: parent
                captureSource: shotWindow.modelData
                live: false
                paintCursor: false
                onHasContentChanged: {
                    if (shot.hasContent)
                        shot.grabToImage(result => root.captured(shotWindow.modelData.name, result));
                }
            }
        }
    }

    // The way in's length (LockScreen): a little longer than hyprlock's
    // fadeIn (3 ds), for the frost and the zoom it carries.
    readonly property int enterMs: 520

    // Collected at once: the pictures are a screen each, and the collector
    // would otherwise keep them for the whole lock.
    Timer {
        id: dropCaptures

        interval: root.enterMs + 100
        onTriggered: {
            root.captures = ({});
            gc();
        }
    }

    onReadyChanged: {
        if (root.ready) {
            dropCaptures.restart();
            root.readLockout();
        }
    }

    // Without a spec there is nothing to draw: gone at once, and lock.sh
    // locks with hyprlock instead.
    Component.onCompleted: {
        // Never reload on a file changing, as an install does: a new generation
        // starts with the lock not yet wanted (capturing), and takes the old one's
        // lock only to let it go, so the session stood open without a password
        // for as long as its capture took (found 2026-11-07, e2e 30).
        Quickshell.watchFiles = false;
        if (root.spec === null) {
            console.warn("[lock] no spec in LOCK_SPEC; leaving the lock to hyprlock");
            Qt.exit(2);
        }
    }

    FileView {
        id: readyFile

        path: Quickshell.env("LOCK_READY") ?? ""
        printErrors: false
    }

    WlSessionLock {
        id: lock

        // A surface per screen: the lock screen's, opaque black under all it
        // draws (see the header), or the see-through lock's, clear, so that
        // what shows is the desktop the compositor draws under it.
        property Component screenSurface: WlSessionLockSurface {
            id: surface

            color: "black"

            LockScreen {
                anchors.fill: parent
                lockScreen: surface.screen
                lockRoot: root
            }
        }

        property Component glassSurface: WlSessionLockSurface {
            id: pane

            color: "transparent"

            LockGlass {
                anchors.fill: parent
                lockScreen: pane.screen
                lockRoot: root
            }
        }

        surface: root.glass ? lock.glassSurface : lock.screenSurface
        locked: root.ready && !root.unlocking
        onSecureChanged: {
            if (!lock.secure)
                return;
            if (readyFile.path !== "")
                readyFile.setText(`${Date.now()}\n`);
            // Keys pressed before the lock held went elsewhere.
            if (!capsFind.running)
                capsFind.running = true;
            // Nothing else on the screen changes, so the prompt says it.
            if (root.glass) {
                root.awake = true;
                rest.interval = root.startMs;
                rest.restart();
            }
        }
    }

    // ---- the unlock -------------------------------------------------------
    // The bar sweeps the lock screen off the desktop (UnlockSweep.qml), as
    // after hyprlock; this ends once the compositor has the unlock.
    function unlock(): void {
        root.unlocking = true;
        quit.restart();
    }

    Timer {
        id: quit

        interval: 150
        onTriggered: Qt.quit()
    }
}
