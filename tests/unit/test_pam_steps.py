"""Tests for pam/system-auth, the lockout in steps: its auth lines run
through libpam itself, from a directory of this test's own (pam_start_confdir),
with pam_deny and pam_permit standing in for the password check, so no
password is typed or read, and a tally directory of its own, so the
machine's /run/faillock is never touched. The lock times are cut to a
thirtieth (a minute to two seconds) so the steps can be waited out.
"""

import ctypes
import ctypes.util
import getpass
import pathlib
import re
import tempfile
import time
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
SOURCE = REPO / "pam/system-auth"
USER = getpass.getuser()
SCALE = 30


class Message(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class Response(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_char_p), ("resp_retcode", ctypes.c_int)]


CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(Message)),
                        ctypes.POINTER(ctypes.POINTER(Response)), ctypes.c_void_p)


class Conv(ctypes.Structure):
    _fields_ = [("conv", CONV), ("appdata_ptr", ctypes.c_void_p)]


def libraries():
    name = ctypes.util.find_library("pam")
    if not name:
        return None, None
    pam = ctypes.CDLL(name)
    if not hasattr(pam, "pam_start_confdir"):
        return None, None
    pam.pam_start_confdir.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(Conv), ctypes.c_char_p,
                                      ctypes.POINTER(ctypes.c_void_p)]
    pam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
    pam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
    libc = ctypes.CDLL(ctypes.util.find_library("c"))
    libc.calloc.restype = ctypes.c_void_p
    libc.calloc.argtypes = [ctypes.c_size_t, ctypes.c_size_t]
    return pam, libc


PAM, LIBC = libraries()
MODULES = [pathlib.Path(d) for d in ("/usr/lib/security", "/lib/security", "/usr/lib64/security",
                                     "/usr/lib/x86_64-linux-gnu/security")]


def module_present(name):
    return any((d / name).exists() for d in MODULES)


def preauth_steps(text):
    """The preauth lines' (control, deny, unlock_time, fail_interval)."""
    out = []
    for line in text.splitlines():
        if re.match(r"^auth\s+\S+\s+pam_faillock\.so\s+preauth\b", line):
            fields = dict(re.findall(r"(\w+)=(\d+)", line))
            out.append((line.split()[1], int(fields["deny"]), int(fields["unlock_time"]), int(fields["fail_interval"])))
    return out


def render(text, check, tally):
    """The file's auth lines with `check` for the password, the homed and
    environment modules left out, every faillock line on `tally` and its
    lock a thirtieth as long. And with nodelay: pam_faillock holds every
    failure two seconds (the machine's lines keep that), longer than the
    first step cut to a thirtieth, which then ran out during the wait."""
    lines = []
    for line in text.splitlines():
        if not re.match(r"^-?auth\s", line) or "pam_systemd_home" in line or "pam_env" in line:
            continue
        if "pam_unix.so" in line:
            line = re.sub(r"pam_unix\.so.*$", check, line)
        if "pam_faillock.so" in line:
            line = re.sub(r"unlock_time=(\d+)", lambda m: f"unlock_time={max(1, int(m.group(1)) // SCALE)}", line)
            line += f" dir={tally} nodelay"
        lines.append(line)
    return "\n".join(lines) + "\n"


@unittest.skipUnless(PAM and module_present("pam_faillock.so") and module_present("pam_deny.so")
                     and module_present("pam_permit.so"), "libpam with pam_start_confdir and pam_faillock not found")
class Steps(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.dir.name)
        self.confdir = root / "pam.d"
        self.confdir.mkdir()
        tally = root / "tally"
        tally.mkdir()
        text = SOURCE.read_text()
        (self.confdir / "wrong").write_text(render(text, "pam_deny.so", tally))
        (self.confdir / "right").write_text(render(text, "pam_permit.so", tally))

    def tearDown(self):
        self.dir.cleanup()

    def attempt(self, service):
        messages = []

        def answer(count, msgs, resp, _data):
            array = LIBC.calloc(count, ctypes.sizeof(Response))
            if not array:
                return 5
            for i in range(count):
                message = msgs[i].contents
                messages.append(message.msg.decode(errors="replace") if message.msg else "")
            resp[0] = ctypes.cast(array, ctypes.POINTER(Response))
            return 0

        conv = Conv(CONV(answer), None)
        handle = ctypes.c_void_p()
        rc = PAM.pam_start_confdir(service.encode(), USER.encode(), ctypes.byref(conv), str(self.confdir).encode(),
                                   ctypes.byref(handle))
        self.assertEqual(rc, 0, "pam_start_confdir")
        rc = PAM.pam_authenticate(handle, 0)
        PAM.pam_end(handle, rc)
        return rc == 0, any("locked" in m for m in messages)

    def wrong(self, times=1):
        for _ in range(times):
            ok, locked = self.attempt("wrong")
            self.assertFalse(ok)
            self.assertFalse(locked, "a wrong password while locked was tried, not refused")

    def test_the_steps_as_written(self):
        steps = preauth_steps(SOURCE.read_text())
        self.assertEqual([s[1] for s in steps], [10, 15, 20, 25, 30, 35, 40])
        self.assertEqual([s[2] for s in steps], [60 * 2 ** i for i in range(7)])
        self.assertEqual({s[0] for s in steps}, {"requisite"})
        text = SOURCE.read_text()
        for action in ("authfail", "authsucc"):
            line = next(ln for ln in text.splitlines() if f"pam_faillock.so      {action}" in ln)
            self.assertIn("deny=0", line)
        intervals = set(re.findall(r"pam_faillock\.so.*fail_interval=(\d+)", text))
        self.assertEqual(intervals, {str(steps[0][3])})

    def test_nine_wrong_lock_nothing(self):
        self.wrong(9)
        self.assertEqual(self.attempt("right"), (True, False))

    def test_the_steps_climb_and_a_right_password_clears_them(self):
        # Two seconds for the first step, four for the second (a thirtieth).
        first, second = 60 // SCALE, 120 // SCALE
        self.wrong(10)
        self.assertEqual(self.attempt("right"), (False, True), "the 10th wrong password locks, the right one too")
        time.sleep(first + 1.1)
        self.assertEqual(self.attempt("right"), (True, False), "the first step runs out")
        self.wrong(10)
        time.sleep(first + 1.1)
        self.wrong()
        self.assertEqual(self.attempt("right"), (False, True), "a lock that ran out kept the count: the 11th locks again")
        for _ in range(4):
            time.sleep(first + 1.1)
            self.wrong()
        time.sleep(first + 1.1)
        self.assertEqual(self.attempt("right"), (False, True), "the 15th holds for the second step, past the first's")
        time.sleep(second + 2 - (first + 1.1) + 0.1)
        self.assertEqual(self.attempt("right"), (True, False), "the second step runs out; the right password gets in")
        self.wrong()
        self.assertEqual(self.attempt("right"), (True, False), "and cleared the count")


if __name__ == "__main__":
    unittest.main()
