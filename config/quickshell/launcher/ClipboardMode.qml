import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// Clipboard history (cliphist; recorded by `wl-paste --watch cliphist store`, started in
// hyprland.lua). Enter copies the entry back; Shift+Delete removes it. The pane beside
// the list previews the selected entry: images, links (the page's title, description and
// picture), colours, and the full text.
Mode {
    id: root

    // Link previews fetch the page when a link stays selected for a moment, like a
    // browser opening it would (a one-time sign-in or reset link can be used up by that).
    // false: links show only their address.
    property bool fetchLinks: true

    readonly property string cache: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-clipboard"
    property var entries: []

    prompt: "clipboard"
    placeholder: "search clipboard…"
    hint: "Enter pastes it where you were, Alt+1 only copies it, Shift+Delete removes it"
    rows: Fuzzy.filter(entries, query, 500)
    preview: Component {
        ClipboardPreview {
            mode: root
        }
    }

    // "<id>\t<preview>" -> a row; cliphist describes images as
    // "[[ binary data 120 KiB png 1920x1080 ]]"
    function entry(line) {
        const id = line.slice(0, line.indexOf("\t"));
        const text = line.slice(line.indexOf("\t") + 1);
        const bin = text.match(/^\[\[ binary data (.+?) (\w+)(?: (\d+)x(\d+))? \]\]$/);
        if (bin) {
            const image = /^(png|jpeg|jpg|gif|webp|bmp|svg)$/.test(bin[2]);
            return {
                line, id,
                kind: image ? "image" : "binary",
                title: image ? `${bin[3]} × ${bin[4]} image` : `${bin[2]} data`,
                size: bin[1], format: bin[2].toUpperCase(), width: bin[3], height: bin[4],
                file: image ? `${root.cache}/${id}.${bin[2]}` : "",
                icon: image ? "image-x-generic" : "application-octet-stream",
                meta: image ? "image picture screenshot " + bin[2] : bin[2]
            };
        }
        const flat = text.replace(/\s+/g, " ").trim();
        if (/^https?:\/\/\S+$/.test(flat))
            return { line, id, kind: "link", title: flat, url: flat, icon: "text-html", meta: "link url" };
        if (/^(#[0-9a-f]{3}|#[0-9a-f]{6}|#[0-9a-f]{8}|rgba?\([\d\s.,%]+\))$/i.test(flat))
            return { line, id, kind: "color", title: flat, swatch: flat, meta: "colour color" };
        return { line, id, kind: "text", title: flat, icon: "text-x-generic" };
    }

    function opened() {
        list.running = true;
    }

    function activate(row, how) {
        if (!row)
            return;
        if (how === "delete") {
            remove.command = ["sh", "-c", 'printf "%s" "$1" | cliphist delete', "sh", row.line];
            remove.running = true;
            return;
        }
        Launcher.deliver('printf "%s" "$1" | cliphist decode | wl-copy', row.line, how === "alt");
    }

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l.includes("\t")).map(root.entry);
                images.running = true;
            }
        }
    }

    // decode the images (once), then show their thumbnails
    Process {
        id: images
        command: [Quickshell.shellPath("scripts/clipboard-images.sh")]
        onExited: root.entries = root.entries.map(e => e.kind === "image" ? Object.assign({}, e, { thumb: e.file }) : e)
    }

    Process {
        id: remove
        onExited: list.running = true
    }

    // ---------------------------------------------------------------- the selected entry

    property string text: ""           // its full text (the list shows the start)
    property var link: null            // its link preview, once fetched
    property bool fetching: false
    property string shown: ""          // id of the entry those belong to

    // (rows are rebuilt as you type: only a different entry starts over)
    onCurrentChanged: {
        if ((current?.id ?? "") === shown)
            return;
        shown = current?.id ?? "";
        text = "";
        link = null;
        fetching = false;
        settle.restart();
    }

    // wait until the selection settles, so arrowing through the list stays cheap
    Timer {
        id: settle
        interval: 120
        onTriggered: {
            const e = root.current;
            if (!e || e.kind === "image" || e.kind === "binary")
                return;
            decoder.command = ["sh", "-c", 'printf "%s" "$1" | cliphist decode | head -c 20000', "sh", e.line];
            decoder.running = true;
            if (e.kind === "link" && root.fetchLinks)
                fetchDelay.restart();
        }
    }

    Timer {
        id: fetchDelay
        interval: 400
        onTriggered: {
            if (root.current?.kind !== "link")
                return;
            root.fetching = true;
            fetcher.url = root.current.url;
            fetcher.command = [Quickshell.shellPath("scripts/link-preview.py"), root.current.url];
            fetcher.running = true;
        }
    }

    Process {
        id: decoder
        stdout: StdioCollector {
            onStreamFinished: root.text = text
        }
    }

    Process {
        id: fetcher
        property string url
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.current?.url !== fetcher.url)
                    return;      // the selection moved on
                root.fetching = false;
                try {
                    root.link = JSON.parse(text);
                } catch (e) {
                    root.link = { url: fetcher.url };
                }
            }
        }
    }
}
