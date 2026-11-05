import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services
import qs.widgets

// One screen's frame and bar. The frame runs around the screen, as thick on every side,
// and the desktop is a rounded box inside it (FrameEdge.qml keeps windows inside). The
// bar is all in the dynamic island, a tab coming out of the frame's top edge in the
// middle. It shows the desktop you're on, the date and time (and what's happening).
// Point at the top edge, or at the island, and it stretches out sideways: cpu and memory
// come out on its left, tray, sound and power on its right; they go back in once the
// pointer leaves (not while one of their menus is open). Clicking the date and time
// opens the island's panel (the sides tuck in meanwhile); the launcher
// (launcher/LauncherWindow.qml) grows out of the island too.
//
// The window covers the whole screen, so that menus, tooltips and the frame are drawn in
// it (Hyprland blurs layer surfaces but not their popups). Only the top edge, the shown
// parts and an open menu take input (mask); everywhere else clicks go through.
PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property real popupMaxHeight: height - Theme.barHeight - Theme.frame - 16

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "islands-bar"
    WlrLayershell.layer: WlrLayer.Top
    // (the island's calendar takes keys once you click in it)
    WlrLayershell.keyboardFocus: popup !== "" || island.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // the top edge, the tabs that are out, and an open menu
    mask: Region {
        Region { x: 0; y: 0; width: root.width; height: Theme.frame }
        Region { x: tabIsland.l; width: tabIsland.r - tabIsland.l; height: tabIsland.out > 0.6 ? tabIsland.b : 0 }
        Region { item: popupLoader.item }
    }

    // the frame is solid; only the menus and tooltips over the desktop are glass
    BackgroundEffect.blurRegion: Region {
        Region { item: popupLoader.item; radius: 12 }
        Region { item: tip.visible ? tip : null; radius: 12 }
    }

    // ---------------------------------------------------------------- stretching out

    // hovered: the pointer is on anything that takes input here (see mask): the top edge,
    // the island, an open menu
    HoverHandler {
        id: hover
    }

    property bool revealed: false

    // (a moment's pause first, so a pointer passing the edge doesn't pull them out)
    Timer {
        interval: 120
        running: hover.hovered && !root.revealed && !island.lent
        onTriggered: root.revealed = true
    }
    Timer {
        interval: 450
        running: !hover.hovered && root.popup === "" && root.revealed
        onTriggered: root.revealed = false
    }
    // (the launcher covers the screen: put them away)
    Connections {
        target: island
        function onLentChanged() {
            if (island.lent)
                root.revealed = false;
        }
    }

    // how far the island is out (always: springing out when the shell starts), and its
    // sides (not while its panel is open)
    readonly property real islandOut: popIsland.value
    Pop { id: popIsland; out: true }
    Pop { id: popSides; out: root.revealed && !island.open && !island.lent }

    // ---------------------------------------------------------------- the frame

    // One pill's tab: the frame coming down around it (Theme.tabPad around it) as far as
    // it is out, its corners curving inwards where it leaves the frame's edge and rounded
    // at the bottom like the pill's own.
    component Tab: QtObject {
        property real left          // the pill, in the window
        property real width         // (0: no tab)
        property real bottom
        property real radius
        property real out
        readonly property real pad: width > 0 ? Theme.tabPad : 0
        readonly property real l: left - pad
        readonly property real r: left + width + pad
        readonly property real b: width > 0 ? Math.max(Theme.frame, Theme.frame + (bottom + pad - Theme.frame) * out) : Theme.frame
        readonly property real depth: b - Theme.frame
        readonly property real ir: Math.min(Theme.tabCurve, depth / 2)
        readonly property real br: Math.max(0, Math.min(radius + pad, depth - ir, (r - l) / 2))
    }

    // (one tab, around the island and its sides)
    Tab {
        id: tabIsland
        left: Math.min(leftSide.x, island.x)
        width: Math.max(rightSide.x + rightSide.width, island.x + island.width) - left
        bottom: Math.max(island.y + island.height, Theme.pillTop + Theme.islandHeight)
        radius: island.radius
        out: popIsland.value
    }

    // The frame: the screen minus a rounded box, with the island's tab coming down from
    // the box's top edge.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: frame

            readonly property real w: root.width
            readonly property real h: root.height
            readonly property real f: Theme.frame
            readonly property real cr: Theme.frameRadius
            readonly property real top: Theme.frame

            fillColor: Theme.frameColor
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill

            // the screen
            startX: 0
            startY: 0
            PathLine { x: frame.w; y: 0 }
            PathLine { x: frame.w; y: frame.h }
            PathLine { x: 0; y: frame.h }
            PathLine { x: 0; y: 0 }

            // the box, clockwise from its top left, with the tabs
            PathMove { x: frame.f + frame.cr; y: frame.top }
            PathLine { x: tabIsland.l - tabIsland.ir; y: frame.top }
            PathArc { x: tabIsland.l; y: frame.top + tabIsland.ir; radiusX: tabIsland.ir; radiusY: tabIsland.ir }
            PathLine { x: tabIsland.l; y: tabIsland.b - tabIsland.br }
            PathArc { x: tabIsland.l + tabIsland.br; y: tabIsland.b; radiusX: tabIsland.br; radiusY: tabIsland.br; direction: PathArc.Counterclockwise }
            PathLine { x: tabIsland.r - tabIsland.br; y: tabIsland.b }
            PathArc { x: tabIsland.r; y: tabIsland.b - tabIsland.br; radiusX: tabIsland.br; radiusY: tabIsland.br; direction: PathArc.Counterclockwise }
            PathLine { x: tabIsland.r; y: frame.top + tabIsland.ir }
            PathArc { x: tabIsland.r + tabIsland.ir; y: frame.top; radiusX: tabIsland.ir; radiusY: tabIsland.ir }
            PathLine { x: frame.w - frame.f - frame.cr; y: frame.top }
            PathArc { x: frame.w - frame.f; y: frame.top + frame.cr; radiusX: frame.cr; radiusY: frame.cr }
            PathLine { x: frame.w - frame.f; y: frame.h - frame.f - frame.cr }
            PathArc { x: frame.w - frame.f - frame.cr; y: frame.h - frame.f; radiusX: frame.cr; radiusY: frame.cr }
            PathLine { x: frame.f + frame.cr; y: frame.h - frame.f }
            PathArc { x: frame.f; y: frame.h - frame.f - frame.cr; radiusX: frame.cr; radiusY: frame.cr }
            PathLine { x: frame.f; y: frame.top + frame.cr }
            PathArc { x: frame.f + frame.cr; y: frame.top; radiusX: frame.cr; radiusY: frame.cr }
        }
    }

    // ---------------------------------------------------------------- actions

    function script(name) {
        return Quickshell.shellPath("scripts/" + name);
    }

    function run(command) {
        closePopup();
        Quickshell.execDetached(command);
    }

    // pavucontrol as a dropdown under the bar (placed by the "bar-popups" window rule)
    function openMixer() {
        run([script("popup.sh"), "org.pulseaudio.pavucontrol", "pavucontrol"]);
    }

    // x for a card of width w centred under item, kept inside the frame
    function placeUnder(item, w) {
        if (!item)
            return 0;
        const centre = item.mapToItem(null, item.width / 2, 0).x;
        const margin = Theme.frame + 8;
        return Math.max(margin, Math.min(width - margin - w, Math.round(centre - w / 2)));
    }

    // ---------------------------------------------------------------- the island

    // The date and time stay in the middle of the screen; the sides grow out from the
    // island's edges (and slide back into them), each with a thin line between it and
    // the island.
    DynamicIsland {
        id: island
        bar: root
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.pillTop
        enabled: popIsland.value > 0.6
        transform: Translate { y: -(1 - popIsland.value) * 40 }
    }

    // its left: cpu and memory
    Item {
        id: leftSide
        anchors.right: island.left
        anchors.rightMargin: Theme.spacing * Math.min(1, popSides.value)
        // (from the frame's edge, so the pills' tints can reach up to it: Island.qml)
        y: Theme.frame
        width: leftPills.implicitWidth * Math.max(0, popSides.value)
        height: Theme.islandHeight + Theme.tabPad
        clip: true

        Row {
            id: leftPills
            anchors.right: parent.right
            y: Theme.tabPad
            spacing: Theme.spacing
            opacity: Math.min(1, popSides.value)
            enabled: popSides.value > 0.6

            Stats {
                id: stats
                bar: root
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 18
                color: Theme.edge
            }
        }
    }

    // its right: tray, sound and power
    Item {
        id: rightSide
        anchors.left: island.right
        anchors.leftMargin: Theme.spacing * Math.min(1, popSides.value)
        y: Theme.frame
        width: rightPills.implicitWidth * Math.max(0, popSides.value)
        height: Theme.islandHeight + Theme.tabPad
        clip: true

        Row {
            id: rightPills
            y: Theme.tabPad
            spacing: Theme.spacing
            opacity: Math.min(1, popSides.value)
            enabled: popSides.value > 0.6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 18
                color: Theme.edge
            }
            StatusIsland {
                id: statusIsland
                bar: root
            }
            PowerButton {
                id: power
                bar: root
            }
        }
    }

    // ---------------------------------------------------------------- menus

    property string popup: ""            // "power", "sound" or "tray"
    property Item popupAnchor: null
    property var popupData: null         // the tray item, for "tray"

    function togglePopup(name, anchor, data) {
        if (popup === name && popupAnchor === anchor) {
            closePopup();
            return;
        }
        hideTip(tipAnchor);
        island.open = false;
        popupAnchor = anchor;
        popupData = data ?? null;
        popup = name;
    }

    function closePopup() {
        popup = "";
        popupAnchor = null;
        popupData = null;
    }

    // a click anywhere outside the bar closes the menu
    HyprlandFocusGrab {
        windows: [root]
        active: root.popup !== ""
        onCleared: root.closePopup()
    }

    // likewise the island's panel (it opens on a click and stays until you're done)
    HyprlandFocusGrab {
        windows: [root]
        active: island.open
        onCleared: island.open = false
    }

    Component {
        id: powerMenu
        PowerMenu { bar: root }
    }
    Component {
        id: soundMenu
        SoundMenu { bar: root }
    }
    Component {
        id: trayMenu
        TrayMenu { bar: root }
    }

    Loader {
        id: popupLoader
        active: root.popup !== ""
        sourceComponent: root.popup === "power" ? powerMenu
                       : root.popup === "sound" ? soundMenu
                       : root.popup === "tray" ? trayMenu : null
        x: root.placeUnder(root.popupAnchor, item?.width ?? 0)
        y: Theme.barHeight + 4
        focus: true
        Keys.onEscapePressed: root.closePopup()
        onLoaded: {
            item.opacity = 0;
            fadeIn.restart();
            forceActiveFocus();
        }

        NumberAnimation {
            id: fadeIn
            target: popupLoader.item
            property: "opacity"
            to: 1
            duration: 110
            easing.type: Easing.OutCubic
        }
    }

    // ---------------------------------------------------------------- tooltips

    property Item tipAnchor: null
    property string tipText: ""
    property bool tipShown: false

    function showTip(item, text) {
        tipAnchor = item;
        tipText = text;
        tipShown = false;
        tipDelay.restart();
    }

    function updateTip(item, text) {
        if (tipAnchor === item)
            tipText = text;
    }

    function hideTip(item) {
        if (item && tipAnchor !== item)
            return;
        tipDelay.stop();
        tipShown = false;
        tipAnchor = null;
    }

    Timer {
        id: tipDelay
        interval: 450
        onTriggered: root.tipShown = true
    }

    Card {
        id: tip
        visible: root.tipShown && root.tipAnchor !== null && root.popup === "" && !island.open && root.tipText !== ""
        x: root.placeUnder(root.tipAnchor, width)
        y: Theme.barHeight + 4
        width: tipLabel.implicitWidth + 16
        height: tipLabel.implicitHeight + 16

        Label {
            id: tipLabel
            x: 8
            y: 8
            leftPadding: 4
            rightPadding: 4
            text: root.tipText
        }
    }
}
