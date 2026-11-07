import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.widgets

// The island's calendar. A month at a time, with week numbers; days from the months
// either side are shown faintly and can be picked too. Today is filled in, the picked
// day ringed, and a dot marks days with events. Events are your calendars through khal,
// kept in step with your Mac and phone (services/Events.qml).
//   ‹ ›, the scroll wheel        another month (or year, or years)
//   the title                    months of the year, then years, to jump far
//   today                        back to today
//   a day                        its events below, and a box to add one: "14:30 dentist"
//                                on top (the buttons beside it pick the calendar and make
//                                it weekly, monthly or yearly), notes under it (Tab goes
//                                there; Shift+Enter: a new line). Double-click a day to
//                                start typing at once.
//   an event                     drag it onto another day to move it there, at the same
//                                time (hold it over ‹ or › for another month; Esc lets go
//                                of it); hold Ctrl as you drop it for a copy. A repeating
//                                one asks: just that day's, or all of them (Enter: just
//                                that day's)? Double-click it, or its pencil, to change
//                                it: it comes into the field as you'd type it ("09:30–10:00
//                                Standup"), its notes under it, its calendar and how often
//                                it repeats beside it; Enter saves, Esc leaves it. ×
//                                deletes it (a repeating one: that day's; "delete all"
//                                then takes the rest).
//                                Click one to open it out (its whole title, place, notes
//                                and link), again to close it; click its notes, or "add
//                                notes", to change them. A ⌄ marks one with more to see.
//   undo                         after each change, for a few seconds (Ctrl+Z any time)
// Changes show at once and go to your Mac and phone straight after (services/Events.qml).
// Keys, once you've clicked in it: ←/→ a day, ↑/↓ a week, Page Up/Down a month, Home
// today, Enter adds an event, Ctrl+Z undoes, Esc goes back (and closes the island).
FocusScope {
    id: root

    property date date: new Date()           // now (the island's clock)
    readonly property bool editing: field.activeFocus || notes.activeFocus
    signal dismiss                           // Esc with nothing left to go back from

    // (set by reset(), not bound to the clock: they'd jump back every minute)
    property var selected: new Date()
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property string mode: "days"             // "days", "months" or "years"
    property string repeat: ""               // for the next event added
    property string calendar: ""             // which calendar it goes in
    property string expanded: ""             // the event showing its notes (uid@day)

    // dragging an event onto another day (the DragHandler on each event, below)
    property var dragged: null               // the event
    property var dragFrom: null              // the day it was picked up from
    property var dropDay: null               // the day under the pointer (null: nowhere to drop it)
    property bool dragCopy: false            // Ctrl held: a copy
    property bool dragCancelled: false       // Esc while dragging
    property point dragPoint: Qt.point(0, 0) // the pointer, in this item
    property int flipBy: 0                   // over ‹ or ›: to another month in a moment
    property var landed: null                // the day something just landed on (it flashes)
    property var asking: null                // a repeating one dropped: { event, from, to }

    // changing an event: its text in the field, and its calendar and repeat ("-": as is)
    property var changing: null
    property string editCalendar: "-"
    property string editRepeat: "-"
    readonly property string shownCalendar: changing ? (editCalendar === "-" ? changing.calendar : editCalendar) : calendarName
    readonly property string shownRepeat: changing ? (editRepeat === "-" ? changing.freq ?? "" : editRepeat) : repeat

    property string notice: ""               // what just happened ("moved to Fri 6 Nov"), with undo
    property var offerAll: null              // one day's of a repeating event just deleted: the rest can go too
    property int undoable: 0                 // changes made here that undo can put back
    readonly property string calendarName: Events.calendars.some(c => c.name === calendar) ? calendar
                                         : Events.calendars[0]?.name ?? ""

    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7          // 0 = Sunday
    readonly property var gridStart: {
        const first = new Date(viewYear, viewMonth, 1);
        return new Date(viewYear, viewMonth, 1 - (first.getDay() - firstDay + 7) % 7);
    }
    readonly property int yearsFrom: viewYear - viewYear % 12

    readonly property int cellWidth: 44
    readonly property int cellHeight: 38
    readonly property int weekWidth: 30
    readonly property int rowHeight: 34              // an event in the list

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight
    Component.onCompleted: reset()

    // khal looks up the six weeks on show
    onGridStartChanged: Events.show(gridStart, 42)

    // ---------------------------------------------------------------- moving around

    function today() {
        return Events.dayOf(date);
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    // back to today, the way the island opens
    function reset() {
        mode = "days";
        expanded = "";
        repeat = "";
        field.text = "";
        notes.text = "";
        field.focus = false;
        select(today());
        Events.show(gridStart, 42);
        Events.sync(false);          // (picks up changes from your Mac; once a minute at most)
    }

    function show(year, month) {
        const d = new Date(year, month, 1);
        const by = (d.getFullYear() - viewYear) * 12 + d.getMonth() - viewMonth;
        if (by === 0)
            return;
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
        slideIn(by);
    }

    function select(d) {
        selected = Events.dayOf(d);
        show(d.getFullYear(), d.getMonth());
    }

    function moveBy(days) {
        select(new Date(selected.getFullYear(), selected.getMonth(), selected.getDate() + days));
    }

    // ‹ / › and the wheel: a month, a year or twelve years, depending on the view
    function step(by) {
        if (mode === "days")
            show(viewYear, viewMonth + by);
        else if (mode === "months")
            show(viewYear + by, viewMonth);
        else
            show(viewYear + 12 * by, viewMonth);
    }

    function slideIn(by) {
        slide.from = by > 0 ? 24 : -24;
        flip.restart();
    }

    function relative(d) {
        const days = Math.round((Events.dayOf(d) - today()) / 86400000);
        return days === 0 ? "today" : days === 1 ? "tomorrow" : days === -1 ? "yesterday"
             : days > 0 ? `in ${days} days` : `${-days} days ago`;
    }

    // notes as rich text, their web addresses as links
    function linkify(text) {
        const safe = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return safe.replace(/https?:\/\/[^\s<>"']*[^\s<>"'.,;:!?)\]]/g, url => `<a href="${url}">${url}</a>`)
                   .replace(/\n/g, "<br>");
    }

    function openLink(url) {
        url = url.replace(/&amp;/g, "&");
        if (/^https?:\/\//.test(url))
            Quickshell.execDetached(["xdg-open", url]);
    }

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7);
    }

    // ---------------------------------------------------------------- changing events

    function tell(text) {
        notice = text;
        offerAll = null;
        noticeTimer.restart();
    }

    function undo() {
        if (undoable <= 0) {
            tell("nothing to undo");
            return;
        }
        undoable--;
        Events.undo();
        tell("undone");
    }

    // the day under the pointer (a point in the window), or null
    function dayAt(scenePos) {
        if (mode !== "days")
            return null;
        const p = page.mapFromItem(null, scenePos.x, scenePos.y);
        const col = Math.floor((p.x - weekWidth) / cellWidth), row = Math.floor((p.y - cellHeight) / cellHeight);
        if (p.x < weekWidth || col < 0 || col > 6 || row < 0 || row > 5)
            return null;
        return new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + row * 7 + col);
    }

    function over(item, scenePos) {
        const p = item.mapFromItem(null, scenePos.x, scenePos.y);
        return p.x >= 0 && p.y >= 0 && p.x < item.width && p.y < item.height;
    }

    function startDrag(e, scenePos) {
        if (changing)
            stopEditing();
        mode = "days";
        expanded = "";
        asking = null;
        dragged = e;
        dragFrom = selected;
        dragCancelled = false;
        dragTo(scenePos, 0);
    }

    function dragTo(scenePos, modifiers) {
        dragPoint = mapFromItem(null, scenePos.x, scenePos.y);
        if (modifiers & Qt.ControlModifier)
            dragCopy = true;
        dropDay = dragCancelled ? null : dayAt(scenePos);
        flipBy = dragCancelled ? 0 : over(prevButton, scenePos) ? -1 : over(nextButton, scenePos) ? 1 : 0;
    }

    // (let go: called once the event's row is done with its own signal)
    function endDrag() {
        const e = dragged, from = dragFrom, to = dropDay, copy = dragCopy;
        dragged = null;
        dropDay = null;
        dragCopy = false;
        flipBy = 0;
        if (!e || !to || dragCancelled)
            return;
        if (copy)
            moveEvent(e, from, to, "copy");
        else if (sameDay(to, from))
            return;
        else if (e.repeat)
            asking = { event: e, from: from, to: to };
        else
            moveEvent(e, from, to, "one");
    }

    function moveEvent(e, from, to, scope) {
        asking = null;
        Events.move(e, from, to, scope);
        undoable++;
        landed = to;
        landTimer.restart();
        tell((scope === "copy" ? "copied to " : "moved to ") + Qt.formatDate(to, "ddd d MMM"));
    }

    // (a repeating one: just that day's, unless it's "all")
    function deleteEvent(e, scope) {
        const one = scope === "one" && e.repeat;
        Events.remove(e, selected, one ? "one" : "all");
        undoable++;
        tell(one ? "deleted this day's “" + e.title + "”" : "deleted “" + e.title + "”");
        if (one)
            offerAll = e;
    }

    // (toNotes: the cursor at the end of its notes, not its title)
    function startEditing(e, toNotes) {
        asking = null;
        expanded = "";
        editCalendar = "-";
        editRepeat = "-";
        changing = e;
        field.text = Events.describe(e);
        notes.text = e.description ?? "";
        const into = toNotes ? notes : field;
        into.forceActiveFocus();
        into.cursorPosition = into.text.length;
    }

    function stopEditing() {
        changing = null;
        field.text = "";
        notes.text = "";
    }

    // out of the field and its notes, keys back to the calendar (focus alone wouldn't do:
    // this is a FocusScope, which hands it straight back to whichever had it)
    function unfocus() {
        field.focus = false;
        notes.focus = false;
        forceActiveFocus();
    }

    // (clicking anywhere but the field and its notes leaves the event as it was)
    function leftFields() {
        if (changing && !field.activeFocus && !notes.activeFocus)
            stopEditing();
    }

    // Enter in the field or its notes: add the event, or save the one being changed
    function submit() {
        const text = notes.text.replace(/[\u2028\u2029]/g, "\n");
        if (changing) {
            const e = changing;
            const before = field.text;
            changing = null;
            const result = Events.edit(e, before, editRepeat, editCalendar, text);
            if (result === "empty") {
                changing = e;           // (a title is needed: stays as it is)
                field.forceActiveFocus();
                return;
            }
            if (result === "changed") {
                undoable++;
                tell("changed “" + (Events.parse(before).title || e.title) + "”");
            }
            field.text = "";
            notes.text = "";
            root.unfocus();
        } else if (Events.add(selected, field.text, repeat, calendarName, text)) {
            tell("added “" + Events.parse(field.text).title + "”");
            field.text = "";
            notes.text = "";
            repeat = "";
            undoable++;
            field.forceActiveFocus();       // (ready for the next one)
        } else {
            field.forceActiveFocus();       // (notes but no title yet)
        }
    }

    function cycleCalendar() {
        const names = Events.calendars.map(c => c.name);
        const next = names[(names.indexOf(shownCalendar) + 1) % names.length];
        if (changing)
            editCalendar = next === changing.calendar ? "-" : next;
        else
            calendar = next;
    }

    function cycleRepeat() {
        const next = Events.repeats[(Events.repeats.indexOf(shownRepeat) + 1) % Events.repeats.length];
        if (changing)
            editRepeat = next === (changing.freq ?? "") ? "-" : next;
        else
            repeat = next;
    }

    // (no fresh looks at your events while one is being dragged: its row stays put)
    Binding {
        target: Events
        property: "hold"
        value: root.dragged !== null
    }

    Connections {
        target: Events
        function onFailed(what) {
            if (what === "undo") {
                root.undoable = 0;
                root.tell("nothing to undo");
            } else {
                root.undoable = Math.max(0, root.undoable - 1);
                root.tell(({ add: "couldn't add it", move: "couldn't move it", edit: "couldn't change it" })[what] ?? "couldn't delete it");
            }
        }
    }

    // over ‹ or › with an event: another month every so often
    Timer {
        interval: 650
        repeat: true
        running: root.dragged !== null && root.flipBy !== 0
        onTriggered: root.step(root.flipBy)
    }
    Timer {
        id: landTimer
        interval: 650
        onTriggered: root.landed = null
    }
    Timer {
        id: noticeTimer
        interval: 8000
        onTriggered: {
            root.notice = "";
            root.offerAll = null;
        }
    }

    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control)
            dragCopy = false;
    }

    Keys.onPressed: event => {
        let done = true;
        if (dragged !== null) {
            if (event.key === Qt.Key_Escape) {
                dragCancelled = true;
                dropDay = null;
                flipBy = 0;
            } else if (event.key === Qt.Key_Control) {
                dragCopy = true;
            }
        } else if (asking !== null && event.key === Qt.Key_Escape)
            asking = null;
        else if (asking !== null && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter))
            moveEvent(asking.event, asking.from, asking.to, "one");
        else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier))
            undo();
        else if (event.key === Qt.Key_Left)
            moveBy(-1);
        else if (event.key === Qt.Key_Right)
            moveBy(1);
        else if (event.key === Qt.Key_Up)
            moveBy(-7);
        else if (event.key === Qt.Key_Down)
            moveBy(7);
        else if (event.key === Qt.Key_PageUp)
            select(new Date(selected.getFullYear(), selected.getMonth() - 1, Math.min(selected.getDate(), 28)));
        else if (event.key === Qt.Key_PageDown)
            select(new Date(selected.getFullYear(), selected.getMonth() + 1, Math.min(selected.getDate(), 28)));
        else if (event.key === Qt.Key_Home || event.key === Qt.Key_T)
            reset();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            field.forceActiveFocus();
        else if (event.key === Qt.Key_Escape)
            mode !== "days" ? mode = "days" : root.dismiss();
        else
            done = false;
        event.accepted = done;
    }

    // a small round button with an icon or a word
    component Button: MouseArea {
        id: button
        property string icon
        property string text
        property bool on: false
        implicitWidth: text ? word.implicitWidth + 18 : 30
        implicitHeight: 30
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: Theme.pillRadius
            color: button.on ? Theme.alpha(Theme.accent, 0.22) : Theme.hover
            opacity: button.on || button.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Icon {
            anchors.centerIn: parent
            visible: button.icon !== ""
            name: button.icon
            color: button.containsMouse || button.on ? Theme.accent : Theme.subtle
            implicitWidth: 15
            implicitHeight: 15
        }
        Label {
            id: word
            anchors.centerIn: parent
            visible: button.text !== ""
            text: button.text
            font.pixelSize: 13
            color: button.containsMouse || button.on ? Theme.accent : Theme.subtle
        }
    }

    ColumnLayout {
        id: column
        spacing: 12

        // ---------------------------------------------------------------- header
        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            // the title: click for the months of the year, then for years
            MouseArea {
                id: title
                implicitWidth: titleText.implicitWidth + 18
                implicitHeight: 34
                hoverEnabled: true
                cursorShape: root.mode === "years" ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                    if (root.mode === "days")
                        root.mode = "months";
                    else if (root.mode === "months")
                        root.mode = "years";
                    root.slideIn(-1);
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.pillRadius
                    color: Theme.hover
                    opacity: title.containsMouse && root.mode !== "years" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Label {
                    id: titleText
                    anchors.centerIn: parent
                    text: root.mode === "days" ? Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                        : root.mode === "months" ? String(root.viewYear)
                        : `${root.yearsFrom} to ${root.yearsFrom + 11}`
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "today"
                visible: root.mode !== "days" || !root.sameDay(root.selected, root.today())
                         || root.viewMonth !== root.date.getMonth() || root.viewYear !== root.date.getFullYear()
                onClicked: root.reset()
            }
            Button {
                id: prevButton
                icon: "chevron-left"
                on: root.dragged !== null && root.flipBy === -1
                onClicked: root.step(-1)
            }
            Button {
                id: nextButton
                icon: "chevron-right"
                on: root.dragged !== null && root.flipBy === 1
                onClicked: root.step(1)
            }
        }

        // ---------------------------------------------------------------- the views
        // (all the same size, so the island doesn't jump; each slides in from the side
        // it comes from)
        Item {
            id: views
            Layout.preferredWidth: root.weekWidth + 7 * root.cellWidth
            Layout.preferredHeight: 7 * root.cellHeight
            clip: true

            WheelHandler {
                property real sum: 0
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    sum += event.angleDelta.y;
                    if (Math.abs(sum) >= 120) {
                        root.step(sum > 0 ? -1 : 1);
                        sum = 0;
                    }
                }
            }

            Item {
                id: page
                width: parent.width
                height: parent.height

                ParallelAnimation {
                    id: flip
                    NumberAnimation { id: slide; target: page; property: "x"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: page; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                }

                // ---------- days
                Grid {
                    visible: root.mode === "days"
                    columns: 8

                    // weekday names (and nothing over the week numbers)
                    Item { width: root.weekWidth; height: root.cellHeight }
                    Repeater {
                        model: 7
                        Label {
                            required property int index
                            width: root.cellWidth
                            height: root.cellHeight
                            horizontalAlignment: Text.AlignHCenter
                            text: Qt.locale().dayName((root.firstDay + index) % 7, Locale.ShortFormat).slice(0, 2)
                            font.pixelSize: 13
                            color: Theme.muted
                        }
                    }

                    Repeater {
                        model: 6 * 8

                        Loader {
                            id: slot
                            required property int index
                            readonly property int row: Math.floor(index / 8)
                            readonly property int column: index % 8
                            readonly property var day: new Date(root.gridStart.getFullYear(), root.gridStart.getMonth(),
                                                                root.gridStart.getDate() + row * 7 + Math.max(0, column - 1))
                            width: column === 0 ? root.weekWidth : root.cellWidth
                            height: root.cellHeight
                            sourceComponent: column === 0 ? weekNumber : dayCell
                        }
                    }
                }

                // ---------- months of the year
                Grid {
                    visible: root.mode === "months"
                    anchors.centerIn: parent
                    columns: 3
                    rowSpacing: 6
                    columnSpacing: 6

                    Repeater {
                        model: 12
                        PickCell {
                            required property int index
                            text: Qt.locale().standaloneMonthName(index, Locale.ShortFormat)
                            now: root.viewYear === root.date.getFullYear() && index === root.date.getMonth()
                            picked: index === root.selected.getMonth() && root.viewYear === root.selected.getFullYear()
                            onClicked: {
                                root.viewMonth = index;
                                root.mode = "days";
                                root.slideIn(1);
                            }
                        }
                    }
                }

                // ---------- years
                Grid {
                    visible: root.mode === "years"
                    anchors.centerIn: parent
                    columns: 3
                    rowSpacing: 6
                    columnSpacing: 6

                    Repeater {
                        model: 12
                        PickCell {
                            required property int index
                            readonly property int year: root.yearsFrom + index
                            text: String(year)
                            now: year === root.date.getFullYear()
                            picked: year === root.selected.getFullYear()
                            onClicked: {
                                root.viewYear = year;
                                root.mode = "months";
                                root.slideIn(1);
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.edge
        }

        // ---------------------------------------------------------------- the day
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 30
            spacing: 8

            Label {
                text: Qt.formatDate(root.selected, "dddd d MMMM")
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: root.relative(root.selected)
                color: Theme.muted
                font.pixelSize: 13
                elide: Text.ElideRight
            }
            Label {
                visible: Events.syncing
                text: "syncing"
                color: Theme.muted
                font.pixelSize: 12
            }
        }

        // its events
        Flickable {
            id: dayEvents
            readonly property var list: Events.on(root.selected)
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(agenda.implicitHeight, 6 * root.rowHeight + 40)
            contentHeight: agenda.implicitHeight
            interactive: false              // (a drag moves an event; the wheel scrolls)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => dayEvents.contentY = Math.max(0, Math.min(dayEvents.contentHeight - dayEvents.height,
                                                                                dayEvents.contentY - event.angleDelta.y / 2))
            }

            Column {
                id: agenda
                width: parent.width

                Label {
                    visible: dayEvents.list.length === 0
                    width: agenda.width
                    topPadding: 4
                    bottomPadding: 4
                    text: Events.missing ? "Events come from khal, which isn't installed:\nsudo pacman -S khal" : "nothing planned"
                    color: Theme.muted
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: dayEvents.list

                    Item {
                        id: item
                        required property var modelData
                        readonly property bool hasNotes: (modelData.description ?? "") !== "" || (modelData.location ?? "") !== ""
                                                         || (modelData.url ?? "") !== ""
                        readonly property bool long: titleWidth.advanceWidth > title.width + 1      // (cut off on one line)
                        readonly property bool hasMore: hasNotes || long
                        // (one just added, or a copy, being written: not yet)
                        readonly property bool editable: modelData.uid !== "" && !modelData.pending
                        // (open, one you can change shows its notes, or "add notes")
                        readonly property bool showsNotes: hasNotes || editable
                        readonly property string key: (modelData.uid || modelData.title) + "@" + Events.key(root.selected)
                        readonly property bool open: (hasMore || editable) && root.expanded === key
                        readonly property bool moving: root.dragged !== null && root.dragged.uid === modelData.uid
                        readonly property bool changing: root.changing !== null && root.changing.uid === modelData.uid

                        width: agenda.width
                        opacity: moving ? 0.35 : modelData.pending ? 0.6 : 1
                        height: head.height + (open && showsNotes ? details.implicitHeight + 8 : 0)
                        clip: true
                        // (opening out: it grows to show the rest, and closes back)
                        Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                        TextMetrics {
                            id: titleWidth
                            font: title.font
                            text: item.modelData.title
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.pillRadius
                            color: item.changing ? Theme.alpha(Theme.accent, 0.16) : Theme.hover
                            opacity: head.containsMouse || item.open || item.changing ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                        }

                        // (the first line stays where it is; an open title wraps below it)
                        MouseArea {
                            id: head
                            width: parent.width
                            height: item.open ? Math.max(root.rowHeight, title.implicitHeight + 2 * title.anchors.topMargin) : root.rowHeight
                            hoverEnabled: true
                            cursorShape: item.hasMore || item.editable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (item.hasMore || item.editable) root.expanded = item.open ? "" : item.key
                            onDoubleClicked: if (item.editable) root.startEditing(item.modelData)

                            // pick it up and drop it on another day
                            DragHandler {
                                target: null
                                enabled: item.editable
                                dragThreshold: 6
                                cursorShape: Qt.ClosedHandCursor
                                onActiveChanged: {
                                    if (active)
                                        root.startDrag(item.modelData, centroid.scenePosition);
                                    else
                                        Qt.callLater(root.endDrag);
                                }
                                onCentroidChanged: if (active) root.dragTo(centroid.scenePosition, centroid.modifiers)
                            }

                            // in its calendar's colour
                            Rectangle {
                                x: 8
                                y: (root.rowHeight - height) / 2
                                width: 3
                                height: 16
                                radius: 1.5
                                color: Events.colorOf(item.modelData.calendar) || (item.modelData.allDay ? Theme.accent2 : Theme.accent)
                            }
                            Label {
                                id: when
                                x: 20
                                width: 96
                                height: root.rowHeight
                                text: item.modelData.allDay ? "all day"
                                    : item.modelData.start ? item.modelData.start + (item.modelData.end ? "–" + item.modelData.end : "")
                                    : "continues"
                                color: Theme.subtle
                                font.pixelSize: 13
                            }
                            Label {
                                id: title
                                anchors.left: when.right
                                anchors.right: marks.left
                                anchors.rightMargin: 6
                                anchors.top: parent.top
                                anchors.topMargin: Math.round((root.rowHeight - titleWidth.height) / 2)
                                text: item.modelData.title
                                textFormat: Text.PlainText
                                font.pixelSize: 14
                                // open: the whole title, over as many lines as it takes
                                wrapMode: item.open ? Text.Wrap : Text.NoWrap
                                elide: item.open ? Text.ElideNone : Text.ElideRight
                                verticalAlignment: Text.AlignTop
                            }

                            Row {
                                id: marks
                                anchors.right: parent.right
                                anchors.rightMargin: 2
                                height: root.rowHeight
                                spacing: 4

                                // has notes: click for them (one without: there on hover, for adding some)
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: item.hasMore || item.editable
                                    opacity: item.hasMore || item.open || head.containsMouse ? 1 : 0
                                    name: "chevron-down"
                                    color: item.open || head.containsMouse ? Theme.accent : Theme.muted
                                    implicitWidth: 12
                                    implicitHeight: 12
                                    rotation: item.open ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 180 } }
                                }
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: item.modelData.repeat === true
                                    name: "repeat"
                                    color: Theme.muted
                                    implicitWidth: 12
                                    implicitHeight: 12
                                }
                                // change it (or double-click it)
                                Button {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: item.editable && head.containsMouse
                                    icon: "edit"
                                    onClicked: root.startEditing(item.modelData)
                                }
                                // delete it (from your Mac and phone too; a repeating one,
                                // that day's: "delete all" then takes the rest; undo puts
                                // it back)
                                Button {
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: "close"
                                    opacity: head.containsMouse ? 1 : 0
                                    visible: item.editable
                                    onClicked: Qt.callLater(root.deleteEvent, item.modelData, "one")
                                }
                            }
                        }

                        // its place, notes and link (fading in as it opens); click the notes
                        // (or "add notes") to change them, in the box below
                        Column {
                            id: details
                            x: 20
                            y: head.height
                            width: parent.width - 32
                            spacing: 5
                            visible: item.showsNotes && (item.open || item.height > head.height)
                            opacity: item.open ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Label {
                                width: parent.width
                                visible: text !== ""
                                text: item.modelData.location ?? ""
                                textFormat: Text.PlainText
                                color: Theme.accent
                                font.pixelSize: 13
                                wrapMode: Text.Wrap
                            }
                            Label {
                                id: description
                                readonly property bool empty: (item.modelData.description ?? "") === ""
                                width: parent.width
                                visible: !empty || item.editable
                                text: empty ? "add notes" : root.linkify(item.modelData.description)
                                textFormat: empty ? Text.PlainText : Text.StyledText
                                color: empty ? Theme.muted : Theme.subtle
                                linkColor: Theme.accent
                                font.pixelSize: 13
                                font.weight: Font.Normal
                                wrapMode: Text.Wrap
                                onLinkActivated: link => root.openLink(link)

                                HoverHandler {
                                    cursorShape: description.hoveredLink ? Qt.PointingHandCursor
                                               : item.editable ? Qt.IBeamCursor : Qt.ArrowCursor
                                }
                                TapHandler {
                                    enabled: item.editable
                                    onTapped: point => {
                                        if (description.linkAt(point.position.x, point.position.y) === "")
                                            root.startEditing(item.modelData, true);
                                    }
                                }
                            }
                            Label {
                                id: link
                                width: parent.width
                                visible: (item.modelData.url ?? "") !== ""
                                text: root.linkify(item.modelData.url ?? "")
                                textFormat: Text.StyledText
                                linkColor: Theme.accent
                                font.pixelSize: 13
                                elide: Text.ElideMiddle
                                onLinkActivated: url => root.openLink(url)

                                HoverHandler {
                                    cursorShape: link.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                            }
                        }
                    }
                }
            }
        }

        // what just happened, for a few seconds: undo it (or, after deleting one day's of a
        // repeating event, the rest of it too)
        Rectangle {
            Layout.fillWidth: true
            visible: root.notice !== ""
            implicitHeight: 34
            radius: Theme.pillRadius
            color: Theme.alpha(Theme.accent, 0.10)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 2
                spacing: 2

                Icon {
                    name: "check"
                    color: Theme.accent
                    weight: 2.6
                    implicitWidth: 12
                    implicitHeight: 12
                }
                Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.leftMargin: 6
                    text: root.notice
                    textFormat: Text.PlainText
                    color: Theme.accent
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                Button {
                    visible: root.offerAll !== null
                    text: "delete all"
                    onClicked: root.deleteEvent(root.offerAll, "all")
                }
                Button {
                    visible: root.undoable > 0
                    text: "undo"
                    onClicked: root.undo()
                }
            }
        }

        // a repeating event dropped on another day: just that day's, or all of them?
        Rectangle {
            Layout.fillWidth: true
            visible: root.asking !== null
            implicitHeight: 40
            radius: Theme.pillRadius
            color: Theme.alpha(Theme.accent, 0.12)
            border.width: 1
            border.color: Theme.alpha(Theme.accent, 0.5)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 4
                spacing: 2

                Icon {
                    name: "repeat"
                    color: Theme.accent
                    implicitWidth: 13
                    implicitHeight: 13
                }
                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    text: "It repeats. Move"
                    color: Theme.subtle
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                Button {
                    text: "just this one"
                    on: true
                    onClicked: root.moveEvent(root.asking.event, root.asking.from, root.asking.to, "one")
                }
                Button {
                    text: "all"
                    onClicked: root.moveEvent(root.asking.event, root.asking.from, root.asking.to, "all")
                }
                Button {
                    icon: "close"
                    onClicked: root.asking = null
                }
            }
        }

        // changing one: which
        Label {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            visible: root.changing !== null
            text: root.changing ? "Changing “" + root.changing.title + "”" + (root.changing.repeat ? ", every one of it" : "") : ""
            color: Theme.accent
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        // adding one (or changing one): its title and time on top; its notes (the event's
        // description) under them, while you're writing or once something's in them.
        // Enter saves the event; Shift+Enter in the notes is a new line.
        Rectangle {
            id: box
            readonly property bool active: field.activeFocus || notes.activeFocus
            readonly property bool showNotes: root.changing !== null || active || notes.text !== ""
            Layout.fillWidth: true
            visible: !Events.missing && root.asking === null
            implicitHeight: 40 + (showNotes ? notesPart.height : 0)
            radius: Theme.pillRadius
            color: Theme.alpha(Theme.fg, active ? 0.10 : 0.06)
            border.width: active || root.changing ? 1 : 0
            border.color: Theme.alpha(Theme.accent, root.changing ? 0.8 : 0.5)

            // ---------- the title
            Item {
                width: parent.width
                height: 40

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: field.forceActiveFocus()
                }

                Icon {
                    id: plus
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.changing ? "edit" : "plus"
                    color: field.activeFocus ? Theme.accent : Theme.muted
                    implicitWidth: 13
                    implicitHeight: 13
                }

                TextInput {
                    id: field
                    anchors.left: plus.right
                    anchors.leftMargin: 8
                    anchors.right: calendarButton.visible ? calendarButton.left : repeatButton.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    clip: true

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text === ""
                        text: root.changing ? "a title, or 14:30 and a title" : field.activeFocus ? "14:30 dentist, or just a title" : "add an event"
                        width: field.width
                        elide: Text.ElideRight
                        color: Theme.muted
                        font.pixelSize: 14
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.submit();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                            notes.forceActiveFocus();
                            notes.cursorPosition = notes.text.length;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            if (root.changing) {
                                root.stopEditing();
                                root.unfocus();
                            } else if (text !== "" || notes.text !== "") {
                                text = "";
                                notes.text = "";
                            } else {
                                root.unfocus();
                            }
                            event.accepted = true;
                        }
                    }
                    onActiveFocusChanged: Qt.callLater(root.leftFields)
                }

                // which calendar (when there's more than one), in its colour
                Button {
                    id: calendarButton
                    anchors.right: repeatButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Events.calendars.length > 1
                    implicitWidth: Math.min(130, calendarLabel.implicitWidth + 30)
                    onClicked: root.cycleCalendar()

                    Rectangle {
                        id: calendarDot
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 3.5
                        color: Events.colorOf(root.shownCalendar) || Theme.accent
                    }
                    Label {
                        id: calendarLabel
                        anchors.left: calendarDot.right
                        anchors.leftMargin: 5
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.shownCalendar
                        font.pixelSize: 13
                        color: calendarButton.containsMouse ? Theme.accent : Theme.subtle
                        elide: Text.ElideRight
                    }
                }

                // once / weekly / monthly / yearly
                Button {
                    id: repeatButton
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.shownRepeat || "once"
                    on: root.shownRepeat !== ""
                    onClicked: root.cycleRepeat()
                }
            }

            // ---------- its notes
            Item {
                id: notesPart
                y: 40
                width: parent.width
                height: Math.min(notes.implicitHeight, 96) + 18
                visible: box.showNotes

                Rectangle {
                    x: 10
                    width: parent.width - 20
                    height: 1
                    color: Theme.alpha(Theme.fg, 0.08)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: notes.forceActiveFocus()
                }

                Icon {
                    x: 10
                    y: 11
                    name: "notes"
                    color: notes.activeFocus ? Theme.accent : Theme.muted
                    implicitWidth: 13
                    implicitHeight: 13
                }

                Flickable {
                    id: notesView
                    anchors.fill: parent
                    anchors.leftMargin: 31
                    anchors.rightMargin: 10
                    anchors.topMargin: 9
                    anchors.bottomMargin: 9
                    contentWidth: width
                    contentHeight: notes.implicitHeight
                    interactive: false              // (the wheel scrolls; dragging selects)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // (keeps the cursor in sight as you type past the bottom)
                    function show(r) {
                        if (contentY > r.y)
                            contentY = r.y;
                        else if (contentY + height < r.y + r.height)
                            contentY = r.y + r.height - height;
                    }

                    WheelHandler {
                        target: null
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => notesView.contentY = Math.max(0, Math.min(notesView.contentHeight - notesView.height,
                                                                                        notesView.contentY - event.angleDelta.y / 2))
                    }

                    TextEdit {
                        id: notes
                        width: notesView.width
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        color: Theme.fg
                        selectionColor: Theme.alpha(Theme.accent, 0.35)
                        selectedTextColor: Theme.fg
                        selectByMouse: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        onCursorRectangleChanged: notesView.show(cursorRectangle)

                        Label {
                            width: parent.width
                            visible: notes.text === ""
                            text: notes.activeFocus ? "notes (Shift+Enter: a new line)" : "add notes"
                            color: Theme.muted
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        Keys.onPressed: event => {
                            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
                            if (enter && (event.modifiers & Qt.ShiftModifier)) {
                                if (selectedText !== "")
                                    remove(selectionStart, selectionEnd);
                                insert(cursorPosition, "\n");
                                event.accepted = true;
                            } else if (enter) {
                                root.submit();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape && root.changing) {
                                root.stopEditing();             // (leaves it as it was)
                                root.unfocus();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                field.forceActiveFocus();       // (back to the title)
                                event.accepted = true;
                            }
                        }
                        onActiveFocusChanged: Qt.callLater(root.leftFields)
                    }
                }
            }
        }
    }

    // the event being dragged, following the pointer, and where it would land
    Rectangle {
        z: 10
        visible: root.dragged !== null && !root.dragCancelled
        x: Math.round(root.dragPoint.x + 14)
        y: Math.round(root.dragPoint.y - height / 2)
        width: ghost.implicitWidth + 22
        height: 32
        radius: Theme.pillRadius
        color: Theme.frameColor
        border.width: 1.5
        border.color: root.dropDay ? Theme.accent : Theme.edge

        Row {
            id: ghost
            anchors.centerIn: parent
            spacing: 7

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 15
                radius: 1.5
                color: Events.colorOf(root.dragged?.calendar ?? "") || Theme.accent
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.dragCopy
                text: "copy"
                color: Theme.accent2
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 160)
                text: root.dragged?.title ?? ""
                textFormat: Text.PlainText
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.dropDay !== null
                text: root.dropDay ? "→ " + Qt.formatDate(root.dropDay, "ddd d") : ""
                color: Theme.accent
                font.pixelSize: 13
            }
        }
    }

    // ---------------------------------------------------------------- cells

    Component {
        id: weekNumber
        Label {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            // (the row's Monday)
            text: root.isoWeek(new Date(parent.day.getFullYear(), parent.day.getMonth(), parent.day.getDate() + (8 - root.firstDay) % 7))
            color: Theme.alpha(Theme.muted, 0.7)
            font.pixelSize: 11
        }
    }

    Component {
        id: dayCell
        MouseArea {
            id: cell
            readonly property var day: parent.day
            readonly property bool inMonth: day.getMonth() === root.viewMonth
            readonly property bool isToday: root.sameDay(day, root.date)
            readonly property bool picked: root.sameDay(day, root.selected)
            readonly property bool weekend: day.getDay() === 0 || day.getDay() === 6
            readonly property bool busy: Events.on(day).length > 0
            readonly property bool target: root.dropDay !== null && root.sameDay(day, root.dropDay)
            readonly property bool landing: root.landed !== null && root.sameDay(day, root.landed)

            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.select(day);
                root.unfocus();
            }
            onDoubleClicked: {
                root.select(day);
                field.forceActiveFocus();
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Theme.pillRadius
                color: cell.isToday ? "transparent" : Theme.hover
                opacity: cell.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }
            // today
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Theme.pillRadius
                visible: cell.isToday
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.accent }
                    GradientStop { position: 1; color: Theme.accent2 }
                }
            }
            // an event over it (where it would land), or just landed on it
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Theme.pillRadius
                color: Theme.alpha(Theme.accent, cell.target ? 0.30 : 0.45)
                border.width: 1.5
                border.color: Theme.accent
                opacity: cell.target || cell.landing ? 1 : 0
                scale: cell.target ? 1.08 : 1
                Behavior on opacity { NumberAnimation { duration: cell.landing ? 120 : 450 } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            }
            // the picked day
            Rectangle {
                anchors.fill: parent
                anchors.margins: cell.isToday ? -1 : 1
                radius: Theme.pillRadius + (cell.isToday ? 2 : 0)
                visible: cell.picked
                color: "transparent"
                border.width: 1.5
                border.color: cell.isToday ? Theme.alpha(Theme.accent, 0.6) : Theme.accent
            }

            Label {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: cell.busy ? -3 : 0
                text: cell.day.getDate()
                font.pixelSize: 15
                font.weight: cell.isToday || cell.picked ? Font.Bold : Font.Medium
                color: cell.isToday ? Theme.ink : cell.weekend ? Theme.subtle : Theme.fg
                opacity: cell.inMonth ? 1 : 0.35
            }
            // has events
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                visible: cell.busy
                width: 4
                height: 4
                radius: 2
                color: cell.isToday ? Theme.ink : Theme.accent2
                opacity: cell.inMonth ? 1 : 0.5
            }
        }
    }

    // a month or a year to jump to
    component PickCell: MouseArea {
        id: pick
        property string text
        property bool now: false
        property bool picked: false
        width: 98
        height: 52
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: Theme.pillRadius
            color: pick.now ? Theme.alpha(Theme.accent, 0.22) : Theme.hover
            opacity: pick.now || pick.containsMouse ? 1 : 0
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.pillRadius
            visible: pick.picked
            color: "transparent"
            border.width: 1.5
            border.color: Theme.accent
        }
        Label {
            anchors.centerIn: parent
            text: pick.text
            font.pixelSize: 15
            color: pick.now ? Theme.accent : Theme.fg
        }
    }
}
