#!/usr/bin/env python3
"""The Shared Box: text, links and files shared between this PC and your other devices
(phone, Mac, iPhone) over Tailscale, and only there.

  shared-box.py serve              the server (shared-box.service). Your devices open it at
                                   https://<this machine>.<your tailnet>.ts.net/ (tailscale
                                   serve passes their requests to its socket; set up by
                                   shared-box-setup.sh): a page to send text and links
                                   from, showing what's in the box, live, with downloads
                                   for its files. On Android it installs as an app that's
                                   in the share sheet.
  shared-box.py add TEXT           put text or a link in the box, from this PC
  shared-box.py add-file FILE      put a file from this PC in the box (to download elsewhere)
  shared-box.py received FILE...   files that came in over Taildrop (taildrop-receive.sh)
  shared-box.py remove ID          take one out (for every device)
  shared-box.py send FILE TARGET [NAME]
                                   send a file to a device over Taildrop (TARGET: its
                                   Tailscale name or address), saying how it went

What's in the box: $XDG_DATA_HOME/shared-box/items.json (~/.local/share; only you can read
it), the newest first, the last 300. Files stay where they are (Taildrop's in Downloads);
the box points at them. Something arriving from another device shows as a notification.

Two sockets in $XDG_RUNTIME_DIR, which only you (and tailscaled) can open:
shared-box.sock for your tailnet (through tailscale serve; only your own devices, signed
in as you, get in) and shared-box-local.sock for this PC (the launcher's Shared Box menu,
these commands). Files on this PC only get into the box through the local one.
"""

import html
import http.client
import http.server
import json
import math
import mimetypes
import os
import re
import secrets
import shutil
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path.home()
DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share") / "shared-box"
STORE = DATA / "items.json"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "shared-box"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
TAILNET_SOCKET = RUNTIME / "shared-box.sock"
LOCAL_SOCKET = RUNTIME / "shared-box-local.sock"
COLORS = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "quickshell/colors.css"
PAGE = HERE / "shared-box.html"
KEEP = 300
MAX_TEXT = 100_000
DEBUG = os.environ.get("SHARED_BOX_DEBUG") == "1"       # (logs each request's headers)
DEFAULT_COLORS = {"fg": "#e0e3e8", "subtle": "#c1c7ce", "muted": "#8b9198", "accent": "#96cdf8",
                  "accent2": "#cfc0e8", "ink": "#00344e", "base": "#101418", "error": "#ffb4ab"}
URL = re.compile(r"https?://[^\s<>\"']*[^\s<>\"'.,;:!?)\]]", re.IGNORECASE)


