#!/usr/bin/env python3
"""The Shared Box: text, links and files shared between this PC and your other devices
(phone, Mac, iPhone) over Tailscale, and only there.

  shared-box.py serve              the server (shared-box.service). Your devices open it at
                                   https://<this machine>.<your tailnet>.ts.net/ (tailscale
                                   serve passes their requests to its socket; set up by
                                   shared-box-setup.sh): a page to send text, links and
                                   files from, showing what's in the box, live, with
                                   downloads for its files. On Android it installs as an
                                   app that's in the share sheet (text, links and files).
  shared-box.py add TEXT           put text or a link in the box, from this PC
  shared-box.py add-file [--quiet] FILE...
                                   put files from this PC in the box, to download on your
                                   other devices (a notification says how it went, unless
                                   --quiet: then only an error, on stderr)
  shared-box.py copied             the files copied on this PC (Ctrl+C in Dolphin...), from
                                   the clipboard: their paths, each ending in a NUL
  shared-box.py remove ID          take one out (for every device)

What's in the box: $XDG_DATA_HOME/shared-box/items.json (~/.local/share; only you can read
it), the newest first, the last 300. Files from your other devices land in your Downloads
folder (a name that's taken gets a number: "photo (1).jpg"); files from this PC stay where
they are. The box only points at them. Something arriving from another device shows as a
notification.

Two sockets in $XDG_RUNTIME_DIR, which only you (and tailscaled) can open:
shared-box.sock for your tailnet (through tailscale serve; only your own devices, signed
in as you, get in) and shared-box-local.sock for this PC (the launcher's Shared Box menu,
these commands). Files already on this PC only get into the box through the local one.
"""

import errno
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
INCOMING = DATA / "incoming"        # (files on their way in, until they're whole)
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "shared-box"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
TAILNET_SOCKET = RUNTIME / "shared-box.sock"
LOCAL_SOCKET = RUNTIME / "shared-box-local.sock"
COLORS = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "quickshell/colors.css"
PAGE = HERE / "shared-box.html"
KEEP = 300
MAX_TEXT = 100_000
SPARE = 1 << 30                     # (disk space files coming in leave free: 1 GiB)
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


def file_item(path, source):
    p = Path(path).resolve()
    return {"id": new_id(), "kind": "file", "text": p.name, "path": str(p), "size": p.stat().st_size,
            "from": source, "time": round(time.time(), 3)}


# ---------------------------------------------------------------- files coming in

class Full(Exception):
    """Not enough disk space left for a file coming in."""


def incoming():
    """The folder files come in to until they're whole (only you can open it)."""
    DATA.mkdir(parents=True, exist_ok=True)
    os.chmod(DATA, 0o700)
    INCOMING.mkdir(exist_ok=True)
    return INCOMING


def downloads():
    """Your Downloads folder (xdg-user-dirs), where files from your devices land."""
    config = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "user-dirs.dirs"
    try:
        m = re.search(r'^XDG_DOWNLOAD_DIR="([^"]*)"', config.read_text(), re.MULTILINE)
        if m:
            folder = Path(m[1].replace("$HOME", str(HOME)))
            if folder.is_absolute() and folder != HOME:
                return folder
    except OSError:
        pass
    return HOME / "Downloads"


def clean_name(name):
    """A file name from another device, safe to save: no folders, no control characters,
    not hidden, and short enough for the disk."""
    name = name.replace("\\", "/").rsplit("/", 1)[-1]
    name = "".join(c for c in name if c.isprintable()).strip().lstrip(".").strip()
    if not name:
        return "file"
    while len(name.encode()) > 200:
        stem, dot, ext = name.rpartition(".")
        name = (stem[:-1] + dot + ext) if dot and stem and len(ext) < 20 else name[:-1]
    return name


def place(part, name):
    """A file that came in, moved into Downloads as `name`, or "name (1).ext", ... if
    that's taken (never over another file)."""
    folder = downloads()
    folder.mkdir(parents=True, exist_ok=True)
    stem, dot, ext = name.rpartition(".")
    base, ext = (stem, dot + ext) if dot and stem else (name, "")
    for n in range(100_000):
        candidate = folder / (name if n == 0 else f"{base} ({n}){ext}")
        try:
            os.link(part, candidate)                # (fails if the name is taken)
        except FileExistsError:
            continue
        except OSError as e:
            if e.errno not in (errno.EXDEV, errno.EPERM, errno.ENOTSUP):
                raise
            # (Downloads is on another disk: copied there)
            try:
                fd = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
            except FileExistsError:
                continue
            with os.fdopen(fd, "wb") as out, open(part, "rb") as src:
                shutil.copyfileobj(src, out, 1 << 20)
        os.unlink(part)
        return candidate
    raise OSError("no free name for it in Downloads")


