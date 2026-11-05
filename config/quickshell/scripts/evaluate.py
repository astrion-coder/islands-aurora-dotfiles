#!/usr/bin/env python3
"""Evaluate what was typed in the launcher's main menu (Enter on text matching nothing).

Prints six lines for the answer card (quickshell/launcher): title, query, query
caption, answer, answer caption, value to copy. Prints nothing if the text isn't a
time conversion or maths.

  15:39 utc              -> local time
  3pm est to tokyo       -> time in another zone ("in" works too)
  9:00 to london         -> local time elsewhere
  now in new york        -> current time there ("time in ..." works too)
  15 oct aoe             -> AoE deadline in local time (date without time = 23:59),
                            with a countdown; "oct 15 5pm aoe to london", "2026-10-15 aoe"
  7 * 6, 5 km to miles   -> maths / units via qalc
  100 usd, 20 eur        -> currency to rupees (LOCAL_CURRENCY) when no target is given
"""

import json
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, available_timezones

# Common abbreviations (GNU/zoneinfo names are ambiguous or missing for many of these)
ABBREVIATIONS = {
    "utc": "UTC", "gmt": "UTC", "z": "UTC",
    "ist": "Asia/Kolkata",
    "est": "America/New_York", "edt": "America/New_York", "et": "America/New_York",
    "cst": "America/Chicago", "cdt": "America/Chicago", "ct": "America/Chicago",
    "mst": "America/Denver", "mdt": "America/Denver", "mt": "America/Denver",
    "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pt": "America/Los_Angeles",
    "bst": "Europe/London", "cet": "Europe/Paris", "cest": "Europe/Paris",
    "eet": "Europe/Athens", "msk": "Europe/Moscow", "gst": "Asia/Dubai",
    "sgt": "Asia/Singapore", "hkt": "Asia/Hong_Kong", "jst": "Asia/Tokyo",
    "kst": "Asia/Seoul", "aest": "Australia/Sydney", "aedt": "Australia/Sydney",
    "nzst": "Pacific/Auckland", "nzdt": "Pacific/Auckland",
}
LOCAL = datetime.now().astimezone().tzinfo
AOE = timezone(timedelta(hours=-12), "AoE")   # Anywhere on Earth: UTC-12 (deadlines)

TIME = r"(?P<h>\d{1,2})(?::(?P<m>\d{2}))?\s*(?P<ampm>am|pm)?"
MONTH = r"(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*"
DATE = (rf"(?:(?P<iso>\d{{4}}-\d{{2}}-\d{{2}})"
        rf"|(?P<d1>\d{{1,2}})(?:st|nd|rd|th)?\s+(?P<m1>{MONTH})"
        rf"|(?P<m2>{MONTH})\s+(?P<d2>\d{{1,2}})(?:st|nd|rd|th)?)")
ZONE = r"[a-z][a-z_/ +\-]*?"


def zone(name):
    """Resolve 'utc', 'tokyo', 'new york', 'Europe/Paris', 'local' to a tzinfo."""
    key = name.strip().lower()
    if key in ("local", "here", "my time"):
        return LOCAL
    if key in ("aoe", "anywhere on earth"):
        return AOE
    if key in ABBREVIATIONS:
        return ZoneInfo(ABBREVIATIONS[key])
    city = key.replace(" ", "_")
    for tz in available_timezones():
        low = tz.lower()
        if low == city or low.rsplit("/", 1)[-1] == city:
            return ZoneInfo(tz)
    return None


def label(dt):
    z = dt.strftime("%Z")
    return z if not z.startswith(("+", "-", "UTC-", "UTC+")) or z == "AoE" else dt.strftime("UTC%z")


def parse_date(m, tz):
    """Date from a DATE match (this year; next year if it's long past), or None."""
    if m["iso"]:
        return datetime.strptime(m["iso"], "%Y-%m-%d").date()
    if not (m["m1"] or m["m2"]):
        return None
    day, month = int(m["d1"] or m["d2"]), (m["m1"] or m["m2"])[:3]
    today = datetime.now(tz).date()
    d = datetime.strptime(f"{day} {month} {today.year}", "%d %b %Y").date()
    return d.replace(year=today.year + 1) if (today - d).days > 180 else d


def countdown(when):
    """'in 15d 4h' / 'passed 2d 3h ago' relative to now."""
    secs = (when - datetime.now(timezone.utc)).total_seconds()
    left = abs(int(secs)) // 60
    d, h, mins = left // 1440, left % 1440 // 60, left % 60
    span = f"{d}d {h}h" if d else (f"{h}h {mins}m" if h else f"{mins}m")
    return f"in {span}" if secs >= 0 else f"passed {span} ago"


def day_note(src, dst):
    delta = (dst.date() - src.date()).days
    return {1: ", the next day", -1: ", the day before"}.get(delta, "")


def where(dt, is_local, place=""):
    """How a time's zone reads on the card: 'UTC', 'Tokyo (JST)', 'your time (IST)'."""
    if is_local:
        return f"your time ({label(dt)})"
    return f"{place} ({label(dt)})" if place else label(dt)


