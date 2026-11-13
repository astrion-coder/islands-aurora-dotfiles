#!/usr/bin/env python3
"""QR codes in a screenshot (scripts/screenshot.sh), kept for the launcher's QR Codes menu.

  qr-codes.py scan IMAGE   prints the codes in it, in reading order (top to bottom, left
                           to right), each followed by a NUL, and adds them to the list of
                           ones found lately (the newest first; a code seen again moves
                           back to the top)

The list: $XDG_STATE_HOME/quickshell-qr-codes.json (~/.local/state), only readable by
you (codes can hold Wi-Fi passwords), the last 100 codes as
[{"text": ..., "time": seconds since 1970, "shot": the screenshot}, ...].

Codes are read with zbar (zbarimg): dark-on-light ones from the picture, and light-on-dark
ones (dark-themed pages and videos) from a negative of it, made with ImageMagick. Nothing
is printed when zbar isn't installed.
"""

import base64
import json
import os
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

KEEP = 100
NS = "{http://zbar.sourceforge.net/2008/barcode}"
STORE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "quickshell-qr-codes.json"
ZBAR = ["zbarimg", "--nodbus", "--quiet", "--xml", "-Sdisable", "-Sqrcode.enable"]


def symbols(xml):
    """(top, left, text) for each code in zbarimg's XML."""
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    found = []
    for symbol in root.iter(NS + "symbol"):
        data = symbol.find(NS + "data")
        if data is None or data.text is None:
            continue
        text = data.text
        if data.get("format") == "base64":
            try:
                text = base64.b64decode(text).decode("utf-8")
            except ValueError:
                continue
        polygon = symbol.find(NS + "polygon")       # "+225,+125 +225,+272 ..."
        points = polygon.get("points", "") if polygon is not None else ""
        xy = [tuple(int(v) for v in p.split(",")) for p in points.split()] or [(0, 0)]
        found.append((min(y for _, y in xy), min(x for x, _ in xy), text))
    return found


def scan(image):
    if not shutil.which("zbarimg"):
        return []
    found = symbols(subprocess.run(ZBAR + [image], capture_output=True, text=True).stdout)
    if shutil.which("magick"):
        negative = subprocess.run(["magick", image, "-colorspace", "gray", "-negate", "pgm:-"], capture_output=True)
        if negative.returncode == 0:
            found += symbols(subprocess.run(ZBAR + ["pgm:-"], input=negative.stdout, capture_output=True).stdout.decode())
    # reading order: rows (codes whose tops are within 40 px count as one row), then across
    found.sort(key=lambda s: (s[0] // 40, s[1]))
    codes = []
    for _, _, text in found:
        if text not in codes:
            codes.append(text)
    return codes


def remember(codes, image):
    try:
        known = json.loads(STORE.read_text())
    except (OSError, ValueError):
        known = []
    now = int(time.time())
    fresh = [{"text": c, "time": now, "shot": image} for c in codes]
    known = fresh + [k for k in known if isinstance(k, dict) and k.get("text") not in codes]
    STORE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STORE.with_name(STORE.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(known[:KEEP], f, ensure_ascii=False)
    os.replace(tmp, STORE)


def main():
    if len(sys.argv) != 3 or sys.argv[1] != "scan":
        sys.exit(__doc__)
    image = os.path.abspath(sys.argv[2])
    codes = scan(image)
    if codes:
        remember(codes, image)
    for code in codes:
        sys.stdout.write(code + "\0")


if __name__ == "__main__":
    main()
