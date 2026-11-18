import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// The Shared Box (scripts/shared-box.py): text, links and files shared with your phone and
// Mac over Tailscale. Type and press Enter to send it to them all (Shift+Enter: and stay
// here); the list is what's in the box, the newest first, and narrows down as you type.
// Enter on one opens a link or a file, or pastes text where you were; Alt+1 only copies it
// (a file: its path); Ctrl+Enter on a file sends it to a device over Taildrop;
// Shift+Delete takes it out of the box, on every device.
Mode {
    id: root

    readonly property string file: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share")
                                   + "/shared-box/items.json"
    readonly property string socket: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shared-box-local.sock"
    readonly property string script: Quickshell.shellPath("scripts/shared-box.py")
    property var items: []          // { id, kind: "text" | "link" | "file", text, from, time, path }
    property bool running: true     // (its socket is there)
    property string problem: ""
    property real now: Date.now()

    prompt: "shared"
    placeholder: "send text or a link to your devices…"
    hint: problem !== "" ? problem
        : !running ? "The Shared Box isn't running: set it up with ~/.config/quickshell/scripts/shared-box-setup.sh"
        : current?.send ? "Enter sends it to all your devices, Shift+Enter sends it and stays here"
        : current?.item?.kind === "file" ? "Enter opens it, Ctrl+Enter sends it to a device, Alt+1 copies its path, Shift+Delete takes it out"
        : current?.item?.kind === "link" ? "Enter opens it, Alt+1 copies it, Shift+Delete takes it out of the box"
        : current ? "Enter pastes it where you were, Alt+1 only copies it, Shift+Delete takes it out of the box"
        : "Type to send text or a link to all your devices"
    rows: (query.trim() !== "" ? [{
              send: true,
              title: "Send “" + query.trim().replace(/\s+/g, " ") + "”",
              subtitle: "to all your devices",
              icon: "document-send"
          }] : []).concat(Fuzzy.filter(items.map(row), query, 300))

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
    }

    function activate(row, how) {
        if (!row)
            return;
        if (row.send) {
            sender.stay = how === "shift";
            sender.command = [script, "add", query.trim()];
            sender.running = true;
            return;
        }
        const it = row.item;
        if (how === "delete") {
            remover.command = [script, "remove", it.id];
            remover.running = true;
            items = items.filter(i => i.id !== it.id);
        } else if (it.kind === "file") {
            if (how === "ctrl") {
                Launcher.sendFile = it.path;
                Launcher.enter("send");
            } else if (how === "alt") {
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

    Process {
        id: check
        command: ["test", "-S", root.socket]
        onExited: code => root.running = code === 0
    }

    Process {
        id: sender
        property bool stay: false
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
