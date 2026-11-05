import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.widgets

// The lock screen's design: the same as the login screen (sddm-theme), on the same blurred
// wallpaper (~/.cache/login/background.jpg, made by sddm-theme/sync.sh).
Item {
    id: root

    readonly property string user: Quickshell.env("USER") ?? ""
    property bool capsLock: false

    component Frost: Rectangle {
        id: frost
        property color tint: "transparent"
        property bool tintLeft: true
        height: 36
        radius: height / 2
        color: Theme.alpha(Theme.fg, 0.08)

        Rectangle {
            anchors.fill: parent
            radius: frost.radius
            visible: frost.tint.a > 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.alpha(frost.tint, frost.tintLeft ? 0.28 : 0) }
                GradientStop { position: 1; color: Theme.alpha(frost.tint, frost.tintLeft ? 0 : 0.28) }
            }
        }
    }

    component RoundButton: Frost {
        id: button
        property string icon
        property color iconColor: Theme.subtle
        signal clicked
        width: 36

        Icon {
            anchors.centerIn: parent
            name: button.icon
            color: button.iconColor
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(1, 1, 1, buttonMouse.containsMouse ? 0.12 : 0)
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    // caps lock state, from Hyprland (checked on lock and whenever Caps Lock is pressed)
    Process {
        id: caps
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.capsLock = JSON.parse(text).keyboards.some(k => k.main && k.capsLock);
                } catch (e) {}
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    Image {
        anchors.fill: parent
        source: "file://" + Quickshell.env("HOME") + "/.cache/login/background.jpg"
        fillMode: Image.PreserveAspectCrop
        cache: false
    }

    // everything but the background: fades in on lock, out on unlock
    Item {
        id: ui
        anchors.fill: parent
        opacity: Lock.unlocking ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Component.onCompleted: fadeIn.start()

        NumberAnimation {
            id: fadeIn
            target: ui
            property: "opacity"
            from: 0
            to: 1
            duration: 400
            easing.type: Easing.OutCubic
        }

        // top left: "arch is locked"
        Frost {
            anchors { top: parent.top; left: parent.left; topMargin: 14; leftMargin: 16 }
            tint: Theme.accent
            width: topRow.implicitWidth + 32

            Row {
                id: topRow
                anchors.centerIn: parent
                spacing: 7
                Label { text: "arch"; color: Theme.accent; font.pixelSize: 13; font.weight: Font.Bold }
                Label { text: "is locked"; font.pixelSize: 13; font.weight: Font.Bold }
            }
        }

        // centre: clock, avatar, name, password
        Column {
            anchors.centerIn: parent
            spacing: 28

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.date, "HH:mm")
                    font.pixelSize: 96
                    font.weight: Font.Light
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(clock.date, "dddd, d MMMM").toLowerCase()
                    color: Theme.subtle
                    font.letterSpacing: 1.1
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                // avatar: the initial on an accent gradient
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 84
                    height: 84
                    radius: 42
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accent2 }
                    }
                    Label {
                        anchors.centerIn: parent
                        text: root.user.charAt(0).toUpperCase()
                        color: Theme.ink
                        font.pixelSize: 30
                        font.weight: Font.Bold
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.user
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                // The password never shows, not even as dots: a thin line fills out from the
                // middle as you type (PasswordLine). Enter unlocks.
                Item {
                    id: field

                    readonly property int length: password.text.length
                    property bool wrong: false       // red, then empties, after a wrong password

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 400
                    height: 24                       // (room to click into it)
                    transform: Translate { id: shakeX }

                    PasswordLine {
                        id: line
                        anchors.fill: parent
                        length: field.length
                        wrong: field.wrong
                        busy: Lock.busy
                        focused: password.activeFocus
                    }

                    // the real input: invisible, it just takes the keys
                    TextInput {
                        id: password
                        anchors.fill: parent
                        color: "transparent"
                        selectionColor: "transparent"
                        selectedTextColor: "transparent"
                        cursorDelegate: Item {}
                        echoMode: TextInput.Password
                        focus: true
                        enabled: !Lock.busy
                        property int last: 0
                        onTextChanged: {
                            if (text.length > last)
                                line.keystroke();
                            else if (text.length < last)
                                line.erase();
                            last = text.length;
                        }
                        onAccepted: Lock.tryUnlock(text)
                        Keys.onEscapePressed: text = ""
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_CapsLock)
                                capsDelay.restart();
                        }

                        Timer {
                            id: capsDelay
                            interval: 100
                            onTriggered: caps.running = true
                        }
                    }

                    SequentialAnimation {
                        id: shake
                        NumberAnimation { target: shakeX; property: "x"; to: -8; duration: 50 }
                        NumberAnimation { target: shakeX; property: "x"; to: 8; duration: 80 }
                        NumberAnimation { target: shakeX; property: "x"; to: -8; duration: 80 }
                        NumberAnimation { target: shakeX; property: "x"; to: 8; duration: 80 }
                        NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 50 }
                    }

                    // a wrong password: the line shakes and turns red, then empties
                    Connections {
                        target: Lock
                        function onAttemptChanged() {
                            field.wrong = true;
                            shake.restart();
                            drain.restart();
                        }
                    }
                    Timer {
                        id: drain
                        interval: 450
                        onTriggered: {
                            password.text = "";
                            field.wrong = false;
                            password.forceActiveFocus();
                        }
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 16
                    text: root.capsLock ? "caps lock is on"
                        : Lock.busy ? "checking…"
                        : Lock.message !== "" ? Lock.message
                        : field.length === 0 ? "type your password" : ""
                    color: root.capsLock || Lock.failed ? Theme.accent2 : Theme.muted
                    font.pixelSize: 12
                }
            }
        }

        // bottom right: suspend, reboot, power off
        Row {
            anchors { bottom: parent.bottom; right: parent.right; bottomMargin: 18; rightMargin: 16 }
            spacing: 8

            RoundButton {
                icon: "suspend"
                onClicked: Quickshell.execDetached(["systemctl", "suspend"])
            }
            RoundButton {
                icon: "reboot"
                onClicked: Quickshell.execDetached(["systemctl", "reboot"])
            }
            RoundButton {
                icon: "power"
                iconColor: Theme.accent2
                tint: Theme.accent2
                tintLeft: false
                onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
            }
        }
    }
}
