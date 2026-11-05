#!/usr/bin/env python3
"""The island calendar's helper (bar/Calendar.qml, through services/Events.qml).

Your calendars are folders of .ics files under ~/.local/share/calendars/, one folder per
calendar (kept in step with your Mac and phone by vdirsyncer, once you've run
calendar-sync-setup.sh). khal reads them; changes are written into them here, touching
only the lines that change (everything else in a file, your Mac's own fields included,
stays as it was).

  calendar-events.py calendars       the calendars, as JSON: [{"name", "color"}]
  calendar-events.py list START END  the events of each day from START to END (dates,
                                     yyyy-mm-dd), as JSON: {"2026-11-02": [event, ...]}
  calendar-events.py add CALENDAR DATE START END REPEAT TITLE
                                     START and END "HH:MM", or "" (END: an hour after
                                     START; both: all day); REPEAT "", "weekly",
                                     "monthly" or "yearly"
  calendar-events.py move UID FROM TO SCOPE
                                     the event as it is on day FROM, onto day TO, at the
                                     same time; SCOPE "one" (of a repeating event, only
                                     that day's), "all" (the whole series moves along)
                                     or "copy" (a new event, not repeating)
  calendar-events.py edit UID TITLE START END REPEAT CALENDAR
                                     TITLE "" keeps it; START "-" keeps the times, ""
                                     makes it all day, "HH:MM" (END as for add) sets
                                     them; REPEAT and CALENDAR "-" keep them. A repeating
                                     event changes as a whole
  calendar-events.py delete UID [DAY]
                                     all of it; with DAY, only that day's (of a
                                     repeating event)
  calendar-events.py undo            the last change made here, put back as it was
  calendar-events.py sync            with the calendar server, if sync is set up
"""

import base64
import copy
import datetime as dt
import fcntl
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from zoneinfo import ZoneInfo

HOME = Path.home()
ROOT = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share") / "calendars"
VDIRSYNCER = HOME / ".config/vdirsyncer/config"
LOCK = HOME / ".local/share/vdirsyncer/lock"
UNDO = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "calendar-undo.json"
SEP = "\x1f"
UTC = dt.timezone.utc
DAY = dt.timedelta(days=1)
WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


class Problem(Exception):
    pass


def local_zone():
    name = os.environ.get("TZ", "").lstrip(":")
    if not name:
        target = os.path.realpath("/etc/localtime")
        name = target.split("/zoneinfo/", 1)[1] if "/zoneinfo/" in target else ""
    try:
        return ZoneInfo(name)
    except Exception:
        return dt.datetime.now().astimezone().tzinfo


LOCAL = local_zone()


# ---------------------------------------------------------------- calendars

def ensure():
    """Make sure there's at least one calendar (khal needs one)."""
    ROOT.mkdir(parents=True, exist_ok=True)
    if not any(d.is_dir() and not d.name.startswith(".") for d in ROOT.iterdir()):
        (ROOT / "personal").mkdir()
        (ROOT / "personal" / "displayname").write_text("Personal")


def meta(d, key):
    f = d / key
    return f.read_text().strip() if f.is_file() else ""


def calendars():
    """Each calendar's folder, and its name as khal shows it (its displayname)."""
    ensure()
    out = []
    for d in sorted(ROOT.iterdir()):
        if d.is_dir() and not d.name.startswith("."):
            out.append({"name": meta(d, "displayname") or d.name, "color": meta(d, "color"), "dir": d})
    return out


def calendar_called(name):
    cal = next((c for c in calendars() if name in (c["name"], c["dir"].name)), None)
    if cal is None:
        raise Problem(f"no calendar called {name}")
    return cal


# ---------------------------------------------------------------- the files

