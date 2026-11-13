import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import qs.notifications
import qs.services
import qs.widgets

// The dynamic island, in the middle of the bar. It morphs between three shapes:
//   compact   while the screen records, a red dot and the time (click it to stop);
//             your desktops as page dots, the date and time; while something plays,
//             the cover and a live audio visualizer too; a dot while an app is using the
//             microphone; the number of unread notifications. A short line along its
//             bottom: the scratchpad is showing (hover it for how to send a window back)
//   activity  for a moment, what just happened: a notification (a critical one stays
//             until you open the island), volume, the sound output switching, a
//             Bluetooth device, a new song, battery
//   open      click it: the time in large type (with what's playing and its controls
//             under it), the calendar, and the unread notifications; a click elsewhere
//             or Esc closes it
// Middle click plays / pauses. All notifications come through here (no other popups).
// The launcher opens out of it too, below the date and time (launcher/LauncherWindow.qml).
Item {
    id: root

    required property var bar
    property bool open: false
    onOpenChanged: {
        if (open) {
            Activities.seen();
            calendar.reset();
            calendar.forceActiveFocus();     // (its keys work straight away; Esc closes)
        }
    }
    // typing an event into the calendar: stays open until you're done (or click elsewhere)
    readonly property bool busy: open && calendar.editing

    readonly property var activity: Activities.current
    readonly property bool media: Media.player !== null && (Media.playing || Spectrum.active)
    readonly property Item view: open ? openView : activity ? activityView : compactView
    readonly property real radius: Theme.pillRadius

    // The launcher grows out of the island and shrinks back into it. It draws the island
    // itself as its top (the same pill, date and time, in the same place), so while it's
    // on this screen the island steps aside: from the moment the launcher starts to grow
    // until just before it's gone.
    readonly property bool lent: Launcher.shown && Launcher.screenName === bar.screen?.name
    readonly property bool covered: lent && Launcher.grow > 0.03
    // out of the frame or tucked into it (Bar.qml)
    opacity: covered ? 0 : Math.max(0, Math.min(1, bar.islandOut))
    Component.onCompleted: Launcher.addIsland(bar.screen?.name ?? "", root)

    Connections {
        target: Launcher
        function onOpenChanged() {
            if (Launcher.open)
                root.open = false;
        }
    }

    width: view.implicitWidth + (open ? 36 : 28)
    height: open ? openView.implicitHeight + 36 : Theme.islandHeight
    Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
    Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---------------------------------------------------------------- opening

    HoverHandler {
        id: hover
    }

    // ---------------------------------------------------------------- the scratchpad

    // Hyprland's scratchpad (its special workspace, Super+S) is showing on this screen: a
    // short line along the bottom of the island, and hovering the island says how to
    // send a window back.
    property string special: ""             // its name, while it's showing
    readonly property bool scratchpad: special !== ""
    readonly property string scratchpadHint: "You're on the scratchpad.\nSuper+Shift+1…0 sends the window back to that desktop; Super+S hides the scratchpad."

    Connections {
        target: Hyprland
        // "activespecial>>special:magic,DP-1" (opened) or ">>,DP-1" (closed)
        function onRawEvent(event) {
            if (event.name !== "activespecial")
                return;
            const comma = event.data.lastIndexOf(",");
            if (event.data.slice(comma + 1) === root.bar.monitor?.name)
                root.special = event.data.slice(0, comma);
        }
    }

    // (and whether it's showing already, when the shell starts)
    Process {
        id: specialNow
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const m = JSON.parse(text).find(m => m.name === root.bar.monitor?.name);
                    root.special = m?.specialWorkspace?.name ?? "";
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 300
        running: true
        onTriggered: specialNow.running = true
    }

    function updateHint() {
        if (hover.hovered && root.scratchpad && !root.open)
            root.bar.showTip(root, root.scratchpadHint);
        else
            root.bar.hideTip(root);
    }
    Connections {
        target: hover
        function onHoveredChanged() {
            root.updateHint();
        }
    }
    onScratchpadChanged: updateHint()

    // (opens on a click, below; closes on a click elsewhere or Esc: Bar.qml, Calendar.qml)

    // ---------------------------------------------------------------- the background
    // (the frame itself, coming down around the island as a tab: Bar.qml), plus tints

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        // an accent glow while music plays (up to the frame's edge, like the pills' tints)
        Rectangle {
            y: -Theme.tabPad
            width: parent.width
            height: parent.height + Theme.tabPad
            radius: parent.radius
            opacity: root.media && !root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.alpha(Theme.accent, 0.22) }
                GradientStop { position: 0.5; color: Theme.alpha(Theme.accent, 0) }
                GradientStop { position: 1; color: Theme.alpha(Theme.accent2, 0.22) }
            }
        }

        // the scratchpad is showing (above)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            width: root.scratchpad && !root.open ? Math.min(56, parent.width - 40) : 0
            height: 2.5
            radius: 1.25
            color: Theme.accent2
            opacity: root.scratchpad && !root.open ? 1 : 0
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        // a red tint for warnings (battery low)
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.alpha(Theme.error, 0.28)
            opacity: root.activity?.warn && !root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.hover
            opacity: hover.hovered && !root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // a click opens it (hovering only stretches the bar out: Bar.qml); middle click plays
    // or pauses
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: root.open ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                Media.player?.togglePlaying();
            else if (!root.open && root.bar.popup === "" && !root.lent)
                root.open = true;
        }
    }

    // the three views cross-fade while the glass changes shape around them
    Item {
        anchors.fill: parent
        clip: true

        // ---------------------------------------------------------------- compact
        IslandCompact {
            id: compactView
            monitor: root.bar.monitor
            anchors.centerIn: parent
            opacity: root.view === compactView ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        // ---------------------------------------------------------------- activity
        Row {
            id: activityView
            readonly property var a: root.activity ?? ({})
            readonly property bool volume: a.kind === "volume"
            readonly property bool track: a.kind === "track"
            readonly property var note: a.kind === "notification" ? a.notification : null

            anchors.centerIn: parent
            spacing: 10
            opacity: root.view === activityView ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Art {
                anchors.verticalCenter: parent.verticalCenter
                visible: activityView.track
                implicitWidth: 22
                implicitHeight: 22
                radius: 7
                source: Media.art
            }
            IconImage {
                readonly property string icon: activityView.note ? Notifs.icon(activityView.note) : ""
                anchors.verticalCenter: parent.verticalCenter
                visible: icon !== "" && status !== Image.Error
                source: icon
                implicitSize: 20
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: !activityView.track && activityView.note === null
                name: activityView.volume ? (Audio.bluetooth ? "bluetooth" : "volume") + (Audio.muted ? "-muted" : "")
                                          : activityView.a.icon ?? ""
                color: activityView.a.warn ? Theme.error : Audio.muted && activityView.volume ? Theme.muted : Theme.accent
            }

            // volume: a level bar and the percentage
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: activityView.volume
                width: 160
                height: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.15)

                Rectangle {
                    width: Math.max(parent.height, parent.width * Math.min(1, Audio.volume))
                    height: parent.height
                    radius: 3
                    Behavior on width { NumberAnimation { duration: 90 } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Audio.muted ? Theme.muted : Theme.accent }
                        GradientStop { position: 1; color: Audio.muted ? Theme.muted : Theme.accent2 }
                    }
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: activityView.volume
                text: Audio.muted ? "muted" : Math.round(Audio.volume * 100) + "%"
                color: Audio.muted ? Theme.muted : Theme.fg
                halo: true
            }

            // track / message: a title and a dimmer detail
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: !activityView.volume
                width: Math.min(implicitWidth, 300)
                text: activityView.track ? Media.title
                    : activityView.note ? (activityView.note.summary || activityView.note.appName)
                    : activityView.a.title ?? ""
                textFormat: Text.PlainText
                font.weight: Font.Bold
                color: activityView.a.warn ? Theme.error : Theme.fg
                elide: Text.ElideRight
                halo: true
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: !activityView.volume && text !== ""
                width: Math.min(implicitWidth, activityView.note ? 320 : 200)
                text: activityView.track ? Media.artist
                    : activityView.note ? Notifs.plain(activityView.note.body)
                    : activityView.a.detail ?? ""
                textFormat: Text.PlainText
                color: Theme.subtle
                elide: Text.ElideRight
                halo: true
            }
            Visualizer {
                anchors.verticalCenter: parent.verticalCenter
                visible: activityView.track
                count: 6
            }
        }

        // ---------------------------------------------------------------- open
        RowLayout {
            id: openView
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18
            spacing: 20
            opacity: root.view === openView ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            // the time, large, and under it what's playing (or that nothing is), filling
            // the height down to the bottom of the calendar
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.fillHeight: true
                Layout.topMargin: 4
                spacing: 18

                BigClock {
                    running: root.open
                }
                NowPlaying {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Theme.edge
            }
            Calendar {
                id: calendar
                Layout.alignment: Qt.AlignTop
                date: clock.date
                onDismiss: root.open = false
            }
            Rectangle {
                Layout.fillHeight: true
                visible: Notifs.count > 0
                implicitWidth: 1
                color: Theme.edge
            }
            NotificationList {
                Layout.alignment: Qt.AlignTop
                visible: Notifs.count > 0
                onActed: root.open = false      // (out of the way of what it opened)
            }
        }
    }
}
