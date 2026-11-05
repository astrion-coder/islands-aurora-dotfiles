import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// Emoji search by name and keyword (data/emoji.txt). Enter types the emoji into the
// window you were in (and copies it); Alt+1 only copies it.
Mode {
    id: root

    property var emoji: []

    prompt: "emoji"
    placeholder: "search emoji…"
    hint: "Enter types the emoji where you were, Alt+1 only copies it"
    rows: Fuzzy.filter(emoji, query, 300)

    // emoji \t name \t keywords
    FileView {
        path: Quickshell.shellPath("launcher/data/emoji.txt")
        onLoaded: root.emoji = text().split("\n")
            .filter(l => l && !l.startsWith("#"))
            .map(l => {
                const f = l.split("\t");
                return { glyph: f[0], title: f[1], meta: f[2] };
            })
    }

    function activate(row, how) {
        if (!row)
            return;
        Launcher.close();
        if (how === "alt")
            Quickshell.execDetached(["wl-copy", "--", row.glyph]);
        else    // give focus back to the window before typing into it
            Quickshell.execDetached(["sh", "-c", 'wl-copy -- "$1"; sleep 0.15; wtype -- "$1"', "sh", row.glyph]);
    }
}