def unescape(value):
    return re.sub(r"\\(.)", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


def escape(text):
    return text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def fold(line):
    """Content lines are at most 75 bytes; longer ones continue on lines starting with a space."""
    out, cur, size = [], "", 0
    for ch in line:
        n = len(ch.encode())
        if size + n > (75 if not out else 74):
            out.append(cur)
            cur, size = "", 0
        cur += ch
        size += n
    out.append(cur)
    return "\r\n ".join(out)


def prop_name(line):
    return re.match(r"[^;:]*", line).group(0).upper()


def split(line):
    """NAME;PARAMS:VALUE -> ("NAME", ";PARAMS", "VALUE") (a quoted parameter can hold a colon)."""
    name = re.match(r"[^;:]*", line).group(0)
    i, quoted = len(name), False
    while i < len(line):
        if line[i] == '"':
            quoted = not quoted
        elif line[i] == ":" and not quoted:
            break
        i += 1
    return name.upper(), line[len(name):i], line[i + 1:]


def param(params, key):
    m = re.search(r";" + key + r'=("[^"]*"|[^;:]*)', params, re.I)
    return m.group(1).strip('"') if m else ""


def is_prop(item, name):
    return isinstance(item, str) and prop_name(item) == name


class Component:
    """BEGIN:NAME ... END:NAME: its property lines (unfolded) and components, in order."""

    def __init__(self, name):
        self.name = name
        self.items = []

    def comps(self, name=None):
        return [i for i in self.items if isinstance(i, Component) and (name is None or i.name == name)]

    def lines(self, name):
        return [i for i in self.items if is_prop(i, name)]

    def get(self, name):
        found = self.lines(name)
        return found[0] if found else None

    def value(self, name):
        line = self.get(name)
        return split(line)[2] if line else ""

    def text(self, name):
        return unescape(self.value(name)).strip()

    def time(self, name):
        line = self.get(name)
        if not line:
            return None
        _, params, value = split(line)
        return Time.read(params, value.split(",")[0])

    def end_of_props(self):
        return next((n for n, i in enumerate(self.items) if isinstance(i, Component)), len(self.items))

    def set(self, name, line):
        """Replace the property (all of its lines) with `line`, or add it."""
        found = [n for n, i in enumerate(self.items) if is_prop(i, name)]
        if found:
            self.items[found[0]] = line
            for n in reversed(found[1:]):
                del self.items[n]
        else:
            self.items.insert(self.end_of_props(), line)

    def add(self, line):
        self.items.insert(self.end_of_props(), line)

    def remove(self, *names):
        self.items = [i for i in self.items if not (isinstance(i, str) and prop_name(i) in names)]


def parse(text):
    root, stack = Component(""), []
    stack.append(root)
    for line in re.sub(r"\r?\n[ \t]", "", text).splitlines():
        upper = line.upper()
        if not line.strip():
            continue
        if upper.startswith("BEGIN:"):
            c = Component(line[6:].strip().upper())
            stack[-1].items.append(c)
            stack.append(c)
        elif upper.startswith("END:") and len(stack) > 1:
            stack.pop()
        else:
            stack[-1].items.append(line)
    return root


def lines_of(c):
    out = [f"BEGIN:{c.name}"] if c.name else []
    for i in c.items:
        out += lines_of(i) if isinstance(i, Component) else [i]
    if c.name:
        out.append(f"END:{c.name}")
    return out


def dump(root):
    return "".join(fold(line) + "\r\n" for line in lines_of(root))


def vevents(root):
    return [e for cal in root.comps("VCALENDAR") for e in cal.comps("VEVENT")]


class Event:
    """One event's file: its calendar component, the main event and its changed days."""

    def __init__(self, path, uid):
        self.path = path
        self.root = parse(path.read_text(errors="replace"))
        self.cal = next(c for c in self.root.comps("VCALENDAR") if any(e.value("UID").strip() == uid for e in c.comps("VEVENT")))
        self.events = [e for e in self.cal.comps("VEVENT") if e.value("UID").strip() == uid]
        self.master = next((e for e in self.events if not e.get("RECURRENCE-ID")), None)
        self.overrides = [e for e in self.events if e.get("RECURRENCE-ID")]

    @property
    def repeating(self):
        return self.master is not None and bool(self.master.get("RRULE") or self.master.get("RDATE"))


def files_with(uid):
    pattern = re.compile(r"^UID(;[^:]*)?:" + re.escape(uid) + r"\s*$", re.M | re.I)
    out = []
    for f in sorted(ROOT.glob("*/*.ics")):
        try:
            if pattern.search(re.sub(r"\r?\n[ \t]", "", f.read_text(errors="replace"))):
                out.append(f)
        except OSError:
            pass
    return out


def load(uid):
    found = files_with(uid)
    if not found:
        raise Problem(f"no event with UID {uid}")
    return Event(found[0], uid)


# ---------------------------------------------------------------- times

def zone_named(tzid):
    try:
        return ZoneInfo(tzid)
    except Exception:
        return LOCAL


class Time:
    """A DTSTART-like value: its kind ("date", "floating", "tz" or "utc"), the wall-clock
    time it names (naive; midnight for a date), the zone that clock is in, and the
    parameters it's written with."""

    def __init__(self, kind, wall, zone, params):
        self.kind, self.wall, self.zone, self.params = kind, wall, zone, params

    @classmethod
    def read(cls, params, value):
        value = value.strip()
        if param(params, "VALUE").upper() == "DATE" or re.fullmatch(r"\d{8}", value):
            return cls("date", dt.datetime.strptime(value[:8], "%Y%m%d"), LOCAL, params)
        wall = dt.datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
        if value.upper().endswith("Z"):
            return cls("utc", wall, UTC, params)
        tzid = param(params, "TZID")
        if tzid:
            return cls("tz", wall, zone_named(tzid), params)
        return cls("floating", wall, LOCAL, params)

    def text(self):
        if self.kind == "date":
            return self.wall.strftime("%Y%m%d")
        return self.wall.strftime("%Y%m%dT%H%M%S") + ("Z" if self.kind == "utc" else "")

    def line(self, name):
        return f"{name}{self.params}:{self.text()}"

    def at(self, wall):
        return Time(self.kind, wall, self.zone, self.params)

    def local(self):
        """The local wall-clock time (naive)."""
        if self.kind == "date":
            return self.wall
        return self.wall.replace(tzinfo=self.zone).astimezone(LOCAL).replace(tzinfo=None)

    def in_zone(self, other):
        """This time on `other`'s wall clock (naive), to compare with its values."""
        if other.kind == "date":
            return dt.datetime.combine(self.local().date(), dt.time())
        if self.kind == "date":
            return dt.datetime.combine(self.wall.date(), other.wall.time())
        return self.wall.replace(tzinfo=self.zone).astimezone(other.zone).replace(tzinfo=None)

    def moved(self, days):
        """`days` days later on the local clock (the same time of day where you are)."""
        if self.kind == "utc":
            t = self.local() + dt.timedelta(days=days)
            return self.at(t.replace(tzinfo=LOCAL).astimezone(UTC).replace(tzinfo=None))
        return self.at(self.wall + dt.timedelta(days=days))


def same(a, b):
    return a is not None and b is not None and a.local() == b.local()


def duration(text):
    m = re.fullmatch(r"([+-]?)P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", text.strip())
    if not m:
        return dt.timedelta(0)
    w, d, h, mi, s = (int(x or 0) for x in m.groups()[1:])
    return dt.timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)