class Body:
    """A request's body as it comes in (files can be big): Content-Length bytes, or in
    chunks (tailscale serve can pass it on that way)."""

    def __init__(self, rfile, headers):
        self.rfile = rfile
        self.chunked = "chunked" in (headers.get("Transfer-Encoding") or "").lower()
        if self.chunked:
            self.length, self.left, self.ended = None, None, False
        else:
            try:
                self.length = int(headers.get("Content-Length") or 0)
            except ValueError:
                raise ValueError("a bad Content-Length")
            if self.length < 0:
                raise ValueError("a bad Content-Length")
            self.left = self.length

    def read(self, n=1 << 20):
        """Up to n bytes of it; b"" at its end."""
        if self.chunked:
            if not self.left:
                if self.ended:
                    return b""
                if self.left == 0:
                    self.rfile.readline(8)              # (the line end after a chunk)
                line = self.rfile.readline(1024)
                if not line:
                    raise ConnectionError("the upload stopped")
                size = int(line.split(b";")[0].strip() or b"x", 16)
                if size == 0:
                    while self.rfile.readline(1024) not in (b"\r\n", b"\n", b""):
                        pass                            # (trailers)
                    self.ended = True
                    return b""
                self.left = size
        elif self.left <= 0:
            return b""
        data = self.rfile.read(min(n, self.left))
        if not data:
            raise ConnectionError("the upload stopped")
        self.left -= len(data)
        return data

    def pieces(self):
        while data := self.read():
            yield data

    def all(self, most):
        """The whole body, if it's at most `most` bytes (else None)."""
        out = b""
        for data in self.pieces():
            out += data
            if len(out) > most:
                return None
        return out


