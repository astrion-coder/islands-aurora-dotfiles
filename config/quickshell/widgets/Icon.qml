import QtQuick
import QtQuick.Shapes
import qs.services

// Line icons in the bar's style: 24-unit paths with round caps, in palette colours.
// "Off" variants add a cross in crossColor; `filled` fills the shapes (media controls).
Item {
    id: root

    property string name
    property color color: Theme.accent
    property color crossColor: Theme.error
    property real weight: 2.2       // stroke width in the 24-unit grid
    property bool filled: false

    readonly property var icons: ({
        "volume": ["M11 5 6 9H3v6h3l5 4z M15.5 8.5a5 5 0 0 1 0 7", ""],
        "volume-muted": ["M11 5 6 9H3v6h3l5 4z", "M16 9l5 6M21 9l-5 6"],
        "bluetooth": ["m7 7 10 10-5 5V2l5 5L7 17", ""],
        "bluetooth-muted": ["m7 7 10 10-5 5V2l5 5L7 17", "M19 15l4 4M23 15l-4 4"],
        "power": ["M12 3v8 M6.3 7.3a8 8 0 1 0 11.4 0", ""],
        // lock screen buttons (same drawings as the login screen's)
        "suspend": ["M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z", ""],
        "reboot": ["M3 12a9 9 0 1 0 3-6.7 M3 4v5h5", ""],
        // the island: media, battery
        "music": ["M9 18V5l12-2v13 M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0z M21 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0z", ""],
        "play": ["M7 4.5v15l12-7.5z", ""],
        "pause": ["M7 5h3v14H7z M14 5h3v14h-3z", ""],
        "previous": ["M19 5v14l-10-7z M6 5v14", ""],
        "next": ["M5 5v14l10-7z M18 5v14", ""],
        "battery": ["M3 7h15a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M23 11v2", ""],
        "charging": ["M13 2 3 14h9l-1 8 10-12h-9l1-8z", ""],
        // the calendar
        "calendar": ["M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M16 2v4 M8 2v4 M3 10h18", ""],
        "chevron-left": ["M15 18l-6-6 6-6", ""],
        "chevron-right": ["M9 18l6-6-6-6", ""],
        "chevron-down": ["M6 9l6 6 6-6", ""],
        "plus": ["M12 5v14 M5 12h14", ""],
        "repeat": ["M17 2l4 4-4 4 M3 11v-1a4 4 0 0 1 4-4h14 M7 22l-4-4 4-4 M21 13v1a4 4 0 0 1-4 4H3", ""],
        "close": ["M18 6 6 18 M6 6l12 12", ""],
        "edit": ["M12 20h9 M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z", ""],
        "notes": ["M4 6h16 M4 11h16 M4 16h10 M4 21h6", ""],
        "undo": ["M3 7v6h6 M3 13a9 9 0 1 0 2.6-6.4L3 9", ""],
        // screenshots
        "camera": ["M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z M15 13a3 3 0 1 1-6 0 3 3 0 0 1 6 0z", ""],
        "region": ["M3 8V5a2 2 0 0 1 2-2h3 M16 3h3a2 2 0 0 1 2 2v3 M21 16v3a2 2 0 0 1-2 2h-3 M8 21H5a2 2 0 0 1-2-2v-3 M8 9h8v6H8z", ""],
        "window": ["M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M2 9h20 M6 6.5h.01 M9 6.5h.01", ""],
        "screen": ["M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M8 21h8 M12 17v4", ""],
        "timer": ["M10 2h4 M12 14l3-3 M20 14a8 8 0 1 1-16 0 8 8 0 0 1 16 0z", ""],
        "video": ["M22 8l-6 4 6 4z M4 6h10a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z", ""],
        // wallpapers
        "image": ["M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M21 15l-5-5L5 21 M10 8.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0z", ""],
        "shuffle": ["M16 3h5v5 M4 20 21 3 M21 16v5h-5 M15 15l6 6 M4 4l5 5", ""],
        "folder": ["M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.7-.9l-.8-1.2A2 2 0 0 0 7.9 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z", ""],
        "check": ["M20 6 9 17l-5-5", ""]
    })
    readonly property var paths: icons[name] ?? ["", ""]

    implicitWidth: 14
    implicitHeight: 14

    Shape {
        width: 24
        height: 24
        scale: root.width / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.weight
            fillColor: root.filled ? root.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.paths[0] }
        }

        ShapePath {
            strokeColor: root.paths[1] ? root.crossColor : "transparent"
            strokeWidth: root.weight
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.paths[1] }
        }
    }
}