def length(ev, start):
    end = ev.time("DTEND")
    if end is not None:
        return end.in_zone(start) - start.wall
    if ev.get("DURATION"):
        return duration(ev.value("DURATION"))
    return DAY if start.kind == "date" else dt.timedelta(0)


def covers(start, span, day):
    """Does an event from `start` lasting `span` show on `day` (a local date)?"""
    first = start.local()
    if start.kind == "date":
        last = first + max(span, DAY) - DAY
    else:
        end = start.at(start.wall + span).local()
        last = end - dt.timedelta(microseconds=1) if end > first else first
    return first.date() <= day <= last.date()


def occurrences(master, start, around, span):
    """The repeating event's starts (on its own wall clock) near `around` (a date)."""
    from dateutil import rrule as rr

    def until(match):
        v = match.group(1)
        if v.upper().endswith("Z"):
            t = Time("utc", dt.datetime.strptime(v[:15], "%Y%m%dT%H%M%S"), UTC, "")
            return "UNTIL=" + t.in_zone(start).strftime("%Y%m%d" if start.kind == "date" else "%Y%m%dT%H%M%S")
        if len(v) == 8 and start.kind != "date":
            return "UNTIL=" + v + "T235959"
        return match.group(0)

    rules = rr.rruleset()
    try:
        for line in master.lines("RRULE"):
            rules.rrule(rr.rrulestr(re.sub(r"UNTIL=([0-9TZz]+)", until, split(line)[2], flags=re.I), dtstart=start.wall))
    except (ValueError, TypeError) as e:
        raise Problem(f"can't read how it repeats: {e}")
    rules.rdate(start.wall)
    for name, add in (("RDATE", rules.rdate), ("EXDATE", rules.exdate)):
        for line in master.lines(name):
            _, params, value = split(line)
            if param(params, "VALUE").upper() != "PERIOD":
                for v in value.split(","):
                    add(Time.read(params, v).in_zone(start))
    centre = dt.datetime.combine(around, dt.time())
    return rules.between(centre - span - 3 * DAY, centre + 3 * DAY, inc=True)


