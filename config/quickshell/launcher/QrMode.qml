import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// QR codes and links found in your screenshots (scripts/qr-codes.py keeps the last 100),
// the latest first: "Show all" on a screenshot's notification opens this, and so does
// Links & QR Codes in the main menu. Each says where it came from: a QR code, or written
// on screen. Enter opens a link (Shift+Enter: and stays here, for the next one) or pastes
// a code's text where you were; Alt+1 only copies it; Shift+Delete forgets it.
Mode {
    id: root

    readonly property string file: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                                   + "/quickshell-qr-codes.json"
    property var codes: []          // { text, from: "qr" or "text", time, shot }, newest first
    property real now: Date.now()

    prompt: "links"
    placeholder: "search links and QR codes…"
    hint: codes.length === 0 ? "Links and QR codes in your screenshots show up here"
        : current?.link ? "Enter opens it, Shift+Enter opens it and stays here, Alt+1 copies it, Shift+Delete forgets it"
        : "Enter pastes it where you were, Alt+1 only copies it, Shift+Delete forgets it"
    rows: Fuzzy.filter(codes.map(row), query, 500)

    function isLink(text) {
        return /^https?:\/\/\S+$/.test(text.trim());
    }

    // when it was found: "14:05" today, "yesterday", "12 Nov", "12 Nov 2025"
    function when(seconds) {
        const d = new Date(seconds * 1000), today = new Date(now);
        const days = Math.round((new Date(today.getFullYear(), today.getMonth(), today.getDate())
                               - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000);
        return days === 0 ? Qt.formatTime(d, "HH:mm") : days === 1 ? "yesterday"
             : Qt.formatDate(d, d.getFullYear() === today.getFullYear() ? "d MMM" : "d MMM yyyy");
    }

    // (one saved before links were read too has no "from": a QR code)
    function row(c) {
        const link = isLink(c.text);
        const wifi = /^WIFI:/i.test(c.text);
        const qr = c.from !== "text";
        return {
            text: c.text,
            link: link,
            title: c.text.replace(/\s+/g, " ").trim(),
            subtitle: (!qr ? "on screen" : wifi ? "Wi-Fi QR code" : "QR code") + ", " + when(c.time),
            icon: !qr ? "text-html" : wifi ? "network-wireless" : "view-barcode-qr",
            meta: (qr ? "qr code " : "on screen ") + (link ? "link url" : wifi ? "wifi wi-fi network password" : "text")
                  + " " + when(c.time)
        };
    }

    function opened() {
        now = Date.now();
        store.reload();
    }

    function activate(row, how) {
        if (!row)
            return;
        if (how === "delete") {
            codes = codes.filter(c => c.text !== row.text);
            store.setText(JSON.stringify(codes));
        } else if (row.link && how !== "alt") {
            Quickshell.execDetached(["xdg-open", row.text.trim()]);
            if (how !== "shift")
                Launcher.close();
        } else {
            Launcher.deliver('wl-copy -- "$1"', row.text, how === "alt");
        }
    }

    // (written by scripts/qr-codes.py; read again when it changes)
    FileView {
        id: store
        path: root.file
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const list = JSON.parse(text());
                root.codes = Array.isArray(list) ? list.filter(c => c && typeof c.text === "string") : [];
            } catch (e) {
                root.codes = [];
            }
        }
        onLoadFailed: root.codes = []
    }
}