class Multipart:
    """A multipart/form-data body (what the share sheet sends), read as it comes:
    for name, file_name in form.parts(), then that part's data with form.data()."""

    def __init__(self, body, boundary):
        self.body = body
        self.delimiter = b"\r\n--" + boundary
        self.buffer = b"\r\n"           # (so the first boundary looks like the others)

    def more(self):
        data = self.body.read()
        if not data:
            raise ValueError("the form ended early")
        self.buffer += data

    def data(self):
        """The current part's data, in pieces, up to the next boundary."""
        keep = len(self.delimiter) - 1
        while True:
            i = self.buffer.find(self.delimiter)
            if i >= 0:
                if i:
                    yield self.buffer[:i]
                self.buffer = self.buffer[i:]
                return
            if len(self.buffer) > keep:
                yield self.buffer[:-keep]
                self.buffer = self.buffer[-keep:]
            self.more()

    def parts(self):
        for _ in self.data():               # (anything before the first part)
            pass
        start = len(self.delimiter)
        while True:
            while len(self.buffer) < start + 2:
                self.more()
            if self.buffer[start:start + 2] == b"--":
                return                      # (the last boundary)
            while (end := self.buffer.find(b"\r\n\r\n", start)) < 0:
                if len(self.buffer) > 65536:
                    raise ValueError("a form part's headers are too long")
                self.more()
            head = self.buffer[start:end].decode("utf-8", "replace")
            self.buffer = self.buffer[end + 4:]
            disposition = next((line.split(":", 1)[1] for line in head.split("\r\n")
                                if line.lower().startswith("content-disposition:")), "")
            name = re.search(r'\bname="([^"]*)"', disposition)
            file_name = re.search(r'\bfilename="([^"]*)"', disposition)
            yield (name[1] if name else ""), (file_name[1].replace("%22", '"') if file_name else None)
            for _ in self.data():           # (whatever of it wasn't read)
                pass


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
        # Android: "Shared Box" in the share sheet, once it's installed: text, links and
        # files (any kind)
        "share_target": {"action": "/share", "method": "POST", "enctype": "multipart/form-data",
                         "params": {"title": "title", "text": "text", "url": "url",
                                    "files": [{"name": "file", "accept": ["*/*"]}]}},
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
        body = html.escape(f"From {source}, in {shown}")
        # (the file itself, in its app; the island shows "default" as the click, not a button)
        actions = [("default", "Open"), ("file", "Open")]
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
        elif action == "file" and kind == "file":
            target = item["path"]
        elif action == "open" and url:
            target = url[0]
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
        if self.command != "HEAD" and body:     # (nothing more to write, for a redirect)
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

    def from_here(self):
        """Sent from your own device (its share sheet, or this page), not by a page
        somewhere else (the share sheet can't send the X-Shared-Box header)."""
        site = self.headers.get("Sec-Fetch-Site")
        if site is not None:
            return site in ("none", "same-origin")
        origin = self.headers.get("Origin")         # (browsers from before Sec-Fetch-Site)
        return origin is None or urllib.parse.urlsplit(origin).netloc == self.headers.get("Host")

    def shared_text(self, title, text, url, who):
        content = text
        if url and url not in text:
            content = f"{text}\n{url}".strip()
        content = (content or title)[:MAX_TEXT]
        if content:
            item = text_item(content, who[0])
            self.box.add(item)
            if who[1]:
                notify(item)

    def share(self, query, who):
        """Android's share sheet, as installed apps from before files did it (GET)."""
        if not self.from_here():
            return self.refuse(403, "Share from your own device.")
        q = urllib.parse.parse_qs(query)
        self.shared_text(*(q.get(name, [""])[0].strip() for name in ("title", "text", "url")), who)
        self.send(303, "", "text/plain", [("Location", "/?shared=1")])

    def share_form(self, who):
        """Android's share sheet (the installed app): text, links and files, as a form.
        The files land in Downloads; all of it goes in the box."""
        if not self.from_here():
            return self.refuse(403, "Share from your own device.")
        kind = self.headers.get("Content-Type") or ""
        boundary = re.search(r'boundary="?([^";]+)"?', kind, re.IGNORECASE)
        if not kind.lower().startswith("multipart/form-data") or not boundary:
            return self.refuse(400, "Share it from the share menu.")
        fields, files = {}, 0
        try:
            body = Body(self.rfile, self.headers)
            self.room(body.length)
            form = Multipart(body, boundary[1].encode())
            for name, file_name in form.parts():
                if file_name is None:
                    value = b""
                    for piece in form.data():
                        value += piece
                        if len(value) > 4 * MAX_TEXT:
                            raise ValueError("its text is too long")
                    fields[name] = value.decode("utf-8", "replace").strip()
                elif file_name:                     # (no name: no file chosen)
                    self.take(file_name, form.data(), who)
                    files += 1
        except Exception as e:
            return self.trouble(e)
        self.shared_text(fields.get("title", ""), fields.get("text", ""), fields.get("url", ""), who)
        self.send(303, "", "text/plain", [("Location", f"/?shared=1&files={files}")])

    # ---------- files coming in

    def room(self, length):
        """(Full, if a file of `length` bytes wouldn't leave SPARE free)"""
        if length and shutil.disk_usage(incoming()).free - length < SPARE:
            raise Full()

    def take(self, name, pieces, who):
        """A file from another device: into Downloads (only once it's whole), and the box."""
        part = incoming() / f"{new_id()}.part"
        written = 0
        try:
            fd = os.open(part, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
            with os.fdopen(fd, "wb") as out:
                for piece in pieces:
                    out.write(piece)
                    before, written = written, written + len(piece)
                    if before >> 26 != written >> 26 and shutil.disk_usage(part.parent).free < SPARE:
                        raise Full()            # (checked every 64 MiB, for uploads of unknown size)
            path = place(part, clean_name(name))
        except BaseException:
            part.unlink(missing_ok=True)
            raise
        item = file_item(path, who[0])
        self.box.add(item)
        if who[1]:
            notify(item)
        return item

    def upload(self, who):
        """A file from the page (its Files button, or dropped or pasted on it); the name
        comes URL-encoded in X-File-Name."""
        try:
            body = Body(self.rfile, self.headers)
            self.room(body.length)
            item = self.take(urllib.parse.unquote(self.headers.get("X-File-Name") or ""), body.pieces(), who)
        except Exception as e:
            return self.trouble(e)
        self.json(201, public(item))

    def trouble(self, e):
        """What went wrong with a file coming in, for the device sending it."""
        host = self.tailnet.self_info()["name"]
        try:
            if isinstance(e, Full) or (isinstance(e, OSError) and e.errno == errno.ENOSPC):
                return self.refuse(507, f"There isn't enough space on {host} for it.")
            if isinstance(e, (ValueError, ConnectionError)):
                return self.refuse(400, f"It didn't come through whole ({e}).")
            log("receiving a file:", repr(e))
            return self.refuse(500, f"{host} couldn't save it ({e}).")
        except OSError:
            pass                                # (the device is gone)

    # ---------- POST, DELETE (only from this page or this PC: a page elsewhere can't send
    # the X-Shared-Box header)

    def body(self):
        try:
            data = Body(self.rfile, self.headers).all(4 * MAX_TEXT)
            return json.loads(data) if data else None
        except (ValueError, ConnectionError):
            return None

    def do_POST(self):
        who = self.who()
        if who is None:
            return self.refuse(403, "Only your own devices can use the Shared Box.")
        path = urllib.parse.urlsplit(self.path).path
        if path == "/share":
            return self.share_form(who)
        if self.headers.get("X-Shared-Box") != "1":
            return self.refuse(403, "Only your own devices can use the Shared Box.")
        if path == "/api/files":
            return self.upload(who)
        if path != "/api/items":
            return self.refuse(404, "Not here.")
        data = self.body()
        if not isinstance(data, dict):
            return self.refuse(400, "Send {\"text\": ...}.")
        if "file" in data:
            # (a file on this PC: from this PC only)
            path = data["file"]
            if self.server.remote or not isinstance(path, str) or not os.path.isabs(path) or not os.path.isfile(path):
                return self.refuse(400, "No such file here.")
            item = file_item(path, who[0])
        else:
            text = data.get("text")
            if not isinstance(text, str) or not text.strip():
                return self.refuse(400, "Nothing to send.")
            if len(text) > MAX_TEXT:
                return self.refuse(413, "That's too long for the box (100 000 characters at most).")
            item = text_item(text, who[0])
        self.box.add(item)
        if who[1]:
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
    for part in incoming().glob("*.part"):      # (uploads cut off when it last stopped)
        part.unlink(missing_ok=True)
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


def tell(title, body, transient):
    subprocess.run(["notify-send", "-a", "Shared Box", "-i", str(CACHE / "icon-192.png")]
                   + (["-e"] if transient else []) + ["--", title, html.escape(body)])


def add_files(paths, quiet=False):
    """Files from this PC into the box, for your other devices to download (the
    launcher), with a notification of how it went (quiet: none)."""
    names = []
    for path in paths:
        name = Path(path).name
        try:
            print(call("POST", "/api/items", {"file": os.path.abspath(path)})["id"])
        except SystemExit as e:
            if not quiet:
                tell(f"Couldn't put {name} in the Shared Box", str(e.code), False)
            raise
        names.append(name)
    if quiet:
        return
    tell(f"In the Shared Box: {names[0]}" if len(names) == 1 else f"In the Shared Box: {len(names)} files",
         "Download it on your phone or Mac, in the box" if len(names) == 1
         else "Download them on your phone or Mac, in the box", True)


def copied():
    """The files copied on this PC (Dolphin and other file managers put them on the
    clipboard as file:// addresses), each path ending in a NUL; nothing if it holds
    something else."""
    def paste(*args):
        try:
            return subprocess.run(["wl-paste", *args], capture_output=True, text=True, timeout=3).stdout
        except (OSError, subprocess.TimeoutExpired):
            return ""

    if "text/uri-list" not in paste("--list-types").split():
        return
    for line in paste("--no-newline", "--type", "text/uri-list").splitlines():
        address = urllib.parse.urlsplit(line.strip())
        if address.scheme == "file" and address.netloc in ("", "localhost"):
            path = urllib.parse.unquote(address.path)
            if os.path.isfile(path):
                sys.stdout.write(path + "\0")


def main():
    args = sys.argv[1:]
    command = args[0] if args else ""
    if command == "serve" and len(args) == 1:
        serve()
    elif command == "add" and len(args) >= 2:
        print(call("POST", "/api/items", {"text": " ".join(args[1:])})["id"])
    elif command == "add-file" and len(args) >= 2 and args[1:] != ["--quiet"]:
        quiet = args[1] == "--quiet"
        add_files(args[2:] if quiet else args[1:], quiet)
    elif command == "copied" and len(args) == 1:
        copied()
    elif command == "remove" and len(args) == 2:
        call("DELETE", f"/api/items/{args[1]}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