def occurrence(e, day):
    """A repeating event as it is on `day` (a date): (its changed copy, None) if that day's
    one has been changed already, else (None, its start on the event's wall clock)."""
    for ov in e.overrides:
        s = ov.time("DTSTART")
        if s is not None and covers(s, length(ov, s), day):
            return ov, None
    start = e.master.time("DTSTART")
    span = length(e.master, start)
    taken = {ov.time("RECURRENCE-ID").in_zone(start) for ov in e.overrides}
    for wall in occurrences(e.master, start, day, span):
        if wall not in taken and covers(start.at(wall), span, day):
            return None, wall
    raise Problem("couldn't find that day's one of it")


# ---------------------------------------------------------------- changing

def touch(ev):
    """Changed: a new sequence number and time stamp, so your Mac takes the new version."""
    now = dt.datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    seq = ev.value("SEQUENCE").strip()
    ev.set("SEQUENCE", f"SEQUENCE:{int(seq) + 1 if seq.isdigit() else 1}")
    ev.set("DTSTAMP", f"DTSTAMP:{now}")
    ev.set("LAST-MODIFIED", f"LAST-MODIFIED:{now}")


def shift(ev, days, *names):
    """Move these properties' times (all their values) `days` days on."""
    for n, item in enumerate(ev.items):
        if isinstance(item, str) and prop_name(item) in names:
            name, params, value = split(item)
            if param(params, "VALUE").upper() == "PERIOD":
                continue
            ev.items[n] = f"{name}{params}:" + ",".join(Time.read(params, v).moved(days).text() for v in value.split(","))


def fresh(comp):
    """A copy, its reminders with new ids (each reminder's id has to be its own)."""
    c = copy.deepcopy(comp)

    def walk(x):
        if x.name == "VALARM":
            new = str(uuid.uuid4()).upper()
            for key in ("UID", "X-WR-ALARMUID"):
                if x.get(key):
                    x.set(key, f"{key}:{new}")
        for child in x.comps():
            walk(child)

    walk(c)
    return c


def copy_of(ev, skip):
    out = Component("VEVENT")
    for item in ev.items:
        if isinstance(item, Component):
            out.items.append(fresh(item))
        elif prop_name(item) not in skip:
            out.items.append(item)
    return out


