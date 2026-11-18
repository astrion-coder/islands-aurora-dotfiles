import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// File search in your home folder (fd: skips hidden and git-ignored files; fzf ranks
// the matches). Enter opens the file in its default app; Ctrl+Enter sends it to one of
// your devices over Taildrop, or into the Shared Box (SendMode.qml).
Mode {
    id: root

    readonly property string index: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-files.txt"
    property bool indexed: false
    property bool pending: false

    prompt: "files"
    placeholder: "search files…"
    hint: indexed ? "Enter opens it, Ctrl+Enter sends it to your phone or Mac" : "finding your files…"

    function opened() {
        indexed = false;
        rows = [];
        indexer.running = true;
    }

    onQueryChanged: delay.restart()

    function search() {
        if (!indexed)
            return;
        if (searcher.running) {
            pending = true;
            return;
        }
        searcher.command = ["sh", "-c",
            query.trim() === "" ? 'head -n 200 "$2"' : 'env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE fzf --filter "$1" < "$2" | head -n 200',
            "sh", query, index];
        searcher.running = true;
    }

    function activate(row, how) {
        if (!row)
            return;
        const path = row.title.replace(/^~/, Quickshell.env("HOME"));
        if (how === "ctrl") {
            Launcher.sendFile = path;
            Launcher.enter("send");
            return;
        }
        Launcher.close();
        Quickshell.execDetached(["xdg-open", path]);
    }

    Timer {
        id: delay
        interval: 60
        onTriggered: root.search()
    }

    // every file, as ~/path, one per line
    Process {
        id: indexer
        command: ["sh", "-c", 'fd . "$HOME" --type f --max-results 100000 2>/dev/null | sed "s|^$HOME/|~/|" > "$1"', "sh", root.index]
        onExited: {
            root.indexed = true;
            root.search();
        }
    }

    Process {
        id: searcher
        stdout: StdioCollector {
            onStreamFinished: {
                root.rows = Fuzzy.mark(text.split("\n").filter(l => l).map(l => ({ title: l, icon: "text-x-generic" })), root.query);
                if (root.pending) {
                    root.pending = false;
                    root.search();
                }
            }
        }
    }
}