def log(*args):
    print(*args, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- your tailnet

class Tailnet:
    """Who's who on your tailnet (tailscale status / whois), looked up as needed."""

    def __init__(self):
        self.lock = threading.Lock()
        self.me = None              # {"name", "login", "ips"}
        self.names = {}             # address -> (device name, when looked up)

    @staticmethod
    def run(*args):
        try:
            r = subprocess.run(["tailscale", *args], capture_output=True, text=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            return None
        return r.stdout if r.returncode == 0 else None

    def self_info(self):
        with self.lock:
            if self.me:
                return self.me
        try:
            d = json.loads(self.run("status", "--json") or "")
            s = d["Self"]
            me = {"name": s.get("HostName") or socket.gethostname(),
                  "login": d["User"][str(s["UserID"])]["LoginName"],
                  "ips": set(s.get("TailscaleIPs") or [])}
        except (ValueError, KeyError, TypeError):
            return {"name": socket.gethostname(), "login": None, "ips": set()}   # (asked again next time)
        with self.lock:
            self.me = me
        return me

    def device(self, address):
        """A device's name ("Galaxy A17 5G") from its Tailscale address."""
        me = self.self_info()
        if address in me["ips"]:
            return me["name"]
        with self.lock:
            known = self.names.get(address)
        if known and time.time() - known[1] < 600:
            return known[0]
        name = "another device"
        try:
            node = json.loads(self.run("whois", "--json", address) or "")["Node"]
            name = (node.get("Hostinfo") or {}).get("Hostname") or node.get("ComputedName") or node["Name"].split(".")[0]
        except (ValueError, KeyError, TypeError, AttributeError):
            pass
        with self.lock:
            self.names[address] = (name, time.time())
        return name


# ---------------------------------------------------------------- what's in the box

class Box:
    def __init__(self):
        self.changed = threading.Condition()
        self.version = 0
        try:
            items = json.loads(STORE.read_text())
            self.items = [i for i in items if isinstance(i, dict) and isinstance(i.get("id"), str)]
        except (OSError, ValueError, TypeError):
            self.items = []

    def _save(self):
        DATA.mkdir(parents=True, exist_ok=True)
        os.chmod(DATA, 0o700)
        tmp = STORE.with_name(".items.json.tmp")
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(self.items, f, ensure_ascii=False)
        os.replace(tmp, STORE)
        self.version += 1
        self.changed.notify_all()

    def add(self, item):
        with self.changed:
            self.items.insert(0, item)
            del self.items[KEEP:]
            self._save()

    def remove(self, item_id):
        with self.changed:
            left = [i for i in self.items if i["id"] != item_id]
            if len(left) == len(self.items):
                return False
            self.items = left
            self._save()
            return True

    def clear(self):
        with self.changed:
            self.items = []
            self._save()

    def get(self, item_id):
        with self.changed:
            return next((i for i in self.items if i["id"] == item_id), None)

    def snapshot(self):
        with self.changed:
            return self.version, list(self.items)

    def wait(self, version, timeout):
        """The version once it's no longer `version`, or after `timeout` seconds."""
        with self.changed:
            self.changed.wait_for(lambda: self.version != version, timeout)
            return self.version


def new_id():
    return f"{int(time.time() * 1000):x}{secrets.token_hex(3)}"


def text_item(text, source):
    text = text.replace("\r\n", "\n").strip()
    kind = "link" if re.fullmatch(r"https?://\S+", text, re.IGNORECASE) else "text"
    return {"id": new_id(), "kind": kind, "text": text, "from": source, "time": round(time.time(), 3)}


def file_item(path, source, received=False):
    p = Path(path).resolve()
    return {"id": new_id(), "kind": "file", "text": p.name, "path": str(p), "size": p.stat().st_size,
            "from": source, "time": round(time.time(), 3), "received": received}


def public(item):
    """An item as your devices see it: no paths on this PC."""
    out = {k: v for k, v in item.items() if k != "path"}
    if item.get("kind") == "file":
        out["gone"] = not os.path.isfile(item.get("path", ""))
    return out


# ---------------------------------------------------------------- the look

def colors():
    """The desktop's colours (matugen's, from the wallpaper)."""
    c = dict(DEFAULT_COLORS)
    try:
        c.update(re.findall(r"@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})\s*;", COLORS.read_text()))
    except OSError:
        pass
    return c


def icon_png(size, c):
    """The app icon: an inbox tray with an arrow into it, in ink on the accent gradient
    (inside the middle 80%, so it can be cut to any shape: "maskable")."""
    rgb = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
    top, bottom, ink = rgb(c["accent"]), rgb(c["accent2"]), rgb(c["ink"])
    k = size / 512
    lines = [((150, 286), (150, 372)), ((150, 372), (362, 372)), ((362, 372), (362, 286)),
             ((256, 132), (256, 300)), ((198, 244), (256, 302)), ((256, 302), (314, 244))]
    lines = [((ax * k, ay * k), (bx * k, by * k)) for (ax, ay), (bx, by) in lines]
    half = 14 * k

    def distance(px, py, a, b):
        (ax, ay), (bx, by) = a, b
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        return math.hypot(px - ax - t * dx, py - ay - t * dy)

    rows = []
    for y in range(size):
        t = y / max(1, size - 1)
        bg = [round(a + (b - a) * t) for a, b in zip(top, bottom)]
        row = bytearray([0]) + bytes(bg) * size
        py = y + 0.5
        if 116 * k < py < 392 * k:
            for x in range(int(130 * k), int(382 * k) + 1):
                d = min(distance(x + 0.5, py, a, b) for a, b in lines)
                a = max(0.0, min(1.0, half + 0.5 - d))
                if a > 0:
                    row[1 + 3 * x:4 + 3 * x] = bytes(round(g * (1 - a) + i * a) for g, i in zip(bg, ink))
        rows.append(bytes(row))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


_icons = {}


def icon(size):
    """The icon's PNG at `size` px, made once for each set of colours (and kept on disk,
    for the notifications)."""
    c = colors()
    key = (size, c["accent"], c["accent2"], c["ink"])
    if key not in _icons:
        _icons[key] = icon_png(size, c)
        try:
            CACHE.mkdir(parents=True, exist_ok=True)
            (CACHE / f"icon-{size}.png").write_bytes(_icons[key])
        except OSError:
            pass
    return _icons[key]


def manifest(c):
    return {
        "name": "Shared Box",
        "short_name": "Shared Box",
        "description": "Text, links and files shared between your devices",
        "start_url": "/",
        "scope": "/",
        "display": "standalone",
        "background_color": c["base"],
        "theme_color": c["base"],
        "icons": [
            {"src": "/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
            {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
            {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
        ],
        # Android: "Shared Box" in the share sheet, once it's installed
        "share_target": {"action": "/share", "method": "GET",
                         "params": {"title": "title", "text": "text", "url": "url"}},
    }


# (installable as an app; everything still comes from the server)
SERVICE_WORKER = """self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {});
"""


# ---------------------------------------------------------------- notifications here

def session_env():
    """The desktop session's environment (WAYLAND_DISPLAY...), for opening and copying."""
    env = dict(os.environ)
    try:
        out = subprocess.run(["systemctl", "--user", "show-environment"], capture_output=True, text=True, timeout=5).stdout
        for line in out.splitlines():
            name, _, value = line.partition("=")
            if name in ("WAYLAND_DISPLAY", "DISPLAY", "XDG_CURRENT_DESKTOP", "HYPRLAND_INSTANCE_SIGNATURE"):
                env[name] = value
    except (OSError, subprocess.TimeoutExpired):
        pass
    return env


def notify(item):
    """Something arrived from another device: say so; its buttons open or copy it."""
    if not shutil.which("notify-send"):
        return
    kind, text, source = item["kind"], item["text"], item["from"]
    url = URL.search(text) if kind == "text" else None
    if kind == "file":
        where = Path(item["path"]).parent
        shown = "~/" + str(where.relative_to(HOME)) if where.is_relative_to(HOME) else str(where)
        title = f"Received {text}"
        body = html.escape(f"{'Over Taildrop' if item.get('received') else 'From ' + source}, in {shown}")
        actions = [("default", "Open"), ("folder", "Open folder")]
    elif kind == "link":
        title = f"Link from {source}"
        body = f'<a href="{html.escape(text)}">{html.escape(text)}</a>'
        actions = [("default", "Open link"), ("copy", "Copy link")]
    else:
        title = f"From {source}"
        body = html.escape(text[:400] + ("…" if len(text) > 400 else ""))
        actions = [("default", "Copy")] + ([("open", "Open link")] if url else [])
    command = ["notify-send", "-a", "Shared Box", "-i", str(CACHE / "icon-192.png")]
    for key, label in actions:
        command += ["-A", f"{key}={label}"]
    command += ["--", title, body]

    def run():
        icon(192)
        env = session_env()
        try:
            action = subprocess.run(command, capture_output=True, text=True, env=env).stdout.strip()
        except OSError:
            return
        target = None
        if action == "default":
            target = item["path"] if kind == "file" else text if kind == "link" else None
            if kind == "text":
                subprocess.run(["wl-copy", "--", text], env=env)
        elif action == "open" and url:
            target = url[0]
        elif action == "folder":
            target = str(Path(item["path"]).parent)
        elif action == "copy":
            subprocess.run(["wl-copy", "--", text], env=env)
        if target:
            subprocess.Popen(["xdg-open", target], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)

    threading.Thread(target=run, daemon=True).start()


# ---------------------------------------------------------------- the server

class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    remote = True           # (the tailnet's socket, or this PC's)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "SharedBox/1"
    protocol_version = "HTTP/1.0"
    box = None
    tailnet = None

    def address_string(self):
        return "-"

    def log_message(self, fmt, *args):
        if DEBUG:
            log(fmt % args)

    def who(self):
        """(the device asking, whether it's another one than this PC), or None when it may
        not: through the tailnet's socket, only a device signed in as you."""
        me = self.tailnet.self_info()
        if not self.server.remote:
            return me["name"], False
        login = self.headers.get("Tailscale-User-Login")
        if DEBUG:
            log("request", self.command, self.path, dict(self.headers))
        if not login or (me["login"] and login.lower() != me["login"].lower()):
            return None
        address = (self.headers.get("X-Forwarded-For") or "").split(",")[-1].strip()
        name = self.tailnet.device(address) if address else "another device"
        return name, name != me["name"]

    def send(self, code, body=b"", kind="application/json", headers=()):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def json(self, code, value):
        self.send(code, json.dumps(value, ensure_ascii=False))

    def refuse(self, code, why):
        self.send(code, why + "\n", "text/plain; charset=utf-8")

    # ---------- GET

    def do_GET(self):
        who = self.who()
        if who is None:
            return self.refuse(403, "Only your own devices can use the Shared Box.")
        url = urllib.parse.urlsplit(self.path)
        path = url.path
        if path == "/":
            self.page(who)
        elif path == "/manifest.webmanifest":
            self.send(200, json.dumps(manifest(colors())), "application/manifest+json")
        elif path == "/sw.js":
            self.send(200, SERVICE_WORKER, "text/javascript")
        elif path in ("/icon-192.png", "/icon-512.png", "/favicon.ico"):
            self.send(200, icon(512 if "512" in path else 192), "image/png", [("Cache-Control", "max-age=3600")])
        elif path == "/api/items":
            version, items = self.box.snapshot()
            self.json(200, {"version": version, "you": who[0], "host": self.tailnet.self_info()["name"],
                            "items": [public(i) for i in items]})
        elif path == "/api/events":
            self.events()
        elif m := re.fullmatch(r"/files/([0-9a-f]+)(?:/[^/]*)?", path):
            self.download(m[1])
        elif path == "/share":
            self.share(url.query, who)
        else:
            self.refuse(404, "Not here.")

    do_HEAD = do_GET

    def page(self, who):
        c = colors()
        version, items = self.box.snapshot()
        start = {"version": version, "you": who[0], "host": self.tailnet.self_info()["name"],
                 "items": [public(i) for i in items]}
        css = "".join(f"--{name}: {value}; " for name, value in c.items())
        body = (PAGE.read_text()
                .replace("/*COLORS*/", css)
                .replace("#101418", c["base"])
                .replace("/*START*/null", json.dumps(start, ensure_ascii=False).replace("<", "\\u003c")))
        self.send(200, body, "text/html; charset=utf-8", [
            ("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; "
             "style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'")])

    def events(self):
        """Server-sent events: the box's version, each time it changes (and a ping now and
        then, to keep the connection)."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            version = self.box.snapshot()[0]
            self.wfile.write(f"retry: 3000\ndata: {version}\n\n".encode())
            self.wfile.flush()
            while True:
                now = self.box.wait(version, 20)
                self.wfile.write((f"data: {now}\n\n" if now != version else ": ping\n\n").encode())
                self.wfile.flush()
                version = now
        except OSError:
            pass

    def download(self, item_id):
        item = self.box.get(item_id)
        if not item or item.get("kind") != "file":
            return self.refuse(404, "That's not in the box.")
        try:
            f = open(item["path"], "rb")
        except OSError:
            return self.refuse(404, "That file isn't there any more.")
        with f:
            st = os.fstat(f.fileno())
            kind = mimetypes.guess_type(item["text"])[0] or "application/octet-stream"
            self.send_response(200)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(st.st_size))
            # (always a download: a page from it can't run as this one)
            self.send_header("Content-Disposition", "attachment; filename*=UTF-8''" + urllib.parse.quote(item["text"]))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            if self.command != "HEAD":
                try:
                    shutil.copyfileobj(f, self.wfile, 1 << 20)
                except OSError:
                    pass

    def share(self, query, who):
        """Android's share sheet (the installed app): what was shared goes in the box."""
        if self.headers.get("Sec-Fetch-Site", "none") not in ("none", "same-origin"):
            return self.refuse(403, "Share from your own device.")
        q = urllib.parse.parse_qs(query)
        title, text, url = (q.get(name, [""])[0].strip() for name in ("title", "text", "url"))
        content = text
        if url and url not in text:
            content = f"{text}\n{url}".strip()
        content = (content or title)[:MAX_TEXT]
        if content:
            item = text_item(content, who[0])
            self.box.add(item)
            if who[1]:
                notify(item)
        self.send(303, "", "text/plain", [("Location", "/?shared=1")])

    # ---------- POST, DELETE (only from this page or this PC: a page elsewhere can't send
    # the X-Shared-Box header)

    def body(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if not 0 < length <= 4 * MAX_TEXT:
            return None
        try:
            return json.loads(self.rfile.read(length))
        except ValueError:
            return None

    def do_POST(self):
        who = self.who()
        if who is None or self.headers.get("X-Shared-Box") != "1":
            return self.refuse(403, "Only your own devices can use the Shared Box.")
        if urllib.parse.urlsplit(self.path).path != "/api/items":
            return self.refuse(404, "Not here.")
        data = self.body()
        if not isinstance(data, dict):
            return self.refuse(400, "Send {\"text\": ...}.")
        if "file" in data:
            # (a file on this PC: from this PC only)
            path = data["file"]
            if self.server.remote or not isinstance(path, str) or not os.path.isabs(path) or not os.path.isfile(path):
                return self.refuse(400, "No such file here.")
            item = file_item(path, "Taildrop" if data.get("received") else who[0], bool(data.get("received")))
        else:
            text = data.get("text")
            if not isinstance(text, str) or not text.strip():
                return self.refuse(400, "Nothing to send.")
            if len(text) > MAX_TEXT:
                return self.refuse(413, "That's too long for the box (100 000 characters at most).")
            item = text_item(text, who[0])
        self.box.add(item)
        if who[1] or item.get("received"):
            notify(item)
        self.json(201, public(item))

    def do_DELETE(self):
        who = self.who()
        if who is None or self.headers.get("X-Shared-Box") != "1":
            return self.refuse(403, "Only your own devices can use the Shared Box.")
        path = urllib.parse.urlsplit(self.path).path
        if path == "/api/items":
            self.box.clear()
        elif m := re.fullmatch(r"/api/items/([0-9a-f]+)", path):
            if not self.box.remove(m[1]):
                return self.refuse(404, "That's not in the box.")
        else:
            return self.refuse(404, "Not here.")
        self.send(204)


def serve():
    Handler.box = Box()
    Handler.tailnet = Tailnet()
    servers = []
    for path, remote in ((TAILNET_SOCKET, True), (LOCAL_SOCKET, False)):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
        mask = os.umask(0o177)          # (rw for you only; tailscaled is root)
        try:
            server = Server(str(path), Handler)
        finally:
            os.umask(mask)
        server.remote = remote
        servers.append(server)

    def stop(*_):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    threading.Thread(target=icon, args=(192,), daemon=True).start()     # (ready for notifications)
    log(f"Shared Box: {TAILNET_SOCKET} (your tailnet), {LOCAL_SOCKET} (this PC)")
    try:
        threading.Thread(target=servers[1].serve_forever, daemon=True).start()
        servers[0].serve_forever()
    finally:
        for path in (TAILNET_SOCKET, LOCAL_SOCKET):
            try:
                path.unlink()
            except OSError:
                pass


# ---------------------------------------------------------------- the commands

class LocalConnection(http.client.HTTPConnection):
    def __init__(self):
        super().__init__("localhost", timeout=10)

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(str(LOCAL_SOCKET))


def call(method, path, data=None):
    connection = LocalConnection()
    try:
        connection.request(method, path, json.dumps(data).encode() if data is not None else None,
                           {"X-Shared-Box": "1", "Content-Type": "application/json"})
        response = connection.getresponse()
        out = response.read()
    except OSError:
        sys.exit("The Shared Box isn't running (set it up with ~/.config/quickshell/scripts/shared-box-setup.sh)")
    if response.status >= 300:
        sys.exit(out.decode("utf-8", "replace").strip() or f"The Shared Box said no ({response.status})")
    return json.loads(out) if out else None


def send(path, target, label=None):
    """A file to a device over Taildrop, with a notification of how it went."""
    name, label = Path(path).name, label or target

    def say(title, body, transient):
        subprocess.run(["notify-send", "-a", "Shared Box", "-i", str(CACHE / "icon-192.png")]
                       + (["-e"] if transient else []) + ["--", title, html.escape(body)])

    say(f"Sending {name}", f"to {label}…", True)
    r = subprocess.run(["tailscale", "file", "cp", path, f"{target}:"], capture_output=True, text=True)
    if r.returncode == 0:
        say(f"Sent {name}", f"to {label}", True)
    else:
        why = (r.stderr or r.stdout).strip().splitlines()
        say(f"Couldn't send {name}", f"to {label}: {why[-1] if why else 'Taildrop failed'}", False)
        sys.exit(1)


def main():
    args = sys.argv[1:]
    command = args[0] if args else ""
    if command == "serve" and len(args) == 1:
        serve()
    elif command == "add" and len(args) >= 2:
        print(call("POST", "/api/items", {"text": " ".join(args[1:])})["id"])
    elif command == "add-file" and len(args) == 2:
        print(call("POST", "/api/items", {"file": os.path.abspath(args[1])})["id"])
    elif command == "received" and len(args) >= 2:
        for path in args[1:]:
            call("POST", "/api/items", {"file": os.path.abspath(path), "received": True})
    elif command == "remove" and len(args) == 2:
        call("DELETE", f"/api/items/{args[1]}")
    elif command == "send" and len(args) in (3, 4):
        send(os.path.abspath(args[1]), args[2], args[3] if len(args) == 4 else None)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