def detach(master, wall):
    """One day's occurrence of a repeating event, as its own changed copy."""
    start = master.time("DTSTART")
    ov = copy_of(master, {"RRULE", "RDATE", "EXDATE", "EXRULE", "DTSTART", "DTEND", "RECURRENCE-ID",
                          "DTSTAMP", "SEQUENCE", "CREATED", "LAST-MODIFIED"})
    occ = start.at(wall)
    ov.set("RECURRENCE-ID", occ.line("RECURRENCE-ID"))
    ov.set("DTSTART", occ.line("DTSTART"))
    if master.get("DTEND"):
        ov.set("DTEND", start.at(wall + length(master, start)).line("DTEND"))
    ov.set("SEQUENCE", master.get("SEQUENCE") or "SEQUENCE:0")
    return ov


def follow_rule(master, days):
    """After a whole series moved `days` days: its rule's weekday / day of the month
    follows (a weekly Monday event moved to Tuesday repeats on Tuesdays)."""
    line = master.get("RRULE")
    if not line:
        return
    name, params, value = split(line)
    start = master.time("DTSTART").wall
    freq = re.search(r"FREQ=(\w+)", value, re.I)
    freq = freq.group(1).upper() if freq else ""
    parts = []
    for part in value.split(";"):
        key, eq, v = part.partition("=")
        k = key.upper()
        if k == "BYDAY":
            out = []
            for item in v.split(","):
                m = re.fullmatch(r"([+-]?\d*)([A-Za-z]{2})", item.strip())
                if not m or m.group(2).upper() not in WEEKDAYS:
                    out.append(item)
                    continue
                n, code = m.groups()
                code = WEEKDAYS[(WEEKDAYS.index(code.upper()) + days) % 7]
                if n and freq in ("MONTHLY", "YEARLY"):
                    last_week = (start + dt.timedelta(days=7)).month != start.month
                    n = "-1" if n.startswith("-") and last_week else str((start.day - 1) // 7 + 1)
                out.append(n + code)
            v = ",".join(out)
        elif k == "BYMONTHDAY" and re.fullmatch(r"\d+", v):
            v = str(start.day)
        elif k == "BYMONTH" and re.fullmatch(r"\d+", v) and freq == "YEARLY":
            v = str(start.month)
        elif k == "UNTIL":
            v = Time.read("", v).moved(days).text()
        parts.append(f"{key}{eq}{v}")
    master.set("RRULE", f"{name}{params}:{';'.join(parts)}")


def retimed(start, day, begin, finish):
    """New start and end for an event on `day` (a local date): all day (begin ""), or
    from `begin` to `finish` ("HH:MM"; "": an hour later), in the event's own zone."""
    if begin == "":
        b = dt.datetime.combine(day, dt.time())
        return Time("date", b, LOCAL, ";VALUE=DATE"), Time("date", b + DAY, LOCAL, ";VALUE=DATE")
    b = dt.datetime.combine(day, dt.time.fromisoformat(begin))
    f = dt.datetime.combine(day, dt.time.fromisoformat(finish)) if finish else b + dt.timedelta(hours=1)
    if f <= b:
        f += DAY                                    # past midnight
    if start.kind in ("tz", "utc"):
        params = start.params if start.kind == "tz" else ""
        conv = [w.replace(tzinfo=LOCAL).astimezone(start.zone).replace(tzinfo=None) for w in (b, f)]
        return Time(start.kind, conv[0], start.zone, params), Time(start.kind, conv[1], start.zone, params)
    # local ("floating") times: it happens at that time wherever you are
    return Time("floating", b, LOCAL, ""), Time("floating", f, LOCAL, "")


def save(changes):
    """Write each file (bytes, or a parsed calendar; None deletes it), keeping what was
    there for `undo`."""
    before = {str(p): base64.b64encode(p.read_bytes()).decode() if p.exists() else None for p in changes}
    for path, content in changes.items():
        if content is None:
            path.unlink(missing_ok=True)
            continue
        data = content if isinstance(content, bytes) else dump(content).encode()
        tmp = path.with_name("." + path.name + ".tmp")
        tmp.write_bytes(data)
        tmp.rename(path)
    try:
        stack = json.loads(UNDO.read_text())
    except (OSError, ValueError):
        stack = []
    UNDO.write_text(json.dumps((stack + [before])[-30:]))


# ---------------------------------------------------------------- listing (khal)

def details():
    """Each event's description, location, link, calendar (by its folder) and how often
    it repeats, by UID, read from the files themselves (khal's list puts one event per
    line, and descriptions can have many)."""
    names = {c["dir"]: c["name"] for c in calendars()}
    out = {}
    for f in ROOT.glob("*/*.ics"):
        try:
            events = vevents(parse(f.read_text(errors="replace")))
        except OSError:
            continue
        for ev in events:
            uid = ev.value("UID").strip()
            # (a changed occurrence of a repeating event shares the UID: keep the main one)
            if not uid or (uid in out and ev.get("RECURRENCE-ID")):
                continue
            freq = re.search(r"FREQ=(\w+)", ev.value("RRULE"), re.I)
            out[uid] = {
                "description": ev.text("DESCRIPTION"),
                "location": ev.text("LOCATION"),
                "url": ev.text("URL"),
                "calendar": names.get(f.parent, ""),
                "freq": freq.group(1).lower() if freq else "",
            }
    return out


FIELDS = ["uid", "title", "start-time", "end-time", "all-day", "repeat-pattern", "calendar"]


def khal_list(start, end, fields):
    fmt = SEP.join("{%s}" % f for f in fields)
    return subprocess.run(
        ["khal", "list", "--format", fmt, "--day-format", "@@{date}", start, end],
        capture_output=True, text=True, timeout=60)


def cmd_list(start, end):
    ensure()
    fields = FIELDS
    try:
        r = khal_list(start, end, fields)
    except FileNotFoundError:
        sys.stderr.write("khal isn't installed: sudo pacman -S khal\n")
        print("{}")
        return 1
    if r.returncode != 0 and "uid" in r.stderr:     # (a khal without {uid})
        fields = [f for f in FIELDS if f != "uid"]
        r = khal_list(start, end, fields)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        print("{}")
        return 1
    more = details()
    days, day = {}, None
    for line in r.stdout.splitlines():
        if line.startswith("@@"):
            day = line[2:].strip()
            days.setdefault(day, [])
        elif day and SEP in line:
            e = dict(zip(fields, line.split(SEP)))
            extra = more.get(e.get("uid", ""), {})
            days[day].append({
                "uid": e.get("uid", ""),
                "title": e.get("title", ""),
                "start": e.get("start-time", ""),
                "end": e.get("end-time", ""),
                "allDay": e.get("all-day", "") == "True",
                "repeat": e.get("repeat-pattern", "") != "",
                "freq": extra.get("freq", ""),
                "calendar": extra.get("calendar") or e.get("calendar", ""),
                "description": extra.get("description", ""),
                "location": extra.get("location", ""),
                "url": extra.get("url", ""),
            })
    print(json.dumps(days))
    return 0


# ---------------------------------------------------------------- the commands

def cmd_add(calendar, date, start, end, repeat, title):
    cal = calendar_called(calendar)
    day = dt.date.fromisoformat(date)
    uid = str(uuid.uuid4()).upper()
    now = dt.datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Islands Aurora//calendar//EN",
             "BEGIN:VEVENT", f"UID:{uid}", f"DTSTAMP:{now}", f"CREATED:{now}"]
    begin, finish = retimed(Time("floating", None, LOCAL, ""), day, start, end)
    lines += [begin.line("DTSTART"), finish.line("DTEND")]
    if repeat in ("weekly", "monthly", "yearly"):
        lines.append(f"RRULE:FREQ={repeat.upper()}")
    lines += [fold("SUMMARY:" + escape(title)), "END:VEVENT", "END:VCALENDAR"]
    save({cal["dir"] / f"{uid}.ics": ("\r\n".join(lines) + "\r\n").encode()})
    print(uid)
    return 0


