import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// What the dynamic island shows when nothing's happening: while the screen records, a red
// dot and the time (click it to stop); your desktops as page dots (the
// one you're on a short bar; red: a window there wants attention; click one to go to
// it), the date and time; while something plays, the cover and a live audio visualizer
// too; a dot while an app is using the microphone; the number of unread notifications.
// Scroll on it to change desktops.
// (The island draws it, and so does the top of the launcher, which grows out of the
// island.)
Row {
    id: root

    property var monitor: Hyprland.focusedMonitor          // (its screen's)
    readonly property int workspace: monitor?.activeWorkspace?.id ?? 0
    // this screen's desktops, in order (not the special ones)
    property var desktops: Hyprland.workspaces.values
        .filter(w => w.id > 0 && (!root.monitor || w.monitor === root.monitor))
        .sort((a, b) => a.id - b.id)
    readonly property bool media: Media.player !== null && (Media.playing || Spectrum.active)

    spacing: 12

    // scroll: the next or previous desktop with windows (like Super+scroll)
    WheelHandler {
        property real sum: 0
        onWheel: event => {
            sum += event.angleDelta.y;
            if (Math.abs(sum) >= 120) {
                Hyprland.dispatch(`hl.dsp.focus({ workspace = "${sum > 0 ? "e-1" : "e+1"}" })`);
                sum = 0;
            }
        }
    }

    // the screen recording: a red dot and how long it's been going. Point at it and the
    // dot turns into a stop button; click to stop (services/Screenshot.qml).
    MouseArea {
        id: recording
        anchors.verticalCenter: parent.verticalCenter
        visible: Screenshot.recording
        implicitWidth: recordingRow.implicitWidth
        implicitHeight: 22
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Screenshot.stop()

        Row {
            id: recordingRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            RecordDot {
                anchors.verticalCenter: parent.verticalCenter
                size: 9
                stop: recording.containsMouse
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Screenshot.elapsedText
                color: Theme.error
                font.weight: Font.Bold
                halo: true
            }
        }
    }

    // the desktops, as page dots. The group grows and shrinks smoothly as desktops come
    // and go (the island resizes around it, so everything stays centred), and the bar
    // slides from dot to dot.
    Item {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.desktops.length > 0
        implicitWidth: dots.implicitWidth
        implicitHeight: 14
        clip: true
        Behavior on implicitWidth { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        Row {
            id: dots
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Repeater {
                model: root.desktops

                MouseArea {
                    id: dot
                    required property var modelData
                    readonly property bool current: modelData.id === root.workspace
                    readonly property bool urgent: (modelData.urgent ?? false) && !current

                    width: current ? 18 : 6
                    height: 14
                    Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // (Lua Hyprland: dispatches are Lua)
                    onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${modelData.id} })`)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: 3
                        color: dot.urgent ? Theme.error
                             : Theme.alpha(Theme.fg, dot.containsMouse ? 0.75 : 0.4)
                        Behavior on color { ColorAnimation { duration: 160 } }

                        // the one you're on
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            opacity: dot.current ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.accent }
                                GradientStop { position: 1; color: Theme.accent2 }
                            }
                        }
                    }
                }
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Art {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.media
        implicitWidth: 22
        implicitHeight: 22
        radius: 7
        source: Media.art
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, "ddd dd MMM")
        color: Theme.muted
        halo: true
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, "HH:mm")
        font.weight: Font.Bold
        halo: true
    }
    Visualizer {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.media || Spectrum.active
        count: 6
    }
    // an app is recording from the microphone
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: Audio.micInUse
        width: 7
        height: 7
        radius: 3.5
        color: Theme.accent2
    }
    // unread notifications
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: Notifs.count > 0
        width: Math.max(height, unread.implicitWidth + 10)
        height: 18
        radius: 9
        color: Notifs.urgent ? Theme.error : Theme.accent

        Label {
            id: unread
            anchors.centerIn: parent
            text: Notifs.count
            color: Theme.ink
            font.pixelSize: 11
            font.weight: Font.Bold
        }
    }
}
