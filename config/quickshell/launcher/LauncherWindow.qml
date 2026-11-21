import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services
import qs.widgets
import "fuzzy.js" as Fuzzy

// The launcher: it grows out of the frame on the focused screen, below the dynamic
// island's date and time, and closes back into it. Type to search; ↑/↓ (or Tab,
// Ctrl+J/K) to move, Enter to choose, Esc to go back or close. A click outside closes it.
PanelWindow {
    id: root

    readonly property var modes: ({
        main: mainMode,
        clipboard: clipboardMode,
        emoji: emojiMode,
        files: filesMode,
        calc: calcMode,
        qr: qrMode,
        shared: boxMode,
        windows: windowsMode,
        system: systemMode
    })
    readonly property var mode: modes[Launcher.mode] ?? null
    // (ScreenshotPanel.qml: "record" is the same menu, on its recording row)
    readonly property bool shooting: Launcher.mode === "screenshot" || Launcher.mode === "record"
    // (WallpaperPanel.qml: the search field narrows its pictures down, in a grid)
    readonly property bool picking: Launcher.mode === "wallpaper"
    readonly property bool custom: shooting                             // no search field or list
    readonly property bool split: (mode?.preview ?? null) !== null      // list + preview pane
    readonly property int rowHeight: 40
    readonly property int visibleRows: split ? 11 : 8    // taller with a preview pane

    // the main menu's answer (maths, conversions, time zones: MainMode.qml), worked out as
    // you type and shown on top of the list, picked; ↓ goes on into the list, ↑ back to it.
    // (It takes five of the list's rows, so the launcher doesn't change size; the rest of
    // the list scrolls under it.)
    readonly property bool hasAnswer: mode === mainMode && mainMode.answer !== null
    readonly property int count: mode?.rows.length ?? 0
    property bool atAnswer: true
    readonly property bool answerPicked: hasAnswer && (atAnswer || count === 0)

    // opens on the focused screen (chosen when it opens, so it doesn't jump)
    property var target: Quickshell.screens[0]

    // ---------- out of the frame, below the island
    // The launcher is part of the screen's frame (bar/Bar.qml): the island comes out of
    // the frame's top edge as a tab with its date and time (drawn here, in the island's
    // place, while the island steps aside: bar/DynamicIsland.qml), and the launcher
    // ("body") grows out from under the tab: first the tab stretches down, its lower
    // corners filling out, then the body spreads sideways, joined to the tab by corners
    // curving inwards; then the menu fades in. Closing runs it backwards.
    property Item island: null
    readonly property real grow: Launcher.grow                    // 0 -> 1 (springs a bit past 1)
    readonly property real g: Math.max(0, Math.min(1, grow))      // (without the spring)
    // how far the island's tab is out of the frame: the bar's own value, so the two match
    readonly property real out: island?.bar?.islandOut ?? 1

    readonly property real edge: Theme.frame                      // the frame's inner edge
    readonly property real pad: Theme.tabPad                      // around the island, in its tab
    readonly property real pillTop: Theme.pillTop
    readonly property real pillHeight: Theme.islandHeight
    // the island: as wide as it is at first (it may be showing something else), then
    // just the date and time
    property real pillWidth: Launcher.open ? header.implicitWidth + 28 : island?.width ?? header.implicitWidth + 28
    Behavior on pillWidth { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    readonly property real pillX: Math.round((width - pillWidth) / 2)  // centred, like the island
    readonly property real middle: pillX + pillWidth / 2
    // the tab around it
    readonly property real tabX: pillX - pad
    readonly property real tabWidth: pillWidth + 2 * pad
    readonly property real joint: edge + (Theme.barHeight - edge) * out   // its bottom: where the body starts
    readonly property real edgeCurve: Math.min(Theme.tabCurve, (joint - edge) / 2)  // inward, where it leaves the frame

    // the launcher's size (it changes between menus, smoothly)
    property real fullWidth: shooting ? 600 : picking ? 780 : split ? 980 : 640
    property real fullHeight: column.implicitHeight + 28
    Behavior on fullWidth { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on fullHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    readonly property real bodyWidth: tabWidth + (fullWidth - tabWidth) * grow
    readonly property real bodyHeight: Math.max(0, fullHeight * grow)
    readonly property real bodyX: Math.round(middle - bodyWidth / 2)

    // the corners
    readonly property real reach: Math.max(0, (bodyWidth - tabWidth) / 2)          // body past the tab, each side
    readonly property real tabBottomRadius: Math.min(Theme.tabRadius * Math.max(0, 1 - bodyHeight / 14),
                                                     Math.max(0, joint - edge - edgeCurve))   // filling out
    readonly property real inward: Math.min(Theme.tabCurve, reach / 2, Math.max(0, bodyHeight - 14) / 2)  // tab into body
    readonly property real shoulder: Math.min(Theme.tabRadius, reach - inward, bodyHeight / 3)  // body's top corners
    readonly property real bodyRadius: Math.max(0, Math.min(Theme.tabRadius, bodyHeight - shoulder, bodyWidth / 2))

    property real reveal: 0             // the menu inside: 0 hidden, 1 shown

    ParallelAnimation {
        id: opening
        NumberAnimation { target: Launcher; property: "grow"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
        SequentialAnimation {
            PauseAnimation { duration: 140 }
            NumberAnimation { target: root; property: "reveal"; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }
    }

    SequentialAnimation {
        id: closing
        ParallelAnimation {
            NumberAnimation { target: root; property: "reveal"; to: 0; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { target: Launcher; property: "grow"; to: 0; duration: 340; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: Launcher.shown = false }
    }

    screen: target
    visible: Launcher.shown
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // (while it closes, the keys and clicks already go back to the windows)
    WlrLayershell.keyboardFocus: Launcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: Launcher.open ? outside : null }

    // (solid like the frame: nothing to blur)

    MainMode { id: mainMode; query: root.mode === mainMode ? search.text : "" }
    ClipboardMode { id: clipboardMode; query: root.mode === clipboardMode ? search.text : "" }
    EmojiMode { id: emojiMode; query: root.mode === emojiMode ? search.text : "" }
    FilesMode { id: filesMode; query: root.mode === filesMode ? search.text : "" }
    CalcMode { id: calcMode; query: root.mode === calcMode ? search.text : "" }
    QrMode { id: qrMode; query: root.mode === qrMode ? search.text : "" }
    BoxMode { id: boxMode; query: root.mode === boxMode ? search.text : "" }
    WindowsMode { id: windowsMode; query: root.mode === windowsMode ? search.text : "" }
    SystemMode { id: systemMode; query: root.mode === systemMode ? search.text : "" }

    Connections {
        target: root.mode
        ignoreUnknownSignals: true
        function onClearQuery() { search.text = ""; }
    }

    // a fresh field for every menu
    function reset() {
        search.text = "";
        list.currentIndex = 0;
        atAnswer = true;
        mode?.opened();
        if (picking)
            walls.opened();
        search.forceActiveFocus();
    }

    Connections {
        target: Launcher
        function onOpenChanged() {
            if (Launcher.open) {
                // (reopened while still closing: it grows again from where it is)
                if (!Launcher.shown) {
                    root.target = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
                    Launcher.screenName = root.target.name;
                    root.island = Launcher.islands[root.target.name] ?? null;
                }
                closing.stop();
                root.reset();
                opening.restart();
            } else {
                opening.stop();
                closing.restart();
            }
        }
        function onModeChanged() {
            if (Launcher.open)
                root.reset();
        }
    }

    // the menu learns which row is selected (for its preview)
    Binding {
        target: root.mode
        when: root.mode !== null
        property: "current"
        value: root.mode?.rows[list.currentIndex] ?? null
    }

    function activate(how) {
        if (answerPicked)
            mainMode.useAnswer(how);
        else
            mode?.activate(mode.rows[list.currentIndex], how);
    }

    function move(by) {
        const n = count;
        if (n === 0)
            return;
        if (answerPicked) {                         // (from the answer down into the list)
            if (by > 0) {
                atAnswer = false;
                list.currentIndex = Math.min(n - 1, by - 1);
            }
        } else if (hasAnswer && list.currentIndex + by < 0) {
            atAnswer = true;                        // (up past the first row: the answer)
            list.currentIndex = 0;
        } else {
            list.currentIndex = Math.max(0, Math.min(n - 1, list.currentIndex + by));
        }
    }

    // a click outside the card closes the launcher
    MouseArea {
        id: outside
        anchors.fill: parent
        onClicked: Launcher.close()
    }

    // The outline, every corner rounded. Clockwise from the frame above the tab's left
    // (it overlaps the frame there, the same colour, so the two join): the tab leaving
    // the frame's edge (curving inwards), down to where it meets the body - there the
    // tab's own corner (while it fills out) or the inward curve into the body (once the
    // body is wider), the other being zero - then round the body and back up.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: o

            readonly property real e: root.edge
            readonly property real ec: root.edgeCurve
            readonly property real l: root.tabX
            readonly property real r: root.tabX + root.tabWidth
            readonly property real j: root.joint
            readonly property real bl: root.bodyX
            readonly property real br: root.bodyX + root.bodyWidth
            readonly property real b: root.joint + root.bodyHeight
            readonly property real pr: root.tabBottomRadius
            readonly property real ir: root.inward
            readonly property real sr: root.shoulder
            readonly property real rr: root.bodyRadius

            fillColor: Theme.frameColor
            strokeWidth: -1

            startX: o.l - o.ec
            startY: 0
            PathLine { x: o.r + o.ec; y: 0 }
            PathLine { x: o.r + o.ec; y: o.e }
            PathArc { x: o.r; y: o.e + o.ec; radiusX: o.ec; radiusY: o.ec; direction: PathArc.Counterclockwise }
            PathLine { x: o.r; y: o.j - o.pr - o.ir }
            PathArc { x: o.r - o.pr; y: o.j - o.ir; radiusX: o.pr; radiusY: o.pr }
            PathArc { x: o.r - o.pr + o.ir; y: o.j; radiusX: o.ir; radiusY: o.ir; direction: PathArc.Counterclockwise }
            PathLine { x: o.br - o.sr; y: o.j }
            PathArc { x: o.br; y: o.j + o.sr; radiusX: o.sr; radiusY: o.sr }
            PathLine { x: o.br; y: o.b - o.rr }
            PathArc { x: o.br - o.rr; y: o.b; radiusX: o.rr; radiusY: o.rr }
            PathLine { x: o.bl + o.rr; y: o.b }
            PathArc { x: o.bl; y: o.b - o.rr; radiusX: o.rr; radiusY: o.rr }
            PathLine { x: o.bl; y: o.j + o.sr }
            PathArc { x: o.bl + o.sr; y: o.j; radiusX: o.sr; radiusY: o.sr }
            PathLine { x: o.l + o.pr - o.ir; y: o.j }
            PathArc { x: o.l + o.pr; y: o.j - o.ir; radiusX: o.ir; radiusY: o.ir; direction: PathArc.Counterclockwise }
            PathArc { x: o.l; y: o.j - o.ir - o.pr; radiusX: o.pr; radiusY: o.pr }
            PathLine { x: o.l; y: o.e + o.ec }
            PathArc { x: o.l - o.ec; y: o.e; radiusX: o.ec; radiusY: o.ec; direction: PathArc.Counterclockwise }
            PathLine { x: o.l - o.ec; y: 0 }
        }
    }

    // clicks on the tab stay in the launcher
    MouseArea {
        x: root.tabX
        y: 0
        width: root.tabWidth
        height: root.joint
    }

    // the island: its date and time, where (and as) the island shows them; with its
    // accent glow while music plays, fading as the body grows
    Item {
        id: pill
        x: root.pillX
        y: root.pillTop
        width: root.pillWidth
        height: root.pillHeight
        opacity: Math.max(0, Math.min(1, root.out))
        transform: Translate { y: -(1 - root.out) * 40 }

        Rectangle {
            anchors.fill: parent
            radius: Theme.pillRadius
            opacity: header.media ? 1 - root.g : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.alpha(Theme.accent, 0.22) }
                GradientStop { position: 0.5; color: Theme.alpha(Theme.accent, 0) }
                GradientStop { position: 1; color: Theme.alpha(Theme.accent2, 0.22) }
            }
        }

        Item {
            anchors.fill: parent
            clip: true

            IslandCompact {
                id: header
                monitor: Hyprland.monitorFor(root.target)
                anchors.centerIn: parent
            }
        }
    }


    // the body, holding the menu (rounded clipping, so the menu stays inside the corners
    // while it grows)
    ClippingRectangle {
        id: card

        x: root.bodyX
        y: root.joint
        width: root.bodyWidth
        height: root.bodyHeight
        topLeftRadius: root.shoulder
        topRightRadius: root.shoulder
        bottomLeftRadius: root.bodyRadius
        bottomRightRadius: root.bodyRadius
        color: "transparent"

        // clicks inside the card stay in it
        MouseArea {
            anchors.fill: parent
        }

        // (stays put on screen while the body grows around it)
        Column {
            id: column
            x: Math.round(root.middle - width / 2) - card.x
            y: 14 - 8 * (1 - root.reveal)
            width: root.fullWidth - 28
            spacing: 12
            opacity: root.reveal

            // ---------- search field (collapsed under the screenshot menu, but keeps focus)
            Rectangle {
                width: parent.width
                height: root.custom ? 0 : 42
                opacity: root.custom ? 0 : 1
                clip: true
                radius: 21
                color: Theme.alpha(Theme.fg, 0.08)

                Label {
                    id: prompt
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.picking ? "wallpaper" : root.mode?.prompt ?? ""
                    color: Theme.accent
                    font.weight: Font.Bold
                }

                TextInput {
                    id: search
                    anchors.left: prompt.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    clip: true
                    focus: true
                    onTextChanged: {
                        list.currentIndex = 0;
                        root.atAnswer = true;
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        text: root.picking ? "search wallpapers…" : root.mode?.placeholder ?? ""
                        color: Theme.muted
                        font.pixelSize: 15
                    }

                    Keys.onPressed: event => {
                        if (root.shooting) {
                            event.accepted = shot.handle(event);
                            return;
                        }
                        if (root.picking && walls.handle(event)) {
                            event.accepted = true;
                            return;
                        }
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        const shift = event.modifiers & Qt.ShiftModifier;
                        const alt = event.modifiers & Qt.AltModifier;
                        let done = true;
                        if (event.key === Qt.Key_Escape)
                            Launcher.back();
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            root.activate(ctrl ? "ctrl" : shift ? "shift" : "enter");
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P)))
                            root.move(-1);
                        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N)))
                            root.move(1);
                        else if (event.key === Qt.Key_PageUp)
                            root.move(-root.visibleRows);
                        else if (event.key === Qt.Key_PageDown)
                            root.move(root.visibleRows);
                        else if (event.key === Qt.Key_Delete && shift)
                            root.activate("delete");
                        else if (alt && event.key === Qt.Key_1)
                            root.activate("alt");
                        else
                            done = false;
                        event.accepted = done;
                    }
                }
            }

            // ---------- hint (keys for this menu, progress, ...)
            Rectangle {
                width: parent.width
                height: 32
                visible: !root.custom && !root.picking && (root.mode?.hint ?? "") !== ""
                radius: 12
                color: Theme.alpha(Theme.fg, 0.08)

                Label {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode?.hint ?? ""
                    color: Theme.subtle
                    font.pixelSize: 13
                }
            }

            // ---------- the answer: what you typed on the left, the answer right, on top
            // of the list
            AnswerCard {
                width: parent.width
                height: 5 * root.rowHeight - parent.spacing
                visible: root.hasAnswer && !root.custom
                answer: mainMode.answer ?? []
                picked: root.answerPicked
                onChosen: {
                    root.atAnswer = true;
                    root.activate("enter");
                }
            }

            // ---------- results (and, for some menus, a preview of the selected one)
            Row {
                width: parent.width
                visible: !root.custom && !root.picking
                spacing: 12

                ListView {
                    id: list
                    width: root.split ? (parent.width - parent.spacing) / 2 : parent.width
                    height: (root.visibleRows - (root.hasAnswer ? 5 : 0)) * root.rowHeight
                    clip: true
                    model: root.mode?.rows ?? []
                    spacing: 0
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0
                    currentIndex: 0

                    delegate: MouseArea {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool current: ListView.isCurrentItem

                        width: ListView.view.width
                        height: root.rowHeight
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.atAnswer = false;
                            list.currentIndex = index;
                            root.activate("enter");
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 2
                            anchors.bottomMargin: 2
                            radius: 12
                            color: row.current && !root.answerPicked ? Theme.alpha(Theme.accent, 0.20)
                                 : row.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"
                        }

                        // icon, or the emoji itself
                        Item {
                            id: iconBox
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22

                            IconImage {
                                anchors.fill: parent
                                visible: !row.modelData.glyph && !row.modelData.swatch && thumb.status !== Image.Ready
                                asynchronous: true
                                source: {
                                    const i = row.modelData.icon ?? "";
                                    return i.startsWith("/") ? "file://" + i : i ? Quickshell.iconPath(i, true) : "";
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !!row.modelData.glyph
                                text: row.modelData.glyph ?? ""
                                font.pixelSize: 19
                            }
                            // a picture's thumbnail
                            ClippingRectangle {
                                anchors.fill: parent
                                visible: thumb.status === Image.Ready
                                radius: 5
                                color: "transparent"
                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    source: row.modelData.thumb ? "file://" + row.modelData.thumb : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 44
                                    sourceSize.height: 44
                                }
                            }
                            // a colour
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                visible: !!row.modelData.swatch
                                radius: width / 2
                                color: row.modelData.swatch ?? "transparent"
                                border.width: 1
                                border.color: Theme.edge
                            }
                        }

                        Label {
                            id: title
                            anchors.left: iconBox.right
                            anchors.leftMargin: 12
                            anchors.right: subtitle.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.StyledText
                            text: Fuzzy.highlight(row.modelData.title ?? "", row.modelData.positions, Theme.accent2)
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }

                        Label {
                            id: subtitle
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.subtitle ?? ""
                            color: Theme.muted
                            font.pixelSize: 13
                        }
                    }
                }

                Loader {
                    id: preview
                    width: root.split ? (parent.width - parent.spacing) / 2 : 0   // the same as the list
                    height: list.height
                    active: root.split
                    sourceComponent: root.mode?.preview ?? null
                }
            }

            // ---------- screenshots and recordings: what to take, a delay, drawing on it
            // after or the sound
            ScreenshotPanel {
                id: shot
                width: parent.width
                visible: root.shooting
            }

            // ---------- wallpapers: a grid of them, and how the new one comes in
            WallpaperPanel {
                id: walls
                width: parent.width
                visible: root.picking
                query: root.picking ? search.text : ""
            }
        }
    }
}
