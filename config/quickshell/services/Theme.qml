pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The shell's look. The palette is generated from the wallpaper by matugen
// (~/.config/matugen/templates/shell-colors.css -> colors.css next to shell.qml) and is
// re-read whenever it changes, so a new wallpaper recolours the shell in place.
Singleton {
    id: root

    property color fg: "#e6e0e9"
    property color subtle: "#cac4d0"
    property color muted: "#938f99"
    property color accent: "#d0bcff"
    property color accent2: "#efb8c8"
    property color ink: "#381e72"
    property color base: "#141218"
    property color error: "#f2b8b5"

    // fade between palettes, but not into the first one
    property bool loaded: false
    Behavior on fg { enabled: root.loaded; ColorAnimation { duration: 600 } }
    Behavior on subtle { enabled: root.loaded; ColorAnimation { duration: 600 } }
    Behavior on muted { enabled: root.loaded; ColorAnimation { duration: 600 } }
    Behavior on accent { enabled: root.loaded; ColorAnimation { duration: 600 } }
    Behavior on accent2 { enabled: root.loaded; ColorAnimation { duration: 600 } }
    Behavior on ink { enabled: root.loaded; ColorAnimation { duration: 600 } }
    Behavior on base { enabled: root.loaded; ColorAnimation { duration: 600 } }
    Behavior on error { enabled: root.loaded; ColorAnimation { duration: 600 } }

    // The frame around the screen (and what grows out of it: the bar's pills, the
    // island's panel, the launcher): solid, the darkest colour of the palette
    readonly property color frameColor: base
    // Glass: thin tinted fills over Hyprland's blur
    readonly property color card: alpha(base, 0.45)       // menus, tooltips
    readonly property color edge: Qt.rgba(1, 1, 1, 0.15)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.12)

    readonly property string fontFamily: "Noto Sans"
    readonly property int fontSize: 14

    // The frame: as thick on every side, the desktop a rounded box inside it
    readonly property int frame: 10
    readonly property int frameRadius: 14
    // The bar: each pill comes out of the frame's top edge as a tab, `tabPad` around it,
    // with corners curving inwards (`tabCurve`) where it leaves the edge and rounded by
    // `tabRadius` at the bottom (the launcher's and the island's panel's corners too).
    // What's drawn inside a tab is rounded to match (`pillRadius`).
    readonly property int islandHeight: 36
    readonly property int tabPad: 4
    readonly property int tabCurve: 6
    readonly property int tabRadius: 12
    readonly property int pillRadius: tabRadius - tabPad
    readonly property int pillTop: frame + tabPad
    readonly property int barHeight: pillTop + islandHeight + tabPad            // how far the tabs come down
    readonly property int edgeMargin: frame + frameRadius + tabCurve + tabPad   // clear of the frame's corners
    readonly property int spacing: 8

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    FileView {
        path: Quickshell.shellPath("colors.css")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const names = ["fg", "subtle", "muted", "accent", "accent2", "ink", "base", "error"];
            const re = /@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})\s*;/g;
            const css = text();
            let m;
            while ((m = re.exec(css)) !== null)
                if (names.includes(m[1]))
                    root[m[1]] = m[2];
            root.loaded = true;
        }
    }
}
