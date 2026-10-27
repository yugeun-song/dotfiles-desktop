#!/usr/bin/env python3
"""OBS Studio's WebSocket server, for the island's OBS part
(services/Obs.qml): where it listens, and the answer to its challenge, both
from OBS's own settings, so that the password never enters the bar.

  obs-auth.py port                     the port, while the server is on
  obs-auth.py answer CHALLENGE SALT    the authentication string for Identify

OBS keeps them in plugin_config/obs-websocket/config.json under its
configuration directory (a Flatpak's under ~/.var/app), and before OBS 30 in
global.ini's [OBSWebSocket] section. The answer is obs-websocket 5's:
base64(sha256(base64(sha256(password + salt)) + challenge)).

Exit 1, printing nothing, while the server is switched off, or for an answer
with no password set. The password is printed nowhere and logged nowhere;
only the answer, which is good for that one challenge, leaves this process.
"""

import base64
import configparser
import hashlib
import json
import os
import sys

DEFAULT_PORT = 4455


def config_dirs():
    home = os.path.expanduser("~")
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    return [os.path.join(xdg, "obs-studio"),
            os.path.join(home, ".var", "app", "com.obsproject.Studio", "config", "obs-studio")]


def from_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    return {
        "enabled": data.get("server_enabled") is True,
        "port": data.get("server_port", DEFAULT_PORT),
        "password": data.get("server_password", ""),
    }


def from_ini(path):
    parser = configparser.ConfigParser(interpolation=None)
    try:
        if not parser.read(path, encoding="utf-8") or not parser.has_section("OBSWebSocket"):
            return None
    except (OSError, configparser.Error):
        return None
    section = parser["OBSWebSocket"]
    try:
        port = int(section.get("ServerPort", str(DEFAULT_PORT)))
    except ValueError:
        port = 0
    return {
        "enabled": section.get("ServerEnabled", "false").strip().lower() == "true",
        "port": port,
        "password": section.get("ServerPassword", ""),
    }


def settings():
    for base in config_dirs():
        found = from_json(os.path.join(base, "plugin_config", "obs-websocket", "config.json"))
        if found is None:
            found = from_ini(os.path.join(base, "global.ini"))
        if found is not None:
            return found
    return None


def answer(password, challenge, salt):
    secret = base64.b64encode(hashlib.sha256((password + salt).encode()).digest()).decode()
    return base64.b64encode(hashlib.sha256((secret + challenge).encode()).digest()).decode()


def main(argv):
    if argv[1:2] not in (["port"], ["answer"]) or (argv[1] == "answer" and len(argv) != 4):
        print("usage: obs-auth.py port | answer CHALLENGE SALT", file=sys.stderr)
        return 2
    found = settings()
    if found is None or not found["enabled"]:
        return 1
    if argv[1] == "port":
        port = found["port"]
        if not isinstance(port, int) or isinstance(port, bool) or not 0 < port < 65536:
            return 1
        print(port)
        return 0
    password = found["password"]
    if not isinstance(password, str) or password == "":
        return 1
    print(answer(password, argv[2], argv[3]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
