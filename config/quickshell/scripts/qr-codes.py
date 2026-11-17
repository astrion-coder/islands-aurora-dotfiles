#!/usr/bin/env python3
"""QR codes and links in a screenshot (scripts/screenshot.sh), kept for the launcher's
Links & QR Codes menu.

  qr-codes.py scan IMAGE   prints what's in it, in reading order (top to bottom, left to
                           right): for each, "qr" (a QR code) or "text" (a link written in
                           the picture), a tab, the code or link, and a NUL. It adds them
                           to the list of ones found lately (the newest first; one seen
                           again moves back to the top).

The list: $XDG_STATE_HOME/quickshell-qr-codes.json (~/.local/state), only readable by
you (codes can hold Wi-Fi passwords), the last 100 as
[{"text": ..., "from": "qr" or "text", "time": seconds since 1970, "shot": the screenshot}, ...].

QR codes are read with zbar (zbarimg): dark-on-light ones from the picture, and
light-on-dark ones (dark-themed pages and videos) from a negative of it, made with
ImageMagick. Links are read with tesseract (English: tesseract-data-eng), from a grey
copy of the picture at twice the size (small screen text reads far better that way), at
the same time. Each is skipped when it isn't installed.
"""

import base64
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

KEEP = 100
NS = "{http://zbar.sourceforge.net/2008/barcode}"
STORE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "quickshell-qr-codes.json"
ZBAR = ["zbarimg", "--nodbus", "--quiet", "--xml", "-Sdisable", "-Sqrcode.enable"]
READING = 8         # seconds the text may take before it's given up on (QR codes still show)

# Links written without http(s):// count when they end in one of these (so file names
# like README.md, install.sh or config.py don't), and their name part is in lower case
TLDS = set("""com org net edu gov mil int io dev app ai co me in uk de fr it es nl eu ru jp
cn br au ca us ch se no fi dk at be cz tw kr hk sg nz za ie pt gr tr ua il mx ar cl vn th
my ph pk bd lk np id info biz xyz tech site online store blog shop page land link news
cloud live pro gg tv fm ly to gl""".split())
HOST = r"(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+([a-z]{2,})"
BARE = re.compile(rf"^(?:www\.)?{HOST}(?::\d{{1,5}})?(?:[/?#]\S*)?$")
WITH_SCHEME = re.compile(r"^https?://[^\s/?#]+\.[^\s/?#]+(?:[/?#]\S*)?$|^https?://localhost(?::\d+)?(?:[/?#]\S*)?$",
                         re.IGNORECASE)


# ---------------------------------------------------------------- QR codes

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
        found.append((min(y for _, y in xy), min(x for x, _ in xy), "qr", text))
    return found


def qr_codes(image):
    if not shutil.which("zbarimg"):
        return []
    found = symbols(subprocess.run(ZBAR + [image], capture_output=True, text=True).stdout)
    if shutil.which("magick"):
        negative = subprocess.run(["magick", image, "-colorspace", "gray", "-negate", "pgm:-"], capture_output=True)
        if negative.returncode == 0:
            found += symbols(subprocess.run(ZBAR + ["pgm:-"], input=negative.stdout, capture_output=True).stdout.decode())
    return found


# ---------------------------------------------------------------- links in the text

def size(image):
    """(width, height) of a PNG (grim's screenshots), or None."""
    try:
        with open(image, "rb") as f:
            head = f.read(24)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            return struct.unpack(">II", head[16:24])
    except OSError:
        pass
    return None


