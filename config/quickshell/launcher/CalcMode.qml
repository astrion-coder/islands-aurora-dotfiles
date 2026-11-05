import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Calculator (qalc): the result updates as you type. Enter copies it; Ctrl+Enter saves
// it to the history below (Enter on a history row copies that result).
Mode {
    id: root

    property string result: ""
    property var history: []          // "expression = result", newest first
    property bool pending: false

    prompt: "calc"
    placeholder: "calculate…"
    hint: "Enter pastes the result where you were, Alt+1 only copies it, Ctrl+Enter saves it to the history"
    rows: (result !== "" ? [{ title: "= " + result, value: result, expression: query.trim(), icon: "accessories-calculator" }] : [])
        .concat(history.map(h => ({ title: h, value: h.slice(h.lastIndexOf(" = ") + 3), icon: "document-open-recent" })))

    onQueryChanged: delay.restart()

    function calculate() {
        if (query.trim() === "") {
            result = "";
            return;
        }
        if (qalc.running) {
            pending = true;
            return;
        }
        qalc.command = ["qalc", "-t", query.trim()];
        qalc.running = true;
    }

    function activate(row, how) {
        if (!row)
            return;
        if (how === "ctrl" && row.expression) {
            history = [row.expression + " = " + row.value, ...history.filter(h => h !== row.expression + " = " + row.value)].slice(0, 100);
            store.setText(history.join("\n") + "\n");
            clearQuery();
            return;
        }
        Launcher.deliver('wl-copy -- "$1"', row.value, how === "alt");
    }

    FileView {
        id: store
        path: Quickshell.statePath("calc-history.txt")
        printErrors: false
        onLoaded: root.history = text().split("\n").filter(l => l)
    }

    Timer {
        id: delay
        interval: 80
        onTriggered: root.calculate()
    }

    Process {
        id: qalc
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim().split("\n")[0] ?? "";
                // qalc echoes text it can't work out
                root.result = out === root.query.trim() ? "" : out;
                if (root.pending) {
                    root.pending = false;
                    root.calculate();
                }
            }
        }
    }
}
