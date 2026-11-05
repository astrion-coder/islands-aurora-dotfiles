import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.widgets
import "fuzzy.js" as Fuzzy

// The wallpaper picker (Super+W, or "Change Wallpaper" in the main menu), growing out of
// the island like the rest of the launcher: the pictures in ~/Pictures/Wallpapers (and
// folders in it) as a grid, newest first, the one showing marked (and first, if it's
// from somewhere else). Type to narrow them
// down by name; the arrows (or Tab) choose. Enter, or a click, sets the lit one and
// closes, so you see it come in (a different transition each time); Shift+Enter, or a
// right click, sets it and stays, to try a few. Ctrl+R: one at random; Ctrl+O: the
// folder, to add some. (services/Wallpaper.qml; the colours follow by themselves.)
Column {
    id: root

    property string query: ""
    property int current: 0                     // the lit one, in `shown`
    property bool follow: false                 // keep the one showing lit (just opened)

    readonly property int columns: 3
    readonly property int rows: 3               // seen at once (more: scroll)
    readonly property int gap: 12
    readonly property real tileWidth: Math.floor((width - (columns - 1) * gap) / columns)
    readonly property real tileHeight: Math.round(tileWidth * 9 / 16)

    readonly property var shown: Fuzzy.filter(Wallpaper.choices.map(f => ({
        file: f,
        title: Wallpaper.name(f),
        // (its folders, to search by too)
        meta: (f.startsWith(Wallpaper.folder + "/") ? f.slice(Wallpaper.folder.length + 1) : f).split("/").slice(0, -1).join(" ")
    })), query)

    spacing: 10

    // (the launcher, as the picker opens)
    function opened() {
        follow = true;
        lightShowing();
        Wallpaper.scan();
    }

    function lightShowing() {
        current = Math.max(0, shown.findIndex(w => w.file === Wallpaper.current));
        Qt.callLater(() => grid.positionViewAtIndex(current, GridView.Contain));
    }

    onShownChanged: {
        if (follow)
            lightShowing();
        else if (current >= shown.length)
            current = Math.max(0, shown.length - 1);
    }
    onQueryChanged: {
        follow = false;
        current = 0;
        grid.positionViewAtBeginning();
    }

    function move(by) {
        if (shown.length === 0)
            return;
        follow = false;
        current = Math.max(0, Math.min(shown.length - 1, current + by));
        grid.positionViewAtIndex(current, GridView.Contain);
    }

    // stay: set it but keep the picker open
    function choose(index, stay) {
        const w = shown[index];
        if (!w)
            return;
        current = index;
        follow = false;
        if (!stay)
            Launcher.close();
        Wallpaper.set(w.file);
    }

    function random() {
        Launcher.close();
        Wallpaper.random();
    }

    function openFolder() {
        Launcher.close();
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", Wallpaper.folder]);
    }

    // the launcher's keys, while this is showing (true: used; the rest go into the
    // search field)
    function handle(event) {
        const k = event.key;
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        if (k === Qt.Key_Return || k === Qt.Key_Enter)
            choose(current, shift);
        else if (k === Qt.Key_Left || k === Qt.Key_Backtab)
            move(-1);
        else if (k === Qt.Key_Right || k === Qt.Key_Tab)
            move(1);
        else if (k === Qt.Key_Up || (ctrl && (k === Qt.Key_K || k === Qt.Key_P)))
            move(-columns);
        else if (k === Qt.Key_Down || (ctrl && (k === Qt.Key_J || k === Qt.Key_N)))
            move(columns);
        else if (k === Qt.Key_PageUp)
            move(-columns * rows);
        else if (k === Qt.Key_PageDown)
            move(columns * rows);
        else if (ctrl && k === Qt.Key_R)
            random();
        else if (ctrl && k === Qt.Key_O)
            openFolder();
        else
            return false;
        return true;
    }

    // ---------------------------------------------------------------- how many, and buttons
    RowLayout {
        width: parent.width
        spacing: 6

        Caption {
            icon: "image"
            text: {
                const n = Wallpaper.files.length;
                return root.query.trim() !== "" ? root.shown.length + " of " + n
                     : n === 1 ? "1 wallpaper" : n + " wallpapers";
            }
        }
        Item { Layout.fillWidth: true }
        Choice {
            icon: "shuffle"
            text: "random"
            visible: Wallpaper.files.length > 1
            onClicked: root.random()
        }
        Choice {
            icon: "folder"
            text: "folder"
            onClicked: root.openFolder()
        }
    }

    // ---------------------------------------------------------------- the pictures
    GridView {
        id: grid
        // (each cell includes the gap to its right and below; the last ones are cut off)
        width: parent.width + root.gap
        height: Math.max(1, Math.min(root.rows, Math.ceil(root.shown.length / root.columns))) * cellHeight - root.gap
        visible: root.shown.length > 0
        cellWidth: root.tileWidth + root.gap
        cellHeight: root.tileHeight + root.gap
        clip: true
        model: root.shown
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: cellHeight * 2

        delegate: MouseArea {
            id: tile

            required property var modelData
            required property int index
            readonly property bool lit: index === root.current
            readonly property bool showing: modelData.file === Wallpaper.current

            width: root.tileWidth
            height: root.tileHeight
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => root.choose(index, mouse.button === Qt.RightButton)

            ClippingRectangle {
                anchors.fill: parent
                radius: Theme.tabRadius
                color: Theme.alpha(Theme.fg, 0.06)

                // (while it loads)
                Icon {
                    anchors.centerIn: parent
                    visible: picture.status !== Image.Ready
                    name: "image"
                    implicitWidth: 26
                    implicitHeight: 26
                    weight: 1.7
                    color: Theme.muted
                }
                Image {
                    id: picture
                    anchors.fill: parent
                    // (each part of the path escaped: names can have # or % in them)
                    source: "file://" + tile.modelData.file.split("/").map(encodeURIComponent).join("/")
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: root.tileWidth * 2
                    sourceSize.height: root.tileHeight * 2
                    opacity: status === Image.Ready ? 1 : 0
                    scale: tile.containsMouse ? 1.07 : 1
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                }

                // its name, on a shade along the bottom
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 42
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.alpha(Theme.base, 0) }
                        GradientStop { position: 1; color: Theme.alpha(Theme.base, 0.85) }
                    }
                }
                Label {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    anchors.bottomMargin: 8
                    textFormat: Text.StyledText
                    text: Fuzzy.highlight(tile.modelData.title, tile.modelData.positions, Theme.accent2)
                    font.pixelSize: 12
                    font.weight: tile.lit ? Font.Bold : Font.Medium
                    color: tile.lit ? Theme.fg : Theme.subtle
                    elide: Text.ElideRight
                }
            }

            // the one showing
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                visible: tile.showing
                width: badge.implicitWidth + 14
                height: 22
                radius: 11
                color: Theme.alpha(Theme.base, 0.8)

                Row {
                    id: badge
                    anchors.centerIn: parent
                    spacing: 4

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        implicitWidth: 12
                        implicitHeight: 12
                        weight: 2.6
                        color: Theme.accent
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "now"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.accent
                    }
                }
            }

            // the lit one: a ring
            Rectangle {
                anchors.fill: parent
                radius: Theme.tabRadius
                color: "transparent"
                border.width: 2.5
                border.color: Theme.accent
                opacity: tile.lit ? 1 : tile.containsMouse ? 0.35 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
        }
    }

    // ---------------------------------------------------------------- nothing to show
    Rectangle {
        width: parent.width
        height: 150
        visible: root.shown.length === 0
        radius: Theme.tabRadius
        color: Theme.alpha(Theme.fg, 0.05)

        Column {
            anchors.centerIn: parent
            spacing: 6

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "image"
                implicitWidth: 30
                implicitHeight: 30
                weight: 1.7
                color: Theme.muted
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Wallpaper.files.length > 0 ? "Nothing called that"
                    : Wallpaper.scanned ? "No wallpapers yet" : "Looking for your wallpapers…"
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Wallpaper.scanned
                text: Wallpaper.files.length > 0 ? "Try another name"
                    : "Put pictures in ~/Pictures/Wallpapers (Ctrl+O opens it)"
                font.pixelSize: 13
                color: Theme.subtle
            }
        }
    }

    // ---------------------------------------------------------------- keys
    Rectangle {
        width: parent.width
        height: 32
        radius: Theme.pillRadius
        color: Theme.alpha(Theme.fg, 0.06)

        Label {
            x: 14
            width: parent.width - 28
            anchors.verticalCenter: parent.verticalCenter
            text: "Enter sets the lit one (arrows choose), Shift+Enter tries it and stays. Ctrl+R: a random one, Ctrl+O: the folder"
            color: Theme.subtle
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }
}