def cmd_move(uid, frm, to, scope):
    if scope not in ("one", "all", "copy"):
        raise Problem(f"move: SCOPE is one, all or copy, not {scope}")
    e = load(uid)
    day = dt.date.fromisoformat(frm)
    days = (dt.date.fromisoformat(to) - day).days
    if scope == "copy":
        return copy_event(e, day, days)
    if days == 0:
        return 0
    if not e.repeating:
        for ev in e.events:
            shift(ev, days, "DTSTART", "DTEND")
            touch(ev)
    elif scope == "all":
        shift(e.master, days, "DTSTART", "DTEND", "EXDATE", "RDATE")
        follow_rule(e.master, days)
        touch(e.master)
        for ov in e.overrides:
            unmoved = same(ov.time("RECURRENCE-ID"), ov.time("DTSTART"))
            shift(ov, days, "RECURRENCE-ID", *(("DTSTART", "DTEND") if unmoved else ()))
            touch(ov)
    else:
        ov, wall = occurrence(e, day)
        if ov is None:
            ov = detach(e.master, wall)
            e.cal.items.insert(e.cal.items.index(e.master) + 1, ov)
        shift(ov, days, "DTSTART", "DTEND")
        touch(ov)
    save({e.path: e.root})
    return 0


def copy_event(e, day, days):
    """A copy of the event as it is on `day`, `days` days on: a new event of its own."""
    src, wall = None, None
    if e.repeating:
        src, wall = occurrence(e, day)
    src = src or e.master or e.events[0]
    start = src.time("DTSTART")
    span = length(src, start)
    if wall is not None:
        start = start.at(wall)
    new = copy_of(src, {"UID", "RRULE", "RDATE", "EXDATE", "EXRULE", "RECURRENCE-ID", "DTSTART", "DTEND",
                        "DTSTAMP", "SEQUENCE", "CREATED", "LAST-MODIFIED", "ATTENDEE", "ORGANIZER"})
    uid = str(uuid.uuid4()).upper()
    now = dt.datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    begin = start.moved(days)
    new.items.insert(0, f"UID:{uid}")
    new.set("DTSTART", begin.line("DTSTART"))
    if src.get("DTEND"):
        new.set("DTEND", begin.at(begin.wall + span).line("DTEND"))
    for line in (f"CREATED:{now}", f"DTSTAMP:{now}", f"LAST-MODIFIED:{now}", "SEQUENCE:0"):
        new.set(prop_name(line), line)
    cal = Component("VCALENDAR")
    for item in e.cal.items:
        if isinstance(item, str):
            cal.items.append(item)
        elif item.name == "VTIMEZONE":
            cal.items.append(copy.deepcopy(item))
    cal.items.append(new)
    root = Component("")
    root.items.append(cal)
    save({e.path.parent / f"{uid}.ics": root})
    print(uid)
    return 0


