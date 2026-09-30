#!/usr/bin/env python3
"""Workspace state for the custom/ws1..ws10 modules.

Waybar's built-in hyprland/workspaces click sends old-style `dispatch workspace N`,
which Hyprland's Lua config rejects (Alexays/Waybar#5008). So each workspace is a
custom module with its own Lua on-click; this script feeds them.

Listens on Hyprland's event socket, writes one JSON line per workspace to
$XDG_RUNTIME_DIR/waybar-ws/<n> (empty = hidden) and signals waybar to re-read.
Started by waybar itself (custom/ws-daemon) so it lives and dies with the bar.
"""

import json
import os
import signal
import socket
import subprocess
import sys

MAX_WS = 10
SIGNAL = 8  # matches "signal": 8 on the custom/ws* modules

runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
hypr_dir = os.path.join(runtime, "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"])
state_dir = os.path.join(runtime, "waybar-ws")

urgent = set()  # workspace ids with an urgent window, cleared once visited


def query(cmd):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(os.path.join(hypr_dir, ".socket.sock"))
        s.sendall(f"j/{cmd}".encode())
        data = b""
        while chunk := s.recv(65536):
            data += chunk
    return json.loads(data)


def refresh():
    workspaces = {w["id"]: w for w in query("workspaces")}
    active = query("activeworkspace")["id"]
    urgent.discard(active)

    for n in range(1, MAX_WS + 1):
        line = ""
        if n in workspaces or n == active:
            windows = workspaces.get(n, {}).get("windows", 0)
            classes = ["ws", "occupied" if windows else "empty"]
            if n == active:
                classes.append("active")
            if n in urgent:
                classes.append("urgent")
            line = json.dumps({"text": str(n), "class": classes,
                               "tooltip": f"Workspace {n} · {windows} window{'s' * (windows != 1)}"})
        tmp = os.path.join(state_dir, f".{n}")
        with open(tmp, "w") as f:
            f.write(line + "\n")
        os.replace(tmp, os.path.join(state_dir, str(n)))

    subprocess.run(["pkill", f"-RTMIN+{SIGNAL}", "-x", "waybar"])


def mark_urgent(address):
    for c in query("clients"):
        if c["address"].removeprefix("0x") == address.removeprefix("0x"):
            urgent.add(c["workspace"]["id"])


def main():
    os.makedirs(state_dir, exist_ok=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    refresh()

    events = ("workspace", "focusedmon", "createworkspace", "destroyworkspace",
              "openwindow", "closewindow", "movewindow", "urgent")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(os.path.join(hypr_dir, ".socket2.sock"))
        buf = b""
        while chunk := s.recv(4096):
            buf += chunk
            *lines, buf = buf.split(b"\n")
            dirty = False
            for raw in lines:
                event, _, data = raw.decode(errors="replace").partition(">>")
                if event == "urgent":
                    mark_urgent(data)
                if event.removesuffix("v2") in events:
                    dirty = True
            if dirty:
                refresh()


if __name__ == "__main__":
    main()
