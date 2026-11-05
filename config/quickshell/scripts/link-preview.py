#!/usr/bin/env python3
"""Link preview for the launcher's clipboard history.

Fetches the page once (10 s at most, 1 MB of it) and prints JSON: url, site, title,
description, and local copies of its preview image and icon. Results are cached per
link in $XDG_RUNTIME_DIR/quickshell-clipboard/links (private, emptied at logout).

  link-preview.py https://example.com/page
"""

import hashlib
import json
import os
import signal
import sys
from concurrent.futures import ThreadPoolExecutor
import urllib.parse
import urllib.request
from html.parser import HTMLParser

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
EXT = {"image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp",
       "image/svg+xml": "svg", "image/x-icon": "ico", "image/vnd.microsoft.icon": "ico"}

url = sys.argv[1].strip()
cache = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "quickshell-clipboard", "links")
os.makedirs(cache, mode=0o700, exist_ok=True)
key = hashlib.sha1(url.encode()).hexdigest()[:16]
saved = os.path.join(cache, key + ".json")


def fetch(address, limit):
    request = urllib.request.Request(address, headers={"User-Agent": UA, "Accept-Language": "en"})
    with urllib.request.urlopen(request, timeout=5) as response:
        return response.read(limit), response.headers.get_content_type(), \
               response.headers.get_content_charset() or "utf-8", response.geturl()


def keep(address, name, limit):
    """Download an image next to the cache entry; its path, or None."""
    try:
        data, kind, _, _ = fetch(address, limit + 1)
        if len(data) > limit or kind not in EXT:
            return None
        path = os.path.join(cache, f"{key}-{name}.{EXT[kind]}")
        with open(path, "wb") as f:
            f.write(data)
        return path
    except Exception:
        return None


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta, self.icon, self.title, self.in_title = {}, None, "", False

    def handle_starttag(self, tag, attrs):
        a = {k: v or "" for k, v in attrs}
        if tag == "meta":
            name = (a.get("property") or a.get("name") or "").lower()
            if name and "content" in a:
                self.meta.setdefault(name, a["content"].strip())
        elif tag == "link" and "icon" in a.get("rel", "").lower().split() and not self.icon:
            self.icon = a.get("href")
        elif tag == "title":
            self.in_title = True

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title += data


if os.path.exists(saved):
    print(open(saved).read())
    sys.exit()

def give_up(*_):
    raise TimeoutError("took too long")


signal.signal(signal.SIGALRM, give_up)
signal.alarm(10)

parts = urllib.parse.urlparse(url)
result = {"url": url, "site": parts.hostname or ""}
if parts.scheme in ("http", "https"):
    try:
        body, kind, charset, final = fetch(url, 1_000_000)
        if kind in EXT:                          # a link straight to an image
            path = os.path.join(cache, f"{key}-image.{EXT[kind]}")
            with open(path, "wb") as f:
                f.write(body)
            result["image"] = path
        elif "html" in kind:
            page = Page()
            page.feed(body.decode(charset, "replace"))
            m = page.meta
            result["title"] = (m.get("og:title") or m.get("twitter:title") or page.title).strip()
            result["description"] = (m.get("og:description") or m.get("twitter:description") or m.get("description") or "").strip()
            result["site"] = m.get("og:site_name") or result["site"]
            image = m.get("og:image") or m.get("og:image:url") or m.get("twitter:image")
            icon = urllib.parse.urljoin(final, page.icon or "/favicon.ico")
            # the preview image and the icon at the same time
            with ThreadPoolExecutor(2) as pool:
                images = pool.submit(keep, urllib.parse.urljoin(final, image), "image", 5_000_000) if image else None
                icons = pool.submit(keep, icon, "icon", 300_000)
                result["image"] = images.result() if images else None
                result["icon"] = icons.result()
    except Exception as e:
        result["error"] = str(e)

text = json.dumps({k: v for k, v in result.items() if v})
if "error" not in result:      # (failures aren't cached: try again next time)
    with open(saved, "w") as f:
        f.write(text)
print(text)
