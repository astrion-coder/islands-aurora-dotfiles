import QtQuick

// How far one of the bar's pills is out of the frame: 0 tucked in, 1 out. It comes out
// with a little spring (going a bit past 1) after `delay` ms, and goes back in after
// `hideDelay` ms, so the pills can follow one another.
Item {
    id: root

    property bool out: false
    property int delay: 0
    property int hideDelay: 0
    property real value: 0

    visible: false

    Component.onCompleted: if (out) showing.start()     // (out from the start: come out now)

    onOutChanged: {
        hiding.stop();
        showing.stop();
        (out ? showing : hiding).start();
    }

    SequentialAnimation {
        id: showing
        PauseAnimation { duration: root.delay }
        NumberAnimation { target: root; property: "value"; to: 1; duration: 440; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
    }

    SequentialAnimation {
        id: hiding
        PauseAnimation { duration: root.hideDelay }
        NumberAnimation { target: root; property: "value"; to: 0; duration: 260; easing.type: Easing.InCubic }
    }
}
