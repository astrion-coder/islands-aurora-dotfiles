import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

// The screenshot and recording menu (Super+Shift+P or Print; "Screenshot" or "Record
// Screen" in the main menu), growing out of the island like the rest of the launcher.
// Everything at once:
//   Screenshot   an area (drag a rectangle), a window (click one), or the screen; and
//                whether to draw on it straight after
//   Record       the same three; and the sound: none, what you hear, or the microphone
//   delay        before either, counted down in the island
// Click a tile to take it, or choose one with the arrows (or 1-6) and press Enter. The
// menu goes away as it starts. Pictures are copied and saved to ~/Pictures/Screenshots,
// videos saved to ~/Videos/Recordings and copied as a file (services/Screenshot.qml).
// While a video records, this shows it, with its time: click it or press Enter to stop.
Column {
    id: root

    // the lit tile: 0-2 a screenshot, 3-5 a recording (of an area, a window, the screen)
    property int current: 0
    readonly property bool recording: Screenshot.recording
    readonly property var kinds: [
        { what: "area", title: "Area", detail: "drag a rectangle", icon: "region" },
        { what: "window", title: "Window", detail: "click one", icon: "window" },
        { what: "screen", title: "Screen", detail: "all of it", icon: "screen" }
    ]
    readonly property var soundNames: ({ none: "none", system: "computer", mic: "mic" })
    readonly property real tileWidth: (width - 24) / 3

    spacing: 10

    // "Record Screen" in the main menu: on the recording row
    Connections {
        target: Launcher
        function onModeChanged() {
            if (Launcher.mode === "record")
                root.current = 3 + root.current % 3;
        }
    }

    function take(index) {
        const i = index ?? current;
        const what = kinds[i % 3].what;
        if (i >= 3)
            Screenshot.record(what, Screenshot.delay, Screenshot.sound);
        else
            Screenshot.take(what, Screenshot.delay, Screenshot.edit);
    }

    function cycle(list, value) {
        return list[(list.indexOf(value) + 1) % list.length];
    }

    // the launcher's keys, while this is showing (true: used)
    function handle(event) {
        const k = event.key;
        const enter = k === Qt.Key_Return || k === Qt.Key_Enter;
        const row = current - current % 3;
        if (k === Qt.Key_Escape)
            Launcher.back();
        else if (recording)
            (enter || k === Qt.Key_Space) && Screenshot.stop();
        else if (enter)
            take();
        else if (k === Qt.Key_Left || k === Qt.Key_H)
            current = row + (current + 2) % 3;
        else if (k === Qt.Key_Right || k === Qt.Key_L)
            current = row + (current + 1) % 3;
        else if (k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_K || k === Qt.Key_J)
            current = (current + 3) % 6;
        else if (k === Qt.Key_Tab)
            current = (current + 1) % 6;
        else if (k === Qt.Key_Backtab)
            current = (current + 5) % 6;
        else if (k >= Qt.Key_1 && k <= Qt.Key_6)
            take(k - Qt.Key_1);
        else if (k === Qt.Key_D)
            Screenshot.delay = cycle(Screenshot.delays, Screenshot.delay);
        else if (k === Qt.Key_E)
            Screenshot.edit = !Screenshot.edit;
        else if (k === Qt.Key_S)
            Screenshot.sound = cycle(Screenshot.sounds, Screenshot.sound);
        return true;        // (nothing else goes into the hidden search field)
    }

    // (Choice and Caption: Choice.qml, Caption.qml)

    // one thing to take: an area, a window or the screen
    component Tile: MouseArea {
        id: tile
        property var kind
        property bool on: false
        height: 92
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: Theme.tabRadius
            color: tile.on ? Theme.alpha(Theme.accent, 0.16) : Theme.alpha(Theme.fg, tile.containsMouse ? 0.10 : 0.05)
            border.width: tile.on ? 1.5 : 0
            border.color: Theme.alpha(Theme.accent, 0.7)
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 5

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: tile.kind?.icon ?? ""
                implicitWidth: 28
                implicitHeight: 28
                weight: 1.7
                color: tile.on || tile.containsMouse ? Theme.accent : Theme.subtle
                scale: tile.containsMouse ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.kind?.title ?? ""
                font.pixelSize: 14
                font.weight: Font.Bold
                color: tile.on ? Theme.fg : Theme.subtle
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.kind?.detail ?? ""
                font.pixelSize: 12
                color: Theme.muted
            }
        }
    }

    // ---------------------------------------------------------------- screenshot
    RowLayout {
        width: parent.width
        visible: !root.recording
        spacing: 6

        Caption {
            icon: "camera"
            text: "Screenshot"
            strong: true
        }
        Item { Layout.fillWidth: true }
        Choice {
            text: "draw on it after"
            on: Screenshot.edit
            onClicked: Screenshot.edit = !Screenshot.edit
        }
    }
    Row {
        visible: !root.recording
        spacing: 12

        Repeater {
            model: 3
            Tile {
                required property int index
                width: root.tileWidth
                kind: root.kinds[index]
                on: root.current === index
                onClicked: root.take(index)
            }
        }
    }

    Item { width: 1; height: 4; visible: !root.recording }

    // ---------------------------------------------------------------- record
    RowLayout {
        width: parent.width
        visible: !root.recording
        spacing: 6

        Caption {
            icon: "video"
            text: "Record"
            strong: true
        }
        Item { Layout.fillWidth: true }
        Caption {
            icon: "volume"
            text: "sound"
        }
        Repeater {
            model: Screenshot.sounds
            Choice {
                required property string modelData
                text: root.soundNames[modelData]
                on: Screenshot.sound === modelData
                onClicked: Screenshot.sound = modelData
            }
        }
    }
    Row {
        visible: !root.recording
        spacing: 12

        Repeater {
            model: 3
            Tile {
                required property int index
                width: root.tileWidth
                kind: root.kinds[index]
                on: root.current === index + 3
                onClicked: root.take(index + 3)
            }
        }
    }

    Item { width: 1; height: 4; visible: !root.recording }

    // ---------------------------------------------------------------- before either
    RowLayout {
        width: parent.width
        visible: !root.recording
        spacing: 6

        Caption {
            icon: "timer"
            text: "delay"
        }
        Repeater {
            model: Screenshot.delays
            Choice {
                required property int modelData
                text: modelData === 0 ? "none" : modelData + " s"
                on: Screenshot.delay === modelData
                onClicked: Screenshot.delay = modelData
            }
        }
        Item { Layout.fillWidth: true }
    }

    // ---------------------------------------------------------------- recording now
    MouseArea {
        id: stopCard
        width: parent.width
        height: 128
        visible: root.recording
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Screenshot.stop()

        Rectangle {
            anchors.fill: parent
            radius: Theme.tabRadius
            color: Theme.alpha(Theme.error, stopCard.containsMouse ? 0.18 : 0.11)
            border.width: 1.5
            border.color: Theme.alpha(Theme.error, 0.55)
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        Row {
            anchors.centerIn: parent
            spacing: 20

            RecordDot {
                anchors.verticalCenter: parent.verticalCenter
                size: 26
                stop: stopCard.containsMouse
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Label {
                    text: "Recording"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
                Label {
                    text: Screenshot.elapsedText
                    font.pixelSize: 30
                    font.weight: Font.Bold
                    color: Theme.error
                }
                Label {
                    text: "click to stop"
                    font.pixelSize: 12
                    color: Theme.muted
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 32
        radius: Theme.pillRadius
        color: Theme.alpha(Theme.fg, 0.06)

        Label {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.recording ? "Enter stops it (so does the red dot in the island). It's saved in Videos/Recordings"
                : "Enter takes the lit one (arrows choose, or 1-6). D: delay, E: draw on it, S: sound"
            color: Theme.subtle
            font.pixelSize: 12
            elide: Text.ElideRight
            width: parent.width - 28
        }
    }
}
