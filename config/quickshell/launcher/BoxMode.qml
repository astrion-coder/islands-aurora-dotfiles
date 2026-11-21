import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// The Shared Box (scripts/shared-box.py): text, links and files shared with your phone and
// Mac over Tailscale. Type and press Enter to send it to them all (Shift+Enter: and stay
// here); the list is what's in the box, the newest first, and narrows down as you type.
// Enter on one opens a link or a file, or pastes text where you were; Alt+1 only copies it
// (a file: its path); Shift+Delete takes it out of the box, on every device.
// Files: "Send a file…" (on top, before you type) finds one on this PC (the "boxfile" menu,
// FilesMode.qml); files you've copied (Ctrl+C in Dolphin) get a row of their own. Enter
// puts them in the box (Shift+Enter: and stay here); your phone and Mac download them from
// its page. (Also: Ctrl+Enter on a file in the Files menu.)
Mode {
    id: root

    readonly property string file: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share")
                                   + "/shared-box/items.json"
    readonly property string socket: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shared-box-local.sock"
    readonly property string script: Quickshell.shellPath("scripts/shared-box.py")
    property var items: []          // { id, kind: "text" | "link" | "file", text, from, time, path }
    property var copiedFiles: []    // files copied on this PC (Ctrl+C in Dolphin...), from the clipboard
    property bool running: true     // (its socket is there)
    property string problem: ""
    property real now: Date.now()

    prompt: "shared"
    placeholder: "send text or a link to your devices…"
    hint: problem !== "" ? problem
        : !running ? "The Shared Box isn't running: set it up with ~/.config/quickshell/scripts/shared-box-setup.sh"
        : current?.send ? "Enter sends it to all your devices, Shift+Enter sends it and stays here"
        : current?.pick ? "Enter finds a file on this PC to put in the box, for your phone and Mac to download"
        : current?.copied ? "Enter puts " + (copiedFiles.length === 1 ? "it" : "them") + " in the box for your phone and Mac, Shift+Enter: and stays here"
        : current?.item?.kind === "file" ? "Enter opens it, Alt+1 copies its path, Shift+Delete takes it out of the box"
        : current?.item?.kind === "link" ? "Enter opens it, Alt+1 copies it, Shift+Delete takes it out of the box"
        : current ? "Enter pastes it where you were, Alt+1 only copies it, Shift+Delete takes it out of the box"
        : "Type to send text or a link to all your devices"
    // typed text first (to send it), else the ways to send files; then what's in the box
    rows: (query.trim() !== "" ? [{
              send: true,
              title: "Send “" + query.trim().replace(/\s+/g, " ") + "”",
              subtitle: "to all your devices",
              icon: "document-send"
          }] : fileRows).concat(Fuzzy.filter(items.map(row), query, 300))
    readonly property var fileRows: [{
            pick: true,
            title: "Send a file…",
            subtitle: "find one on this PC: your phone and Mac can download it from the box",
            icon: "document-open"
        }].concat(copiedFiles.length === 0 ? [] : [{
            copied: copiedFiles,
            title: copiedFiles.length === 1 ? "Send the copied file “" + copiedFiles[0].split("/").pop() + "”"
                                            : "Send the " + copiedFiles.length + " copied files",
            subtitle: copiedFiles.length === 1 ? copiedFiles[0].replace(Quickshell.env("HOME"), "~")
                                               : copiedFiles.map(f => f.split("/").pop()).join(", "),
            icon: "edit-paste"
        }])

    onQueryChanged: problem = ""

    // "just now", "5 min", "14:05", "yesterday", "12 Nov"
    function when(seconds) {
        const d = new Date(seconds * 1000), today = new Date(now);
        const minutes = (now - d) / 60000;
        if (minutes < 1)
            return "just now";
        if (minutes < 60)
            return Math.floor(minutes) + " min ago";
        const days = Math.round((new Date(today.getFullYear(), today.getMonth(), today.getDate())
                               - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000);
        return days === 0 ? Qt.formatTime(d, "HH:mm") : days === 1 ? "yesterday"
             : Qt.formatDate(d, d.getFullYear() === today.getFullYear() ? "d MMM" : "d MMM yyyy");
    }

    function row(it) {
        return {
            item: it,
            title: it.text.replace(/\s+/g, " ").trim(),
            subtitle: it.from + ", " + when(it.time),
            icon: it.kind === "link" ? "text-html" : it.kind === "file" ? "folder-download" : "text-x-generic",
            meta: it.from + " " + it.kind
        };
    }

    function opened() {
        now = Date.now();
        problem = "";
        store.reload();
        check.running = true;
        copiedFiles = [];
        clipboard.running = true;
    }

    function activate(row, how) {
        if (!row)
            return;
        if (row.send) {
            sender.stay = how === "shift";
            sender.copied = false;
            sender.command = [script, "add", query.trim()];
            sender.running = true;
            return;
        }
        if (row.pick) {
            Launcher.enter("boxfile");
            return;
        }
        if (row.copied) {
            if (how === "shift") {          // (quietly: they show up in the list)
                sender.stay = true;
                sender.copied = true;
                sender.command = [script, "add-file", "--quiet"].concat(row.copied);
                sender.running = true;
            } else {                        // (a notification says how it went)
                Launcher.close();
                Quickshell.execDetached([script, "add-file"].concat(row.copied));
            }
            return;
        }
        const it = row.item;
        if (how === "delete") {
            remover.command = [script, "remove", it.id];
            remover.running = true;
            items = items.filter(i => i.id !== it.id);
        } else if (it.kind === "file") {
            if (how === "alt") {
                Launcher.deliver('wl-copy -- "$1"', it.path, true);
            } else {
                Launcher.close();
                Quickshell.execDetached(["xdg-open", it.path]);
            }
        } else if (it.kind === "link" && how !== "alt") {
            Launcher.close();
            Quickshell.execDetached(["xdg-open", it.text]);
        } else {
            Launcher.deliver('wl-copy -- "$1"', it.text, how === "alt");
        }
    }

    // (written by shared-box.py; read again when it changes)
    FileView {
        id: store
        path: root.file
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const list = JSON.parse(text());
                root.items = Array.isArray(list) ? list.filter(i => i && typeof i.text === "string" && i.id) : [];
            } catch (e) {
                root.items = [];
            }
            root.now = Date.now();
        }
        onLoadFailed: root.items = []
    }

    // what's on the clipboard, if it's files (NUL-separated paths)
    Process {
        id: clipboard
        command: [root.script, "copied"]
        stdout: StdioCollector {
            onStreamFinished: root.copiedFiles = text.split("\0").filter(f => f !== "")
        }
    }

    Process {
        id: check
        command: ["test", "-S", root.socket]
        onExited: code => root.running = code === 0
    }

    Process {
        id: sender
        property bool stay: false
        property bool copied: false     // (the copied files: their row goes, once they're in)
        stderr: StdioCollector {
            id: senderErrors
        }
        onExited: code => {
            if (code !== 0) {
                root.problem = senderErrors.text.trim() || "Couldn't send it";
                if (!Launcher.open)
                    Quickshell.execDetached(["notify-send", "-a", "Shared Box", "Couldn't send it", root.problem]);
            } else if (stay) {
                root.clearQuery();
                if (copied)
                    root.copiedFiles = [];
            } else {
                Launcher.close();
            }
        }
    }

    Process {
        id: remover
        onExited: code => {
            if (code !== 0)
                store.reload();
        }
    }
}
