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

        // top-left: the session, e.g. "hyprland on arch"
        Island {
            anchors { top: parent.top; left: parent.left; topMargin: 14; leftMargin: 16 }
            tintColor: root.accent
            width: topRow.implicitWidth + 32
            Row {
                id: topRow
                anchors.centerIn: parent
                spacing: 7
                Label { text: root.sessionName.toLowerCase() }
                Label { text: "on"; color: root.muted }
                Label { text: "arch"; color: root.accent }
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

                // The password never shows, not even as dots: a thin line fills out from the
                // middle as you type (full at 12 characters), and every key sends a bright
                // glint from the middle out to both ends; deleting sends it from the ends in.
                // Enter logs in.
                Item {
                    id: field

                    readonly property int length: password.text.length
                    readonly property real progress: Math.min(1, length / 12)
                    property bool wrong: false       // red, then empties, after a wrong password
                    property bool checking: false    // pulses while SDDM checks the password
                    property real breath: 0

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 400
                    height: 24                       // (room to click into it)
                    transform: Translate { id: shakeX }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: 4
                        radius: 2
                        color: root.tint(root.fg, password.activeFocus ? 0.2 : 0.12)
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }

                    Rectangle {
                        id: fill
                        anchors.centerIn: parent
                        width: parent.width * field.progress
                        height: 4
                        radius: 2
                        clip: true
                        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: field.wrong ? root.error : root.accent }
                            GradientStop { position: 1; color: field.wrong ? root.error : root.accent2 }
                        }

                        // glints running out from the middle (a few at once when typing fast)
                        Repeater {
                            id: ripples
                            property int next: 0
                            model: 6

                            Item {
                                id: ripple
                                property real travel: 0
                                property bool inward: false
                                function start(towardsMiddle) { inward = towardsMiddle; run.restart() }
                                anchors.fill: parent
                                opacity: 0

                                Repeater {
                                    model: [-1, 1]
                                    Rectangle {
                                        required property int modelData
                                        width: 28
                                        height: parent.height
                                        x: fill.width / 2 - width / 2 + modelData * ripple.travel * fill.width / 2
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.95) }
                                            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                                        }
                                    }
                                }

                                ParallelAnimation {
                                    id: run
                                    NumberAnimation { target: ripple; property: "travel"; from: ripple.inward ? 1 : 0; to: ripple.inward ? 0 : 1; duration: 380; easing.type: Easing.OutQuad }
                                    SequentialAnimation {
                                        NumberAnimation { target: ripple; property: "opacity"; from: 0; to: 1; duration: 60 }
                                        NumberAnimation { target: ripple; property: "opacity"; to: 0; duration: 320; easing.type: Easing.InQuad }
                                    }
                                }
                            }
                        }

                        // checking the password
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: root.fg
                            opacity: field.checking ? field.breath : 0
                        }
                    }

                    SequentialAnimation on breath {
                        running: field.checking
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.5; duration: 450; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 450; easing.type: Easing.InOutSine }
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
                        enabled: !field.checking
                        property int last: 0
                        onTextChanged: {
                            if (text.length !== last) ripples.itemAt(ripples.next++ % ripples.count).start(text.length < last)
                            last = text.length
                        }
                        onAccepted: root.doLogin()
                        Keys.onEscapePressed: text = ""
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

                    // after a wrong password the red line empties
                    Timer {
                        id: drain
                        interval: 450
                        onTriggered: {
                            password.text = ""
                            field.wrong = false
                            password.forceActiveFocus()
                        }
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
                    text: keyboard.capsLock ? "caps lock is on"
                        : field.checking ? "checking…"
                        : error !== "" ? error
                        : field.length === 0 ? "type your password" : ""
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
        if (!password.text || field.checking) { password.forceActiveFocus(); return }
        message.error = ""
        field.checking = true
        sddm.login(root.userName, password.text, root.sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            field.checking = false
            message.error = "wrong password"
            field.wrong = true      // shakes red, then empties
            shake.restart()
            drain.restart()
        }
        function onLoginSucceeded() {
            ui.opacity = 0      // leave only the blurred wallpaper Hyprland starts on
        }
    }
}
