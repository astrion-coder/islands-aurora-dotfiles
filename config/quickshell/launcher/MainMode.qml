import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// The main menu: commands and apps together, like Raycast. Hidden keywords (meta) let
// partial words match ("paste" finds Clipboard History). Apps you open often come first.
// Maths, units, currency, time zones and AoE deadlines are worked out as you type: the
// answer shows above the list (LauncherWindow.qml), picked, so Enter pastes it where you
// were and Alt+1 only copies it.
Mode {
    id: root

    prompt: "search"

    readonly property var commands: [
        { title: "Clipboard History", icon: "edit-paste", menu: "clipboard", meta: "clipboard clip paste copy history" },
        { title: "Search Emoji", icon: "face-smile", menu: "emoji", meta: "emoji emoticon smiley symbol" },
        { title: "Search Files", icon: "system-search", menu: "files", meta: "files find folder documents open" },
        { title: "Calculator", icon: "accessories-calculator", menu: "calc", meta: "calculator calc math convert units" },
        { title: "QR Codes", icon: "view-barcode-qr", menu: "qr", meta: "qr codes scanned screenshot links barcode" },
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

    // (with an answer and nothing else matching the text, the usual list stays under it)
    readonly property var found: Fuzzy.filter(commands.concat(apps), query)
    rows: found.length === 0 && answer !== null ? Fuzzy.filter(commands.concat(apps), "") : found

    // the answer (scripts/evaluate.py): title, query, caption, answer, caption, value to
    // copy; null when the text isn't maths, a conversion, a time or a deadline
    property var answer: null
    property string answerFor: ""    // the text it answers (the one before, while the
                                     // latest is still being worked out)
    property string asked: ""        // the text being worked out
    property string waiting: ""      // Enter came before the answer did: how
    property bool nothing: false     // Enter on text with no answer
    hint: nothing ? "no answer for that" : ""

    onQueryChanged: {
        nothing = false;
        waiting = "";
        if (worthAsking(query)) {
            delay.restart();
        } else {
            delay.stop();
            answer = null;
            answerFor = "";
        }
    }

    // (every answer has a number in it, or is "now in tokyo": apps and commands are
    // searched without starting the evaluator for each key)
    function worthAsking(text) {
        return /\d/.test(text) || /^\s*(now|time)\s+in\s+\S/i.test(text);
    }

    function ask() {
        const text = query.trim();
        if (!worthAsking(text))
            return;
        if (evaluate.running) {
            delay.restart();             // (still on the text before: in a moment)
            return;
        }
        asked = text;
        evaluate.command = [Quickshell.shellPath("scripts/evaluate.py"), text];
        evaluate.running = true;
    }

    // Enter (how: "enter", or "alt" to only copy it) on the answer, or on text that
    // matches nothing: paste it where you were, once it's the answer to what's typed now
    function useAnswer(how) {
        const text = query.trim();
        if (answer && answerFor === text) {
            Launcher.deliver('wl-copy -- "$1"', answer[5], how === "alt");
        } else if (worthAsking(text)) {
            waiting = how;
            delay.stop();
            ask();
        } else {
            nothing = text !== "";
        }
    }

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
            useAnswer(how);
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

    // (a moment after the last key, so a fast typist doesn't start one for every key)
    Timer {
        id: delay
        interval: 60
        onTriggered: root.ask()
    }

    // six lines: title, query, caption, answer, caption, value to copy (or nothing).
    // (Answers to text that's since changed are dropped: the new text is asked next.)
    Process {
        id: evaluate
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.asked !== root.query.trim())
                    return;
                const f = text.split("\n");
                root.answer = f.length >= 6 && f[5] !== "" ? f.slice(0, 6) : null;
                root.answerFor = root.asked;
                const how = root.waiting;
                root.waiting = "";
                if (how !== "" && root.answer)
                    root.useAnswer(how);
                else if (how !== "")
                    root.nothing = true;
            }
        }
    }
}
