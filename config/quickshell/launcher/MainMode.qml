import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// The main menu: commands and apps together, like Raycast. Hidden keywords (meta) let
// partial words match ("paste" finds Clipboard History). Apps you open often come first.
// Enter on text that matches nothing works it out (maths, units, currency, time zones,
// AoE deadlines) and shows the answer, copied.
Mode {
    id: root

    prompt: "search"

    readonly property var commands: [
        { title: "Clipboard History", icon: "edit-paste", menu: "clipboard", meta: "clipboard clip paste copy history" },
        { title: "Search Emoji", icon: "face-smile", menu: "emoji", meta: "emoji emoticon smiley symbol" },
        { title: "Search Files", icon: "system-search", menu: "files", meta: "files find folder documents open" },
        { title: "Calculator", icon: "accessories-calculator", menu: "calc", meta: "calculator calc math convert units" },
        { title: "Switch Windows", icon: "preferences-system-windows", menu: "windows", meta: "windows switch window focus" },
        { title: "Screenshot", icon: "camera-photo", menu: "screenshot", meta: "screenshot screen capture snip grab print picture" },
        { title: "Record Screen", icon: "media-record", menu: "record", meta: "record recording screen video capture screencast" },
        { title: "Change Wallpaper", icon: "preferences-desktop-wallpaper", menu: "wallpaper", meta: "wallpaper background desktop picture image theme colours colors" },
        { title: "Lock Screen", icon: "system-lock-screen", action: "lock", meta: "lock" },
        { title: "Log Out", icon: "system-log-out", action: "logout", meta: "logout log out exit session" },
        { title: "Suspend", icon: "system-suspend", action: "suspend", meta: "suspend sleep" },
        { title: "Reboot", icon: "system-reboot", action: "reboot", meta: "reboot restart" },
        { title: "Shut Down", icon: "system-shutdown", action: "poweroff", meta: "shutdown shut down power off poweroff" }
    ]

    // how often each app was opened (by desktop id), kept between sessions
    property var uses: ({})
    FileView {
        id: usesFile
        path: Quickshell.statePath("launcher-uses.json")
        printErrors: false
        onLoaded: {
            try {
                root.uses = JSON.parse(text());
            } catch (e) {}
        }
    }

    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)
        .map(a => ({
            title: a.name,
            icon: a.icon,
            entry: a,
            meta: [a.genericName, ...(a.keywords ?? [])].filter(k => k).join(" | "),
            boost: Math.log2(1 + (uses[a.id] ?? 0)) * 4
        }))
        .sort((a, b) => b.boost - a.boost || a.title.localeCompare(b.title))

    rows: Fuzzy.filter(commands.concat(apps), query)

    property bool working: false
    property bool nothing: false     // the last Enter on unmatched text had no answer
    hint: working ? "working it out…" : nothing ? "no answer for that" : ""
    onQueryChanged: nothing = false

    function launch(entry) {
        if (entry.runInTerminal)
            Quickshell.execDetached(["kitty", "-e", ...entry.command]);
        else
            entry.execute();
        const u = Object.assign({}, uses);
        u[entry.id] = (u[entry.id] ?? 0) + 1;
        uses = u;
        usesFile.setText(JSON.stringify(u));
    }

    function activate(row, how) {
        if (!row) {
            if (query.trim() !== "") {
                working = true;
                evaluate.command = [Quickshell.shellPath("scripts/evaluate.py"), query];
                evaluate.running = true;
            }
            return;
        }
        if (row.menu) {
            Launcher.enter(row.menu);
        } else if (row.action) {
            Launcher.system(row.action);
        } else if (row.entry) {
            Launcher.close();
            launch(row.entry);
        }
    }

    // six lines: title, query, caption, answer, caption, value to copy
    Process {
        id: evaluate
        stdout: StdioCollector {
            onStreamFinished: {
                root.working = false;
                const f = text.split("\n");
                if (f.length < 6 || f[5] === "") {
                    root.nothing = true;
                    return;
                }
                Quickshell.execDetached(["wl-copy", "--", f[5]]);
                Launcher.answer = f.slice(0, 5);
                Launcher.answerValue = f[5];
                Launcher.enter("answer");
            }
        }
    }
}
