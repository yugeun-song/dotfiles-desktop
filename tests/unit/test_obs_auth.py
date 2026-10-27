"""Tests for quickshell/bar/scripts/obs-auth.py, which reads OBS Studio's
WebSocket settings for the island and answers the server's challenge. Run
whole against settings written to a temporary configuration directory; no
OBS, and no real settings, are read.
"""

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = REPO / "quickshell/bar/scripts/obs-auth.py"

# obs-websocket 5's own worked example of the authentication string.
PASSWORD = "supersecretpassword"
SALT = "lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI="
CHALLENGE = "+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY="
ANSWER = "1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4="


class ObsAuthTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.tmp.name)
        self.config = self.home / ".config"

    def tearDown(self):
        self.tmp.cleanup()

    def settings(self, data, base=None):
        path = (base or self.config / "obs-studio") / "plugin_config" / "obs-websocket" / "config.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def run_script(self, *args):
        env = {"HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config), "PATH": "/usr/bin:/bin"}
        done = subprocess.run([sys.executable, "-I", "-S", str(SCRIPT), *args], env=env,
                              capture_output=True, text=True, timeout=10, check=False)
        return done.returncode, done.stdout, done.stderr

    def test_the_port_while_the_server_is_on(self):
        self.settings({"server_enabled": True, "server_port": 4466, "server_password": PASSWORD})
        self.assertEqual(self.run_script("port")[:2], (0, "4466\n"))

    def test_nothing_while_the_server_is_off(self):
        self.settings({"server_enabled": False, "server_port": 4466, "server_password": PASSWORD})
        self.assertEqual(self.run_script("port")[:2], (1, ""))
        self.assertEqual(self.run_script("answer", CHALLENGE, SALT)[:2], (1, ""))

    def test_nothing_without_settings(self):
        self.assertEqual(self.run_script("port")[:2], (1, ""))

    def test_the_answer_is_obs_websocket_s(self):
        self.settings({"server_enabled": True, "server_port": 4455, "server_password": PASSWORD})
        self.assertEqual(self.run_script("answer", CHALLENGE, SALT)[:2], (0, ANSWER + "\n"))

    def test_the_password_is_never_printed(self):
        self.settings({"server_enabled": True, "server_port": 4455, "server_password": PASSWORD})
        for args in (("port",), ("answer", CHALLENGE, SALT), ("answer",), ()):
            code, out, err = self.run_script(*args)
            self.assertNotIn(PASSWORD, out + err)

    def test_no_answer_without_a_password(self):
        self.settings({"server_enabled": True, "server_port": 4455, "server_password": ""})
        self.assertEqual(self.run_script("answer", CHALLENGE, SALT)[:2], (1, ""))

    def test_a_bad_port_is_none(self):
        for port in (0, 70000, "4455", True):
            self.settings({"server_enabled": True, "server_port": port, "server_password": PASSWORD})
            self.assertEqual(self.run_script("port")[0], 1, port)

    def test_obs_before_30_kept_them_in_global_ini(self):
        ini = self.config / "obs-studio" / "global.ini"
        ini.parent.mkdir(parents=True)
        ini.write_text("[OBSWebSocket]\nServerEnabled=true\nServerPort=4477\nServerPassword=" + PASSWORD + "\n")
        self.assertEqual(self.run_script("port")[:2], (0, "4477\n"))
        self.assertEqual(self.run_script("answer", CHALLENGE, SALT)[:2], (0, ANSWER + "\n"))

    def test_a_flatpak_s_settings(self):
        self.settings({"server_enabled": True, "server_port": 4488, "server_password": PASSWORD},
                      base=self.home / ".var/app/com.obsproject.Studio/config/obs-studio")
        self.assertEqual(self.run_script("port")[:2], (0, "4488\n"))

    def test_garbage_settings_are_none(self):
        path = self.config / "obs-studio" / "plugin_config" / "obs-websocket" / "config.json"
        path.parent.mkdir(parents=True)
        path.write_text("{ not json")
        self.assertEqual(self.run_script("port")[:2], (1, ""))

    def test_usage(self):
        self.assertEqual(self.run_script()[0], 2)
        self.assertEqual(self.run_script("answer", CHALLENGE)[0], 2)
        self.assertEqual(self.run_script("password")[0], 2)


if __name__ == "__main__":
    unittest.main()