def cmd_edit(uid, title, begin, finish, repeat, calendar):
    if repeat not in ("-", "", "weekly", "monthly", "yearly"):
        raise Problem(f"edit: REPEAT is -, \"\", weekly, monthly or yearly, not {repeat}")
    e = load(uid)
    m = e.master or e.events[0]
    changed = []

    def mark(ev):
        if not any(ev is c for c in changed):
            changed.append(ev)

    old = m.text("SUMMARY")
    if title and title != old:
        for ev in e.events:
            if ev is m or ev.text("SUMMARY") == old:
                ev.set("SUMMARY", "SUMMARY:" + escape(title))
                mark(ev)

    start = m.time("DTSTART")
    # (all day already: kept as it is, however many days)
    if begin != "-" and start is not None and not (begin == "" and start.kind == "date"):
        new_start, new_end = retimed(start, start.local().date(), begin, finish)
        for ov in e.overrides:
            rid, s = ov.time("RECURRENCE-ID"), ov.time("DTSTART")
            unmoved = same(rid, s)
            ns, ne = retimed(start, rid.local().date(), begin, finish)
            ov.set("RECURRENCE-ID", ns.line("RECURRENCE-ID"))
            if unmoved:
                ov.set("DTSTART", ns.line("DTSTART"))
                ov.set("DTEND", ne.line("DTEND"))
                ov.remove("DURATION")
            mark(ov)
        for n, item in enumerate(m.items):
            if is_prop(item, "EXDATE"):
                _, params, value = split(item)
                skipped = [retimed(start, Time.read(params, v).local().date(), begin, finish)[0] for v in value.split(",")]
                m.items[n] = f"EXDATE{skipped[0].params}:" + ",".join(t.text() for t in skipped)
        m.set("DTSTART", new_start.line("DTSTART"))
        m.set("DTEND", new_end.line("DTEND"))
        m.remove("DURATION")
        mark(m)

    if repeat == "" and e.repeating:
        m.remove("RRULE", "RDATE", "EXDATE", "EXRULE")
        e.cal.items = [i for i in e.cal.items if not any(i is ov for ov in e.overrides)]
        mark(m)
    elif repeat not in ("-", ""):
        m.set("RRULE", f"RRULE:FREQ={repeat.upper()}")
        mark(m)

    target = e.path
    if calendar not in ("-", ""):
        target = calendar_called(calendar)["dir"] / e.path.name
    for ev in changed:
        touch(ev)
    if not changed and target == e.path:
        return 0
    changes = {target: e.root}
    if target != e.path:
        changes[e.path] = None          # (into the other calendar's folder)
    save(changes)
    return 0


