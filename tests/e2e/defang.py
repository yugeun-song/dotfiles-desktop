#!/usr/bin/env python3
"""Turn the copies tests/e2e/run.sh made into ones that cannot reach the machine.

Usage: defang.py WORK     (WORK holds bar/, config/hypr/ and the log apps.log)

Every action that would leave the nested session is replaced with a line in
WORK/apps.log: the session dialog's lock, sleep, sign-out, restart and power-off,
programs started from the bar, brightness and volume writes, the alarm chime.
The key reader becomes a reader of WORK/keyfifo, never of /dev/input. The
weather script prints a fixed reading instead of going to the network. Then
a probe is added to shell.qml for the suite to read the bar's state, the
screensaver's minutes become five-second units so its stages come within a
test's patience, and the Displays panel stops hiding headless outputs, which
are all the nested session has. A pattern that is not found is an error:
a defang that silently did nothing would let a test reach the machine.
"""

import pathlib
import re
import sys

WORK = pathlib.Path(sys.argv[1]).resolve()
BAR = WORK / "bar"
HYPR = WORK / "config" / "hypr"
LOG = WORK / "apps.log"


def edit(path, old, new, count=1, regex=False):
    text = path.read_text()
    if regex:
        text, n = re.subn(old, new, text, count=count, flags=re.S)
    else:
        n = text.count(old)
        text = text.replace(old, new, count)
    if n == 0:
        sys.exit(f"defang: {path.relative_to(WORK)}: pattern not found: {old[:70]!r}")
    path.write_text(text)


def logger(name):
    return f'["sh", "-c", "echo {name} >> {LOG}"]'


power = BAR / "modules/PowerMenu.qml"
edit(power, 'command: ["loginctl", "lock-session"],', f"command: {logger('lock')},")
edit(power, r'command: \["sh", "-c",\n.*?"notify-send -u critical .*?\],', f"command: {logger('suspend')},", regex=True)
if "systemctl suspend" in power.read_text() or "loginctl" in power.read_text().split("command:")[1]:
    sys.exit("defang: PowerMenu.qml still holds a real session command")

(HYPR / "scripts/session-power.sh").write_text(f'#!/bin/sh\necho "session-power $*" >> {LOG}\n')

edit(BAR / "services/Brightness.qml",
     'writeProc.command = ["ddcutil", "-b", String(bus), "setvcp", "10", String(root.pending)];',
     f"writeProc.command = {logger('ddc-set')};")
edit(BAR / "services/Brightness.qml",
     'writeProc.command = ["brightnessctl", "--class", "backlight", "-q", "s", `${root.pending}%`];',
     f"writeProc.command = {logger('backlight-set')};")
edit(BAR / "services/Volume.qml", "root.audio.volume = clamped / 100;", "console.warn('[e2e] volume write refused');")
edit(BAR / "services/Volume.qml", "root.audio.muted = !root.audio.muted;", "console.warn('[e2e] mute refused');")
edit(BAR / "services/Volume.qml", 'fallback.command = ["wpctl"', 'fallback.command = ["true", "wpctl"', count=3)
edit(BAR / "services/Alarms.qml",
     'command: ["canberra-gtk-play", "-f", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]',
     'command: ["true"]')

(BAR / "scripts/app-scope.sh").write_text(f'#!/bin/sh\necho "app $*" >> {LOG}\n')
(BAR / "scripts/weather.sh").write_text(
    "#!/bin/sh\n"
    "echo '{\"code\": 1, \"temp\": 18, \"feels\": 17, \"day\": 1, \"place\": \"Test\", "
    "\"fetched\": '\"$(date +%s)\"', \"live\": true}'\n")
(BAR / "scripts/keyfeed.py").write_text(f'''#!/usr/bin/env python3
import json, sys
print(json.dumps({{"type": "ready", "devices": 1}}), flush=True)
while True:
    with open("{WORK / 'keyfifo'}") as fh:
        for line in fh:
            line = line.strip()
            if line == "EXIT":
                sys.exit(3)
            if line.startswith("ERR "):
                print(json.dumps({{"type": "error", "reason": line[4:]}}), flush=True)
            elif line:
                parts = line.split("+")
                print(json.dumps({{"type": "key", "mods": parts[:-1], "key": parts[-1]}}), flush=True)
''')

saver = BAR / "modules/ScreensaverDpms.qml"
edit(saver, "timeout: Math.max(1, slot.minutes) * 60", "timeout: Math.max(1, slot.minutes) * 5")
edit(saver, "interval: Math.max(1, slot.minutes) * 60000", "interval: Math.max(1, slot.minutes) * 5000")

edit(BAR / "modules/Displays.qml", "if (/^(FALLBACK$|HEADLESS-)/.test(m.name))", "if (/^(FALLBACK$)/.test(m.name))")

capture = HYPR / "scripts/capture.sh"
edit(capture, '    RUN="$XDG_RUNTIME_DIR/capture"', f'    RUN="{WORK / "capture"}"')
edit(capture, 'BAR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar"', f'BAR_CONFIG="{BAR}"')

probe = '''
    // tests/e2e only: the suite reads the bar's state through this.
    IpcHandler {
        target: "e2e"

        function keys(): string {
            return JSON.stringify({ enabled: KeyFeed.enabled, locked: KeyFeed.locked,
                                    chords: KeyFeed.chords.map(c => c.key), failure: KeyFeed.failure });
        }
        function notifs(): string {
            return JSON.stringify(Notifications.history.map(e => ({ id: e.id, read: e.read, at: e.at })));
        }
        function toasts(): int {
            return e2eToasts.count;
        }
        function alarm(): string {
            return Alarms.ringing ? Alarms.ringing.label : "";
        }
        function displaysState(): string {
            return JSON.stringify({ countdown: displays.countdown, current: displays.current ? displays.current.name : "" });
        }
        function session(): bool {
            return Session.menuOpen;
        }
    }

    QtObject {
        id: e2eToasts

        property int count: 0
    }

    Connections {
        target: Notifications

        function onToast(entry) {
            e2eToasts.count += 1;
        }
    }
}
'''
shell = BAR / "shell.qml"
text = shell.read_text().rstrip()
if not text.endswith("}"):
    sys.exit("defang: shell.qml does not end with its root's brace")
shell.write_text(text[:-1] + probe)