def convert(text):
    t = text.strip().lower()

    m = re.fullmatch(rf"(?:now|time)\s+in\s+(?P<to>{ZONE})", t)
    if m:
        dst_tz = zone(m["to"])
        if not dst_tz:
            return None
        here, there = datetime.now(LOCAL), datetime.now(dst_tz)
        place = m["to"].strip().title() if len(m["to"].strip()) > 4 else ""
        return ("Time zones",
                f"{here:%H:%M}", where(here, True),
                f"{there:%H:%M}", f"{where(there, False, place)}, {there:%a %-d %b}",
                f"{there:%H:%M}")

    m = re.fullmatch(rf"(?:{DATE}\s*,?\s*)?(?:{TIME})?"
                     rf"(?:\s+(?!(?:to|in)\s)(?P<from>{ZONE}))?(?:\s+(?:to|in)\s+(?P<to>{ZONE}))?", t)
    if not m or not (m["from"] or m["to"]):
        return None
    dated = bool(m["iso"] or m["m1"] or m["m2"])
    if not dated and not m["h"]:
        return None
    # a bare date is a deadline: 23:59 that day
    hour, minute = (int(m["h"]), int(m["m"] or 0)) if m["h"] else (23, 59)
    if m["ampm"]:
        hour = hour % 12 + (12 if m["ampm"] == "pm" else 0)
    if hour > 23 or minute > 59:
        return None
    src_tz = zone(m["from"]) if m["from"] else LOCAL
    dst_tz = zone(m["to"]) if m["to"] else LOCAL
    if not src_tz or not dst_tz:
        return None

    today = datetime.now(src_tz)
    src = today.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if dated:
        d = parse_date(m, src_tz)
        src = src.replace(year=d.year, month=d.month, day=d.day)
    dst = src.astimezone(dst_tz)
    place = m["to"].strip().title() if m["to"] and len(m["to"].strip()) > 4 else ""
    src_where = where(src, src_tz is LOCAL)
    dst_where = where(dst, dst_tz is LOCAL, place)
    if dated:   # deadline: show both dates and the time left
        return (f"Deadline {countdown(src)}",
                f"{src:%H:%M}", f"{src:%a %-d %b}, {src_where}",
                f"{dst:%H:%M}", f"{dst:%a %-d %b}, {dst_where}",
                f"{dst:%a %-d %b %H:%M}")
    return ("Time zones",
            f"{src:%H:%M}", src_where,
            f"{dst:%H:%M}", dst_where + day_note(src, dst),
            f"{dst:%H:%M}")


QALC_DIRS = [Path.home() / ".local/share/qalculate", Path("/usr/share/qalculate")]
# Local currency: amounts typed without a target ("100 usd") convert to this, like times
# without a target zone convert to local time
LOCAL_CURRENCY = "inr"
LOCAL_CURRENCY_NAMES = {"inr", "₹", "rupee", "rupees"}


def currency_names():
    """Lower-case currency codes/names qalc knows (USD, inr, euro, €, ...)."""
    names = set()
    for d in QALC_DIRS:
        try:
            names |= {k.lower() for k in json.loads((d / "rates.json").read_text()).get("eur", {})}
        except (OSError, ValueError):
            pass
    try:
        xml = (QALC_DIRS[1] / "currencies.xml").read_text()
        for entry in re.findall(r"<names>([^<]+)</names>", xml):     # default-language names only
            names |= {n.split(":")[-1].lower() for n in entry.split(",") if n}
    except OSError:
        pass
    return names - {"", "-"}


def rates_date():
    """Date of the newest exchange rates qalc has (downloaded by qalc-rates.timer, or bundled)."""
    dates = []
    for d in QALC_DIRS:
        try:
            dates.append(json.loads((d / "rates.json").read_text())["date"])
        except (OSError, ValueError, KeyError):
            pass
        try:
            dates += re.findall(r"time=['\"](\d{4}-\d{2}-\d{2})['\"]", (d / "eurofxref-daily.xml").read_text())
        except OSError:
            pass
    return datetime.strptime(max(dates), "%Y-%m-%d") if dates else None


def maths(text):
    words = set(re.findall(r"[^\W\d_]+|[$€£¥₹]", text.lower()))
    names = currency_names()
    # "100 usd" (no target): convert to the local currency
    local_default = bool(re.search(r"\d", text) and words & names
                         and not re.search(r" to | in ", text) and not words & LOCAL_CURRENCY_NAMES)
    if local_default:
        text = f"{text} to {LOCAL_CURRENCY}"
    # digits plus an operator or a unit conversion; plain words go to qalc as units
    if not (re.search(r"\d", text) and re.search(r"[-+*/^%()]| to | in ", text)):
        return None
    expr = text
    # "5 km to miles": answer in plain miles, not "3 mi + 188 yd + ..." (qalc: "-unit")
    head, sep, unit = text.rpartition(" to ")
    if sep and not unit.lstrip().startswith("-"):
        expr = f"{head} to -{unit.strip()}"
    currency = bool(sep and words & names) or local_default
    # 8 significant digits: readable on the card (3.1068560 mi, not 3.106855961 mi);
    # money is shown to exactly 2 decimals (₹95.27)
    opts = ["-set", "precision 8"]
    if currency:
        opts += ["-set", "max decimals 2", "-set", "min decimals 2"]
    out = subprocess.run(["qalc", "-t", *opts, expr], capture_output=True, text=True).stdout.strip()
    if not out:
        return None
    answer = out.splitlines()[0]
    pretty = text.replace("*", "×").replace("/", "÷")
    if sep:
        caption = unit.strip() + (" (your currency)" if local_default else "")
        # currency: say how old the exchange rates are (qalc-rates.timer refreshes them daily)
        if currency:
            when = rates_date()
            if when:
                caption += f", rates from {when:%-d %b}"
        return "Conversion", head.strip(), "from", answer, caption, answer
    return "Calculation", pretty, "question", answer, "answer", answer


if __name__ == "__main__":
    text = " ".join(sys.argv[1:])
    result = convert(text) or maths(text)
    if result:
        print(*result, sep="\n")