def cmd_delete(uid, day=None):
    if day:
        e = load(uid)
        if e.repeating:
            ov, wall = occurrence(e, dt.date.fromisoformat(day))
            start = e.master.time("DTSTART")
            if ov is not None:
                skipped = start.at(ov.time("RECURRENCE-ID").in_zone(start))
                e.cal.items = [i for i in e.cal.items if i is not ov]
            else:
                skipped = start.at(wall)
            e.master.add(skipped.line("EXDATE"))
            touch(e.master)
            save({e.path: e.root})
            print(1)
            return 0
    gone = files_with(uid)
    if gone:
        save({f: None for f in gone})
    print(len(gone))
    return 0 if gone else 1


def cmd_undo():
    try:
        stack = json.loads(UNDO.read_text())
    except (OSError, ValueError):
        stack = []
    if not stack:
        sys.stderr.write("nothing to undo\n")
        return 1
    for path, data in stack.pop().items():
        p = Path(path)
        if data is None:
            p.unlink(missing_ok=True)
        else:
            tmp = p.with_name("." + p.name + ".tmp")
            tmp.write_bytes(base64.b64decode(data))
            tmp.rename(p)
    UNDO.write_text(json.dumps(stack))
    return 0


# ---------------------------------------------------------------- syncing

def cmd_sync():
    if not VDIRSYNCER.is_file():
        return 0
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)     # (not at the same time as the timer's)
        try:
            r = subprocess.run(["vdirsyncer", "-v", "WARNING", "sync"], capture_output=True, text=True, timeout=120)
        except FileNotFoundError:
            sys.stderr.write("vdirsyncer isn't installed: sudo pacman -S vdirsyncer\n")
            return 1
    sys.stderr.write(r.stderr)
    return r.returncode


def main(argv):
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    commands = {
        ("calendars", 0): lambda: print(json.dumps([{"name": c["name"], "color": c["color"]} for c in calendars()])) or 0,
        ("list", 2): lambda: cmd_list(*args),
        ("add", 6): lambda: cmd_add(*args),
        ("move", 4): lambda: cmd_move(*args),
        ("edit", 6): lambda: cmd_edit(*args),
        ("delete", 1): lambda: cmd_delete(*args),
        ("delete", 2): lambda: cmd_delete(*args),
        ("undo", 0): cmd_undo,
        ("sync", 0): cmd_sync,
    }
    run = commands.get((cmd, len(args)))
    if run is None:
        sys.stderr.write(__doc__)
        return 2
    try:
        return run()
    except Problem as e:
        sys.stderr.write(f"calendar: {e}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
