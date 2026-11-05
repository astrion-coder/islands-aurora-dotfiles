pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpapers: the pictures in ~/Pictures/Wallpapers (and folders in it), the one showing,
// and setting one, with a transition picked at random each time (scripts/wallpaper.sh,
// through awww; everything re-themes from it by itself: hypr/scripts/wallpaper-theme.sh). The picker is
// launcher/WallpaperPanel.qml (Super+W, or "Change Wallpaper" in the main menu).
//   qs ipc call wallpaper set <file>     a path, or a name in ~/Pictures/Wallpapers
//   qs ipc call wallpaper random         another one, at random
Singleton {
    id: root

    readonly property string folder: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    property var files: []              // full paths, newest first
    property bool scanned: false
    // the one showing (wallpaper-theme.sh writes it down once it's themed; one set here
    // counts straight away)
    property string current: ""
    // the picker's: these, and the one showing first when it's from somewhere else
    readonly property var choices: current !== "" && !files.includes(current) ? [current].concat(files) : files

    function name(file) {
        return file.slice(file.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
    }

    function set(file) {
        if (!file)
            return;
        current = file;
        Quickshell.execDetached([Quickshell.shellPath("scripts/wallpaper.sh"), file]);
    }

    property bool wantRandom: false
    function random() {
        if (!scanned) {
            wantRandom = true;
            scan();
            return;
        }
        const others = files.filter(f => f !== current);
        if (others.length > 0)
            set(others[Math.floor(Math.random() * others.length)]);
    }

    // (again each time the picker opens, so new pictures show up)
    function scan() {
        lister.running = true;
    }

    Process {
        id: lister
        running: true
        command: ["sh", "-c", 'find -L "$1" -maxdepth 3 -type f -not -path "*/.*" \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.bmp" \\) -printf "%T@\\t%p\\n" 2>/dev/null | sort -rn | cut -f2-', "sh", root.folder]
        stdout: StdioCollector {
            onStreamFinished: {
                root.files = text.split("\n").filter(l => l !== "");
                root.scanned = true;
                if (root.wantRandom) {
                    root.wantRandom = false;
                    root.random();
                }
            }
        }
    }

    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/wallpaper-theme.last"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.current = text().trim()
    }

    IpcHandler {
        target: "wallpaper"

        function set(file: string): void {
            root.set(file.startsWith("/") ? file : root.folder + "/" + file);
        }
        function random(): void {
            root.random();
        }
    }
}
