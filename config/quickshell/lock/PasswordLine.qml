import QtQuick
import qs.services

// The password as a thin line: it fills out from the middle as you type (full at 12
// characters), and every key sends a bright glint from the middle out to both ends, so
// typing still shows once the line is full. Deleting sends the glints the other way, from
// the ends in to the middle. Call keystroke() for each typed character, erase() for each
// deletion.
Item {
    id: root

    property int length: 0
    property bool wrong: false          // red (after a wrong password)
    property bool busy: false           // pulses (while the password is checked)
    property bool focused: true

    readonly property real progress: Math.min(1, length / 12)
    readonly property color from: wrong ? Theme.error : Theme.accent
    readonly property color to: wrong ? Theme.error : Theme.accent2

    function keystroke() {
        ripples.itemAt(ripples.next++ % ripples.count).start(false);
    }

    function erase() {
        ripples.itemAt(ripples.next++ % ripples.count).start(true);
    }

    implicitWidth: 400
    implicitHeight: 24

    // the track
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: 4
        radius: 2
        color: Theme.alpha(Theme.fg, root.focused ? 0.2 : 0.12)
        Behavior on color { ColorAnimation { duration: 250 } }
    }

    // the fill, from the middle out
    Rectangle {
        id: fill
        anchors.centerIn: parent
        width: root.width * root.progress
        height: 4
        radius: 2
        clip: true
        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.from }
            GradientStop { position: 1; color: root.to }
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
                function start(towardsMiddle) {
                    inward = towardsMiddle;
                    run.restart();
                }
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
            color: Theme.fg
            opacity: root.busy ? breath.value : 0
        }
    }

    Item {
        id: breath
        visible: false
        property real value: 0
        SequentialAnimation on value {
            running: root.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.5; duration: 450; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 450; easing.type: Easing.InOutSine }
        }
    }
}
