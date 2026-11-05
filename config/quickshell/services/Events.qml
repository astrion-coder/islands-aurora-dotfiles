pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Your calendars, through khal: the folders of .ics files in ~/.local/share/calendars/
// (kept in step with your Mac and phone by vdirsyncer once you've run
// scripts/calendar-sync-setup.sh). scripts/calendar-events.py does the work: listing (khal),
// adding, moving, changing, deleting, undoing, syncing. The island's calendar
// (bar/Calendar.qml) shows them and is where you change them; what you do shows there at
// once, before it's written (the next look puts what's really there back, should the
// write fail). The island announces each event 10 minutes before it starts and again
// when it does. The calendar sync timer says when it has pulled something in:
//   qs ipc call calendar refresh
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/calendar-events.py")
    readonly property var repeats: ["", "weekly", "monthly", "yearly"]

    property bool missing: false        // khal isn't installed
    property var calendars: []          // [{ name, color }]
    property var byDay: ({})            // "yyyy-MM-dd" -> [{ uid, title, start, end, allDay, repeat, freq, calendar, ... }]
    property var today: []              // today's, for the reminders
    property bool syncing: false
    property var range: null            // [first, last] the calendar shows
    property bool hold: false           // an event is being dragged: no new looks meanwhile

    signal failed(string what)          // a change couldn't be made ("move", "undo", ...)

    // ---------------------------------------------------------------- dates

    function key(d) {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function dayOf(d) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }

    function on(d) {
        return byDay[key(d)] ?? [];
    }

    function dateOf(k) {
        const [y, m, d] = k.split("-").map(Number);
        return new Date(y, m - 1, d);
    }

    function plusDays(d, n) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
    }

    function daysBetween(a, b) {
        return Math.round((dayOf(b) - dayOf(a)) / 86400000);
    }

    // an event as you'd type it: "09:30–10:00 Standup", or just the title (all day)
    function describe(e) {
        return e.start ? e.start + (e.end ? "–" + e.end : "") + " " + e.title : e.title;
    }

    function colorOf(calendar) {
        return calendars.find(c => c.name === calendar)?.color ?? "";
    }

    // ---------------------------------------------------------------- reading

    // the calendar shows `days` days from `start`
    function show(start, days) {
        range = [key(start), key(new Date(start.getFullYear(), start.getMonth(), start.getDate() + days))];
        refresh();
    }

    function refresh() {
        if (missing) {
            khalCheck.running = true;     // (installed since? it refreshes again if so)
            return;
        }
        if (range)
            run(lister, ["list", range[0], range[1]]);
        const now = new Date();
        run(todayLister, ["list", key(now), key(new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1))]);
        run(calendarLister, ["calendars"]);
    }

    // (a process already running goes again when it's done, with the latest arguments;
    // "when it's done" is just after its exited signal, which comes while it still counts
    // as running)
    function run(process, args) {
        process.next = [root.script].concat(args);
        if (!process.running)
            again(process);
    }

    function again(process) {
        if (process.next && !process.running) {
            process.command = process.next;
            process.next = null;
            process.stamp = root.stamp;
            process.running = true;
        }
    }

    // bumps with each change shown before it's written, and again once it's written: a
    // look started before either is out of date (and so is one that finishes while a
    // change is still being written)
    property int stamp: 0
    property string lastList: ""

    Process {
        id: lister
        property var next: null
        property int stamp: 0
        onExited: Qt.callLater(() => root.again(lister))
        stdout: StdioCollector {
            onStreamFinished: {
                if (lister.stamp !== root.stamp || root.writing || root.hold)
                    return;
                if (text === root.lastList)
                    return;             // (the same: the list isn't rebuilt)
                try {
                    root.byDay = JSON.parse(text || "{}");
                    root.lastList = text;
                } catch (e) {}
            }
        }
    }
    onHoldChanged: if (!hold) refresh()

    Process {
        id: todayLister
        property var next: null
        property int stamp: 0
        onExited: Qt.callLater(() => root.again(todayLister))
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.today = JSON.parse(text || "{}")[root.key(new Date())] ?? [];
                } catch (e) {}
            }
        }
    }

    Process {
        id: calendarLister
        property var next: null
        property int stamp: 0
        onExited: Qt.callLater(() => root.again(calendarLister))
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.calendars = JSON.parse(text || "[]");
                } catch (e) {}
            }
        }
    }

    // is khal there? (again each time the calendar looks, while it isn't)
    Process {
        id: khalCheck
        running: true
        command: ["sh", "-c", "command -v khal"]
        onExited: code => {
            const was = root.missing;
            root.missing = code !== 0;
            if (!root.missing || !was)
                root.refresh();
        }
    }

    // now and then (other changes: your Mac, the phone, khal in a terminal)
    Timer {
        interval: 5 * 60000
        running: !root.missing
        repeat: true
        onTriggered: root.refresh()
    }

    // ---------------------------------------------------------------- changing

    // What's shown, changed straight away: `f(day, event)` gives where the event goes now,
    // as [[day, event], ...] (none: gone). Days that get something new are put in order:
    // all day first, then by time.
    function reshape(f) {
        const out = {}, touched = {};
        for (const k in byDay) {
            out[k] = out[k] ?? [];
            for (const e of byDay[k])
                for (const [nk, ne] of f(k, e)) {
                    (out[nk] = out[nk] ?? []).push(ne);
                    if (nk !== k || ne !== e)
                        touched[nk] = true;
                }
        }
        for (const k in touched)
            out[k] = out[k].slice().sort(inOrder);
        shown(out);
    }

    function insert(k, e) {
        shown(Object.assign({}, byDay, { [k]: (byDay[k] ?? []).concat([e]).sort(inOrder) }));
    }

    function inOrder(a, b) {
        return (b.allDay - a.allDay) || (a.start || "").localeCompare(b.start || "");
    }

    function shown(days) {
        stamp++;
        lastList = "";
        byDay = days;
    }

    function plusHour(hhmm) {
        const [h, m] = hhmm.split(":").map(Number);
        return String((h + 1) % 24).padStart(2, "0") + ":" + String(m).padStart(2, "0");
    }

    // "14:30 Dentist", "9am standup", "2:30pm-3pm call", "14:00 to 15:30 review" or just
    // "Birthday" (all day), into `calendar` (a name from `calendars`). False if there's
    // no title.
    function add(d, text, repeat, calendar) {
        const e = parse(text);
        if (e.title === "" || !calendar)
            return false;
        const k = key(d);
        insert(k, { uid: "", title: e.title, start: e.time, end: e.time ? e.end || plusHour(e.time) : "",
                    allDay: e.time === "", repeat: !!repeat, freq: repeat ?? "", calendar: calendar, pending: true });
        change(["add", calendar, k, e.time, e.end, repeat ?? "", e.title]);
        return true;
    }

    // The event `e` as it is on day `from`, onto day `to` at the same time. scope: "one"
    // (a repeating event: only that day's), "all" (the series moves along) or "copy".
    function move(e, from, to, scope) {
        const days = daysBetween(from, to), fromKey = key(from);
        reshape((k, x) => {
            if (x.uid !== e.uid)
                return [[k, x]];
            if (scope === "copy")
                return k === fromKey ? [[k, x], [key(plusDays(dateOf(k), days)), Object.assign({}, x, { uid: "", repeat: false, freq: "", pending: true })]] : [[k, x]];
            if (scope === "one" && e.repeat && k !== fromKey)
                return [[k, x]];
            return [[key(plusDays(dateOf(k), days)), x]];
        });
        change(["move", e.uid, fromKey, key(to), scope]);
    }

    // `text` as typed ("09:30-10:00 Standup", "Birthday"), how often it repeats and its
    // calendar ("-": as they are). A repeating event changes as a whole. Says "changed",
    // "same" (nothing to change) or "empty" (no title).
    function edit(e, text, repeat, calendar) {
        const p = parse(text);
        if (p.title === "")
            return "empty";
        // (the times as they were: kept; a day an event only continues on has none)
        const same = e.allDay ? p.time === "" : (!e.start && p.time === "") || (p.time === e.start && (p.end === "" || p.end === e.end));
        const start = same ? "-" : p.time, end = same ? "" : p.end;
        const title = p.title === e.title ? "" : p.title;
        if (start === "-" && title === "" && repeat === "-" && calendar === "-")
            return "same";
        reshape((k, x) => {
            if (x.uid !== e.uid)
                return [[k, x]];
            const y = Object.assign({}, x);
            if (title !== "")
                y.title = title;
            if (start !== "-") {
                y.allDay = start === "";
                y.start = start;
                y.end = start ? end || plusHour(start) : "";
            }
            if (repeat !== "-") {
                y.repeat = repeat !== "";
                y.freq = repeat;
            }
            if (calendar !== "-")
                y.calendar = calendar;
            return [[k, y]];
        });
        change(["edit", e.uid, title, start, end, repeat, calendar]);
        return "changed";
    }

    // scope "all" (all of it), or "one": only day `d`'s, of a repeating event
    function remove(e, d, scope) {
        const k = key(d), one = scope === "one" && e.repeat;
        reshape((day, x) => x.uid === e.uid && (!one || day === k) ? [] : [[day, x]]);
        change(one ? ["delete", e.uid, k] : ["delete", e.uid]);
    }

    // the last change, put back as it was
    function undo() {
        change(["undo"]);
    }

    // one change at a time, each followed by a fresh look and a sync
    property var changes: []
    readonly property bool writing: writer.running || changes.length > 0
    function change(args) {
        changes = changes.concat([args]);
        if (!writer.running)
            writeNext();
    }
    function writeNext() {
        if (changes.length === 0)
            return;
        writer.what = changes[0][0];
        writer.command = [root.script].concat(changes[0]);
        changes = changes.slice(1);
        writer.running = true;
    }

    Process {
        id: writer
        property string what
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("calendar:", text.trim())
        }
        onExited: code => {
            if (code !== 0)
                root.failed(writer.what);
            Qt.callLater(root.written);
        }
    }

    // the next change, or (all written) a fresh look and a sync
    function written() {
        stamp++;
        if (changes.length > 0) {
            writeNext();
        } else {
            refresh();
            sync(true);
        }
    }

    // ---------------------------------------------------------------- syncing

    // (when the island opens, at most once a minute; right away after a change)
    property real lastSync: 0
    function sync(now) {
        if (missing || (!now && Date.now() - lastSync < 60000))
            return;
        lastSync = Date.now();
        if (syncer.running)
            syncer.again = true;
        else
            syncer.running = true;
    }

    Process {
        id: syncer
        property bool again: false
        command: [root.script, "sync"]
        onRunningChanged: root.syncing = running
        onExited: {
            root.refresh();
            if (again)
                Qt.callLater(() => {
                    syncer.again = false;
                    syncer.running = true;
                });
        }
    }

    // ---------------------------------------------------------------- typing an event

    function parse(text) {
        const t = text.trim();
        const time = "(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm)?";
        const m = t.match(new RegExp("^" + time + "(?:\\s*(?:-|–|to)\\s*" + time + ")?\\s+(.+)$", "i"));
        // (a bare number isn't a time: "3 kids' party"; but "9-10am gym" is)
        if (m && (m[2] !== undefined || m[3] || (m[4] && (m[5] !== undefined || m[6])))) {
            let start = clock(m[1], m[2], m[3] || m[6]);
            const end = m[4] ? clock(m[4], m[5], m[6] || m[3]) : "";
            // "11-1pm": the am/pm only goes with the end
            if (!m[3] && m[6] && end !== "" && start > end)
                start = clock(m[1], m[2], m[6].toLowerCase() === "pm" ? "am" : "pm");
            if (start !== "")
                return { time: start, end: end, title: m[7].trim() };
        }
        return { time: "", end: "", title: t };
    }

    function clock(h, min, ampm) {
        let hours = Number(h);
        const minutes = Number(min ?? 0);
        if (ampm) {
            const pm = ampm.toLowerCase() === "pm";
            if (hours < 1 || hours > 12)
                return "";
            hours = hours % 12 + (pm ? 12 : 0);
        }
        if (hours > 23 || minutes > 59)
            return "";
        return String(hours).padStart(2, "0") + ":" + String(minutes).padStart(2, "0");
    }

    IpcHandler {
        target: "calendar"

        // (after the calendar sync timer has pulled in changes: calendar-sync.service)
        function refresh(): void {
            root.refresh();
        }
    }

    // ---------------------------------------------------------------- reminders

    property var announced: ({})

    Timer {
        interval: 15000
        running: root.today.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date();
            for (const e of root.today) {
                if (!e.start || e.allDay)
                    continue;
                const [h, m] = e.start.split(":").map(Number);
                const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), h, m);
                const id = (e.uid || e.title) + root.key(now) + e.start;
                const until = start - now;
                if (until <= 10 * 60000 && until > 9 * 60000 && !root.announced[id + "soon"]) {
                    root.announced[id + "soon"] = true;
                    Activities.show({ kind: "message", icon: "calendar", title: e.title, detail: "in 10 minutes, at " + e.start }, 8000);
                } else if (until <= 0 && until > -60000 && !root.announced[id]) {
                    root.announced[id] = true;
                    Activities.show({ kind: "message", icon: "calendar", title: e.title, detail: e.end ? "now, until " + e.end : "now" }, 10000);
                }
            }
        }
    }
}
