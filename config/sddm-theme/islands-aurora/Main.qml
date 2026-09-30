// Islands Aurora — SDDM login screen
// Frosted islands over the blurred wallpaper (dynamic/background.jpg), coloured from
// the wallpaper palette (theme.conf.user). No glows, borders or sheen, like the bar.
// On login everything but the background fades out, so the hand-off to Hyprland
// (which starts on the same blurred image, then fades to the sharp wallpaper) is seamless.

import QtQuick 2.15

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "black"

    readonly property color fg: config.fg
    readonly property color subtle: config.subtle
    readonly property color muted: config.muted
    readonly property color accent: config.accent
    readonly property color accent2: config.accent2
    readonly property color ink: config.ink
    readonly property color base: config.base
    readonly property color error: config.error
    readonly property string fontFamily: config.font

    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ---------- model readers (user / session names by index) ----------
    Item {
        visible: false
        Repeater { id: users;    model: userModel;    delegate: Item { property string uname: model.name } }
        Repeater { id: sessions; model: sessionModel; delegate: Item { property string sname: model.name } }
    }
    property int userIndex: Math.max(userModel.lastIndex, 0)
    property int sessionIndex: Math.max(sessionModel.lastIndex, 0)
    readonly property string userName: users.count > userIndex && users.itemAt(userIndex)
                                       ? users.itemAt(userIndex).uname : userModel.lastUser
    readonly property string sessionName: sessions.count > sessionIndex && sessions.itemAt(sessionIndex)
                                          ? sessions.itemAt(sessionIndex).sname : ""

    // ---------- building blocks ----------
    // Frosted pill. The background is already blurred and darkened, so a faint light
    // frost (not a dark fill) is what makes islands read as glass here.
    component Island: Rectangle {
        id: isl
        property color tintColor: "transparent"
        property bool tintLeft: true
        height: 36
        radius: height / 2
        color: root.tint(root.fg, 0.08)
        Rectangle {           // accent tint fading across the pill
            anchors.fill: parent
            radius: isl.radius
            visible: isl.tintColor.a > 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.tint(isl.tintColor, isl.tintLeft ? 0.28 : 0) }
                GradientStop { position: 1; color: root.tint(isl.tintColor, isl.tintLeft ? 0 : 0.28) }
            }
        }
    }

    component Label: Text {
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: true
    }

    // Hover lift + pointer cursor, like the bar's modules
    component Hover: MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(1, 1, 1, parent.containsMouse ? 0.12 : 0)
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    // Island holding "label value" that cycles through options on click
    component Picker: Island {
        id: picker
        property string label
        property string value
        signal clicked()
        width: pickRow.implicitWidth + 32
        Row {
            id: pickRow
            anchors.centerIn: parent
            spacing: 8
            Label { text: picker.label; color: root.muted }
            Label { text: picker.value }
        }
        Hover { onClicked: picker.clicked() }
    }

    component RoundButton: Island {
        id: rb
        property string icon
        signal clicked()
        width: 36
        Image {
            anchors.centerIn: parent
            source: rb.icon
            sourceSize: Qt.size(14, 14)
        }
        Hover { onClicked: rb.clicked() }
    }

    // ---------- background ----------
    Image {
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
    }

    // ---------- everything else (fades out on successful login) ----------
    Item {
        id: ui
        anchors.fill: parent
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        // top-left: distro · session
        Island {
            anchors { top: parent.top; left: parent.left; topMargin: 14; leftMargin: 16 }
            tintColor: root.accent
            width: topRow.implicitWidth + 32
            Row {
                id: topRow
                anchors.centerIn: parent
                spacing: 7
                Label { text: "arch"; color: root.accent }
                Label { text: "·"; color: root.muted }
                Label { text: root.sessionName.toLowerCase() }
            }
        }

        // centre: clock, avatar, name, password
        Column {
            anchors.centerIn: parent
            spacing: 28

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Text {
                    id: clock
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 96
                    font.weight: Font.Light
                    text: Qt.formatTime(new Date(), "HH:mm")
                }
                Text {
                    id: dateText
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.subtle
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    font.letterSpacing: 1.1
                    text: Qt.formatDate(new Date(), "dddd, d MMMM").toLowerCase()
                }
                Timer {
                    interval: 5000; running: true; repeat: true
                    onTriggered: {
                        clock.text = Qt.formatTime(new Date(), "HH:mm")
                        dateText.text = Qt.formatDate(new Date(), "dddd, d MMMM").toLowerCase()
                    }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Rectangle {   // avatar: initial on an accent gradient
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 84; height: 84; radius: 42
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: root.accent }
                        GradientStop { position: 1; color: root.accent2 }
                    }
                    Text {
                        anchors.centerIn: parent
                        color: root.ink
                        font.family: root.fontFamily
                        font.pixelSize: 30
                        font.bold: true
                        text: root.userName.charAt(0).toUpperCase()
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: 15
                    text: root.userName
                }

                Island {
                    id: field
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 320
                    height: 48
                    color: root.tint(root.fg, password.activeFocus ? 0.13 : 0.08)
                    Behavior on color { ColorAnimation { duration: 250 } }
                    transform: Translate { id: shakeX }

                    Image {
                        id: lockIcon
                        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                        source: "dynamic/lock.svg"
                        sourceSize: Qt.size(15, 15)
                    }

                    // The real input is invisible; animated dots (below) stand in for the
                    // characters, like hyprlock: each pops in, deleted ones shrink away.
                    TextInput {
                        id: password
                        anchors { left: lockIcon.right; right: go.left; leftMargin: 10; rightMargin: 10
                                  verticalCenter: parent.verticalCenter }
                        color: "transparent"
                        selectionColor: "transparent"
                        selectedTextColor: "transparent"
                        cursorDelegate: Item {}
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        echoMode: TextInput.Password
                        clip: true
                        focus: true
                        onAccepted: root.doLogin()
                        Keys.onEscapePressed: text = ""
                        onTextChanged: {
                            while (dotModel.count < text.length) dotModel.append({})
                            while (dotModel.count > text.length) dotModel.remove(dotModel.count - 1)
                        }

                        ListModel { id: dotModel }
                        ListView {
                            id: dots
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            height: 14
                            orientation: ListView.Horizontal
                            interactive: false
                            spacing: 7
                            clip: true
                            model: dotModel
                            // Once the field is full, glide the row left as each dot pops in
                            // (and back on delete) so the newest dot stays in view.
                            onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
                            Behavior on contentX { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            delegate: Rectangle {
                                width: 10; height: 10; radius: 5
                                y: 2
                                color: root.fg
                            }
                            add: Transition {
                                NumberAnimation { property: "scale";   from: 0; to: 1; duration: 200; easing.type: Easing.OutBack }
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                            }
                            remove: Transition {
                                NumberAnimation { property: "scale";   to: 0; duration: 150; easing.type: Easing.InQuad }
                                NumberAnimation { property: "opacity"; to: 0; duration: 150 }
                            }
                            displaced: Transition {
                                NumberAnimation { property: "x"; duration: 150; easing.type: Easing.OutCubic }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !parent.text
                            color: root.muted
                            font.family: root.fontFamily
                            font.pixelSize: 14
                            text: "password"
                        }
                    }

                    Rectangle {
                        id: go
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        width: 36; height: 36; radius: 18
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.accent }
                            GradientStop { position: 1; color: root.accent2 }
                        }
                        scale: goMouse.pressed ? 0.94 : (goMouse.containsMouse ? 1.06 : 1)
                        Behavior on scale { NumberAnimation { duration: 150 } }
                        Image { anchors.centerIn: parent; source: "dynamic/arrow.svg"; sourceSize: Qt.size(15, 15) }
                        MouseArea {
                            id: goMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.doLogin()
                        }
                    }

                    SequentialAnimation {
                        id: shake
                        loops: 1
                        NumberAnimation { target: shakeX; property: "x"; to: -8; duration: 50 }
                        NumberAnimation { target: shakeX; property: "x"; to: 8;  duration: 80 }
                        NumberAnimation { target: shakeX; property: "x"; to: -8; duration: 80 }
                        NumberAnimation { target: shakeX; property: "x"; to: 8;  duration: 80 }
                        NumberAnimation { target: shakeX; property: "x"; to: 0;  duration: 50 }
                    }
                }

                Text {
                    id: message
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 16
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    property string error: ""
                    color: keyboard.capsLock || error ? root.accent2 : root.muted
                    text: keyboard.capsLock ? "caps lock is on" : error
                }
            }
        }

        // bottom-left: user, session, keyboard layout
        Row {
            anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 18; leftMargin: 16 }
            spacing: 8

            Picker {
                label: "user"
                value: root.userName
                tintColor: root.accent
                onClicked: {
                    root.userIndex = (root.userIndex + 1) % Math.max(users.count, 1)
                    password.text = ""; message.error = ""; password.forceActiveFocus()
                }
            }
            Picker {
                label: "session"
                value: root.sessionName
                onClicked: {
                    root.sessionIndex = (root.sessionIndex + 1) % Math.max(sessions.count, 1)
                    password.forceActiveFocus()
                }
            }
            Picker {
                label: "kbd"
                visible: keyboard.layouts.length > 0
                value: keyboard.layouts.length > 0 ? keyboard.layouts[keyboard.currentLayout].shortName : ""
                onClicked: {
                    keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
                    password.forceActiveFocus()
                }
            }
        }

        // bottom-right: power
        Row {
            anchors { bottom: parent.bottom; right: parent.right; bottomMargin: 18; rightMargin: 16 }
            spacing: 8
            RoundButton { icon: "dynamic/suspend.svg"; visible: sddm.canSuspend; onClicked: sddm.suspend() }
            RoundButton { icon: "dynamic/reboot.svg";  visible: sddm.canReboot;  onClicked: sddm.reboot() }
            RoundButton { icon: "dynamic/power.svg";   visible: sddm.canPowerOff; onClicked: sddm.powerOff()
                          tintColor: root.accent2; tintLeft: false }
        }
    }

    // ---------- login ----------
    function doLogin() {
        if (!password.text) { password.forceActiveFocus(); return }
        message.error = ""
        sddm.login(root.userName, password.text, root.sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            message.error = "wrong password"
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
        function onLoginSucceeded() {
            ui.opacity = 0      // leave only the blurred wallpaper Hyprland starts on
        }
    }
}
