pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The notification daemon (replaces dunst). A notification shows in the dynamic island
// for a moment, then waits, unread, beside the calendar in the open island until you act
// on it or close it. Transient ones, and ones whose app sets a timeout, go by themselves.
Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values.slice().reverse()   // newest first
    readonly property int count: list.length
    readonly property bool urgent: list.some(n => n.urgency === NotificationUrgency.Critical)

    property var arrivals: ({})     // id -> when it arrived (ms)
    property var deadlines: ({})    // id -> when it goes by itself
    property real now: Date.now()   // for "5m"

    // a new notification (the island shows it)
    signal arrived(var notification)

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true;
            root.now = Date.now();
            root.arrivals = Object.assign({}, root.arrivals, { [n.id]: root.now });
            // expireTimeout: the app's wish in ms (-1: up to us, 0: never)
            const lifetime = n.expireTimeout > 0 ? n.expireTimeout : n.transient ? root.showFor(n) : 0;
            if (lifetime > 0)
                root.deadlines = Object.assign({}, root.deadlines, { [n.id]: root.now + lifetime });
            root.arrived(n);
        }
    }

    // how long the island shows it (0: until you open the island)
    function showFor(n) {
        return n.urgency === NotificationUrgency.Critical ? 0 : n.urgency === NotificationUrgency.Low ? 3000 : 5000;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.count > 0
        onTriggered: {
            root.now = Date.now();
            for (const n of root.list)
                if (root.deadlines[n.id] && root.deadlines[n.id] <= root.now)
                    n.expire();
        }
    }

    function dismissAll() {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
    }

    // "now", "5m", "2h", "3d"
    function ago(n) {
        const s = (now - (arrivals[n.id] ?? now)) / 1000;
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d";
    }

    // its picture, the app's icon, or the icon of its desktop entry
    function icon(n) {
        const path = s => s.startsWith("/") ? "file://" + s : s;
        if (n?.image)
            return path(n.image);
        if (n?.appIcon)
            return n.appIcon.includes("/") ? path(n.appIcon) : Quickshell.iconPath(n.appIcon, true);
        const entry = n?.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null;
        return entry ? Quickshell.iconPath(entry.icon, true) : "";
    }

    // plain one-line text from a body that may have markup
    function plain(text) {
        return (text ?? "").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
    }
}
