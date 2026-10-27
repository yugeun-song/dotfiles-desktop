"""Tests for quickshell/bar/scripts/polkit-tty.py, run whole with a stand-in
pkttyagent first on PATH that logs whom it is registered for and its stop:
nothing reaches polkit or asks for a password. A terminal is a pty made the
controlling one of the process started on it, in its foreground, as a
terminal emulator's shell has it; a pkexec is a python3 started under that
name, which is all the script goes by.
"""

import fcntl
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import termios
import time
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = REPO / "quickshell/bar/scripts/polkit-tty.py"

# pkttyagent: logs the process it is registered for (the pid of --process
# pid,start) and closes the notify fd, then waits as the agent does, logging
# its stop. PKTTY_NEVER keeps the fd open (never registered); PKTTY_FAIL
# ends at once, as one polkit refused does.
PKTTYAGENT = r"""#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in
        --process) pid=${2%%,*}; shift 2 ;;
        --notify-fd) fd=$2; shift 2 ;;
        *) shift ;;
    esac
done
[ -n "${PKTTY_FAIL:-}" ] && exit 127
trap 'kill $! 2>/dev/null; echo stopped >> "$STUB_DIR/agent.log"; exit 0' TERM
if [ -z "${PKTTY_NEVER:-}" ]; then
    echo "registered $pid" >> "$STUB_DIR/agent.log"
    eval "exec $fd>&-"
fi
# Started after the fd is closed: a child holding it would keep the
# registration from being seen.
sleep 30 &
wait
"""


def own_terminal():
    """In the child, before exec: stdin, a pty's slave, becomes the
    controlling terminal of the new session, whose group is then in front."""
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


class PolkitTtyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        agent = self.bin / "pkttyagent"
        agent.write_text(PKTTYAGENT)
        agent.chmod(0o755)
        self.env = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "STUB_DIR": str(self.dir),
            "POLKIT_TTY_TIMEOUT": "2",
        }
        self.procs = []
        self.masters = []

    def tearDown(self):
        # What a test left running, and only that: each process it started
        # leads a session and group of its own, which the watcher and the
        # agent stay in.
        for proc in self.procs:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass
            if proc.poll() is None:
                proc.wait()
        for master in self.masters:
            os.close(master)
        self.tmp.cleanup()

    def start(self, *command, env=None, terminal=False, foreign_terminal=False, **kw):
        """Runs the script; terminal: on a pty it owns, as at a terminal;
        foreign_terminal: with a pty for stdin that is not its terminal."""
        argv = [sys.executable, "-I", "-S", str(SCRIPT), *command]
        if terminal or foreign_terminal:
            master, slave = os.openpty()
            self.masters.append(master)
            kw["stdin"] = slave
            if terminal:
                kw["preexec_fn"] = own_terminal
                # Under a shell that leads the session and outlives the
                # command, as a terminal's does: a leader's end hangs the
                # terminal up, and everything on it with it.
                argv = ["sh", "-c", '"$@"; code=$?; sleep 0.5; exit $code', "sh", *argv]
        else:
            kw.setdefault("stdin", subprocess.DEVNULL)
        kw.setdefault("stdout", subprocess.PIPE)
        kw.setdefault("stderr", subprocess.PIPE)
        try:
            proc = subprocess.Popen(argv, env={**self.env, **(env or {})}, text=True,
                                    start_new_session=True, **kw)
        finally:
            if terminal or foreign_terminal:
                os.close(slave)
        self.procs.append(proc)
        return proc

    def run_script(self, *command, timeout=10, **kw):
        proc = self.start(*command, **kw)
        out, err = proc.communicate(timeout=timeout)
        return proc.returncode, out, err

    def read(self, name):
        try:
            return (self.dir / name).read_text().strip()
        except OSError:
            return ""

    def registered(self):
        return [line.split()[1] for line in self.read("agent.log").splitlines() if line.startswith("registered ")]

    def agent_stopped(self, timeout=3.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if "stopped" in self.read("agent.log").splitlines():
                return True
            time.sleep(0.05)
        return False

    # -- away from a terminal: the command as it is, polkit's dialog asks --

    def test_away_from_a_terminal_the_command_runs_as_it_is(self):
        proc = self.start("bash", "-c", 'echo $$ > "$STUB_DIR/pid"; exit 7')
        proc.communicate(timeout=10)
        self.assertEqual(proc.returncode, 7)
        # Exec'd, not run under a wrapper: the pid is the script's own.
        self.assertEqual(self.read("pid"), str(proc.pid))
        self.assertEqual(self.read("agent.log"), "")

    def test_the_command_s_status_is_its_own(self):
        # The command's very own: it is this process, killed here.
        self.assertEqual(self.run_script("bash", "-c", "kill -KILL $$")[0], -signal.SIGKILL)

    def test_stdout_and_stdin_are_the_command_s(self):
        proc = self.start("bash", "-c", 'read -r line; printf "{\\"got\\": \\"%s\\"}\\n" "$line"',
                          stdin=subprocess.PIPE)
        out, _ = proc.communicate("resume\n", timeout=10)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(out, '{"got": "resume"}\n')

    def test_a_terminal_nobody_reads_is_not_handed_on(self):
        # A key's command has the compositor's console, which is not the
        # session's terminal in front of anyone: stdin becomes /dev/null.
        code, out, _ = self.run_script("bash", "-c", '[ -t 0 ] && echo tty || echo notty',
                                       foreign_terminal=True)
        self.assertEqual(code, 0)
        self.assertEqual(out, "notty\n")
        self.assertEqual(self.read("agent.log"), "")

    # -- at a terminal: the agent on it, for the command's own process --

    def test_at_a_terminal_the_agent_is_registered_for_the_command_before_it_runs(self):
        code, _, _ = self.run_script(
            "bash", "-c", 'echo "$$ $(cat "$STUB_DIR/agent.log" 2>/dev/null)" > "$STUB_DIR/seen"; '
                          '[ -t 0 ] && echo tty >> "$STUB_DIR/seen"', terminal=True)
        self.assertEqual(code, 0)
        seen = self.read("seen").split()
        self.assertEqual(seen[:3], [seen[0], "registered", seen[0]])
        self.assertEqual(seen[-1], "tty", "the command lost its terminal")

    def test_the_command_has_no_child_of_ours_to_reap(self):
        code, _, _ = self.run_script(
            "bash", "-c", 'read -r kids < /proc/$$/task/$$/children; echo "$kids" > "$STUB_DIR/kids"',
            terminal=True)
        self.assertEqual(code, 0)
        self.assertTrue(self.registered(), "no agent")
        self.assertEqual(self.read("kids"), "")

    def test_the_agent_goes_once_pkexec_has_become_its_program(self):
        # pkexec asks for a moment, then runs the program, which goes on.
        proc = self.start("bash", "-c",
                          'exec -a pkexec python3 -c "import os, time; time.sleep(0.6); '
                          'os.execvp(\'sleep\', [\'sleep\', \'2\'])" & wait', terminal=True)
        self.assertTrue(self.agent_stopped(timeout=2.0), "the agent stayed")
        self.assertIsNone(proc.poll(), "the command ended with the agent")
        proc.communicate(timeout=10)
        self.assertEqual(proc.returncode, 0)

    def test_a_pkexec_that_asks_nothing_still_lets_the_agent_go(self):
        # It became its program at once, between two looks: only the
        # program is ever seen under the command, and a while of it with no
        # pkexec ends the agent.
        proc = self.start("bash", "-c", "sleep 3 & wait", terminal=True)
        self.assertTrue(self.agent_stopped(timeout=2.5), "the agent stayed")
        self.assertIsNone(proc.poll(), "the command ended with the agent")
        proc.communicate(timeout=10)
        self.assertEqual(proc.returncode, 0)

    def test_the_agent_goes_when_the_command_ends(self):
        code, _, _ = self.run_script("bash", "-c", "sleep 0.3", terminal=True)
        self.assertEqual(code, 0)
        self.assertTrue(self.agent_stopped())

    def test_an_agent_that_fails_leaves_the_asking_to_polkit(self):
        code, _, _ = self.run_script("bash", "-c", 'echo ran > "$STUB_DIR/ran"; exit 3',
                                     terminal=True, env={"PKTTY_FAIL": "1"})
        self.assertEqual(code, 3)
        self.assertEqual(self.read("ran"), "ran")
        self.assertEqual(self.registered(), [])

    def test_an_agent_not_up_in_time_leaves_the_asking_to_polkit(self):
        began = time.monotonic()
        code, _, _ = self.run_script("bash", "-c", 'echo ran > "$STUB_DIR/ran"', terminal=True,
                                     env={"PKTTY_NEVER": "1", "POLKIT_TTY_TIMEOUT": "0.5"})
        self.assertEqual(code, 0)
        self.assertEqual(self.read("ran"), "ran")
        self.assertLess(time.monotonic() - began, 3)
        self.assertTrue(self.agent_stopped())

    def test_without_pkttyagent_the_command_runs_as_it_is(self):
        (self.bin / "pkttyagent").unlink()
        code, _, _ = self.run_script("bash", "-c", "exit 4", terminal=True)
        self.assertEqual(code, 4)

    def test_pkexec_itself_is_refused(self):
        for command in (["pkexec", "true"], ["--", "pkexec", "true"]):
            code, _, err = self.run_script(*command)
            self.assertEqual(code, 2, command)
            self.assertIn("usage", err)


if __name__ == "__main__":
    unittest.main()