def start_reading(image):
    """Start reading the picture's words (tesseract, in the background), or None.
    Returns (scale, the processes): the words come back as tesseract's TSV."""
    if not (shutil.which("tesseract") and shutil.which("magick")):
        return None
    w, h = size(image) or (1920, 1080)
    scale = 2 if w * h <= 2560 * 1600 else 1        # (a bigger screen's text is bigger already)
    # (8-bit grey: tesseract misreads ImageMagick's default 16-bit; one thread is about as
    # fast as all of them, and leaves the rest of the computer alone)
    grey = subprocess.Popen(["magick", image, "-colorspace", "gray", "-resize", f"{scale * 100}%", "-depth", "8", "pgm:-"],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    read = subprocess.Popen(["tesseract", "stdin", "stdout", "--psm", "11", "-l", "eng", "-c", "tessedit_create_tsv=1"],
                            stdin=grey.stdout, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            env=dict(os.environ, OMP_THREAD_LIMIT="1"))
    grey.stdout.close()
    return scale, (grey, read)


def link(word):
    """The link a word is (with https:// added when it's written without), or None."""
    w = word.strip("([{<\"'“‘")
    # trailing punctuation, and closing brackets that don't close one in the link
    while w:
        if w[-1] in ".,;:!?\"'”’>":
            w = w[:-1]
        elif w[-1] in ")]}" and w.count({")": "(", "]": "[", "}": "{"}[w[-1]]) < w.count(w[-1]):
            w = w[:-1]
        else:
            break
    # (a few common misreadings)
    w = re.sub(r"^(https?):/(?=[^/])", r"\1://", w, flags=re.IGNORECASE)
    w = re.sub(r"^(https?)//", r"\1://", w, flags=re.IGNORECASE)
    w = re.sub(r"^((?:https?://)?[^/?#\s]+)\.(?:con|corn|c0m)(?=$|[/?#:])", r"\1.com", w, flags=re.IGNORECASE)
    if WITH_SCHEME.match(w):
        return w
    m = BARE.match(w)
    if m and m[1] in TLDS and "@" not in w:
        return "https://" + w
    return None


def text_links(reading):
    """(top, left, "text", link) for each link in the words read."""
    if reading is None:
        return []
    scale, (grey, read) = reading
    try:
        out, _ = read.communicate(timeout=READING)
    except subprocess.TimeoutExpired:
        grey.kill()
        read.kill()
        return []
    grey.wait()
    lines = {}
    for row in out.decode("utf-8", "replace").splitlines()[1:]:
        f = row.split("\t")
        if len(f) < 12 or f[0] != "5" or not f[11].strip():
            continue
        try:
            if float(f[10]) < 20:                   # (noise)
                continue
            left, top = int(f[6]) // scale, int(f[7]) // scale
        except ValueError:
            continue
        lines.setdefault((f[2], f[3], f[4]), []).append([top, left, f[11]])
    found = []
    for words in lines.values():
        # "https://" read apart from the rest: one word again
        for i in range(len(words) - 1, 0, -1):
            if re.search(r"https?:/{0,2}$", words[i - 1][2], re.IGNORECASE):
                words[i - 1][2] += words.pop(i)[2]
        for top, left, word in words:
            url = link(word)
            if url:
                found.append((top, left, "text", url))
    return found


# ---------------------------------------------------------------- both

def scan(image):
    reading = start_reading(image)                  # (the text is read while QR codes are)
    found = qr_codes(image) + text_links(reading)
    # reading order: rows (tops within 40 px count as one row), then across; a link that's
    # also a QR code (or written twice) once, where it's first seen
    found.sort(key=lambda s: (s[0] // 40, s[1]))
    items, where = [], {}
    for _, _, kind, text in found:
        key = text.rstrip("/").lower() if re.match(r"https?://", text, re.IGNORECASE) else text
        if key not in where:
            where[key] = len(items)
            items.append((kind, text))
        elif kind == "qr":                          # (the QR code's text, exactly as it is)
            items[where[key]] = (kind, text)
    return items


def remember(items, image):
    try:
        known = json.loads(STORE.read_text())
    except (OSError, ValueError):
        known = []
    now = int(time.time())
    texts = {text for _, text in items}
    fresh = [{"text": text, "from": kind, "time": now, "shot": image} for kind, text in items]
    known = fresh + [k for k in known if isinstance(k, dict) and k.get("text") not in texts]
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
    items = scan(image)
    if items:
        remember(items, image)
    for kind, text in items:
        sys.stdout.write(f"{kind}\t{text}\0")


if __name__ == "__main__":
    main()
