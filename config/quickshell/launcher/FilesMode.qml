import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// File search in your home folder (fd: skips hidden and git-ignored files; fzf ranks
// the matches). Enter opens the file in its default app; Ctrl+Enter puts it in the
// Shared Box, to download on your phone or Mac (scripts/shared-box.py add-file).
// forBox: the same search, from the Shared Box's "Send a file…" (the "boxfile" menu):
// Enter puts the file in the box, Shift+Enter puts it in and stays to pick another, Esc
// goes back to the box.
Mode {
    id: root

    property bool forBox: false
    property string added: ""           // (forBox: what Shift+Enter just put in the box)
    property string problem: ""

    readonly property string index: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-files.txt"
    readonly property string box: Quickshell.shellPath("scripts/shared-box.py")
    property bool indexed: false
    property bool pending: false

    prompt: forBox ? "send" : "files"
    placeholder: forBox ? "find a file for the Shared Box…" : "search files…"
    hint: !indexed ? "finding your files…"
        : problem !== "" ? problem
        : added !== "" ? "“" + (added.length > 36 ? added.slice(0, 22) + "…" + added.slice(-12) : added)
                         + "” is in the box. Pick another, or Esc to go back"
        : forBox ? "Enter puts it in the Shared Box, Shift+Enter: and pick another, Esc goes back"
        : "Enter opens it, Ctrl+Enter puts it in the Shared Box for your phone and Mac"

    function opened() {
        indexed = false;
        added = "";
        problem = "";
        rows = [];
        indexer.running = true;
    }

    onQueryChanged: {
        problem = "";
        delay.restart();
    }

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
        if (forBox && how === "shift") {        // (quietly: the hint says so, and it stays)
            adder.name = path.split("/").pop();
            adder.command = [box, "add-file", "--quiet", path];
            adder.running = true;
            return;
        }
        Launcher.close();
        if (forBox || how === "ctrl")
            Quickshell.execDetached([box, "add-file", path]);      // (a notification says how it went)
        else
            Quickshell.execDetached(["xdg-open", path]);
    }

    Process {
        id: adder
        property string name: ""
        stderr: StdioCollector {
            id: adderErrors
        }
        onExited: code => {
            root.added = code === 0 ? name : "";
            root.problem = code === 0 ? "" : adderErrors.text.trim() || "Couldn't put it in the box";
        }
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
