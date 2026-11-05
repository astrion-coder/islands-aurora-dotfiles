pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU load (every 2 s) and memory use (every 5 s), read from /proc.
Singleton {
    id: root

    property real cpu: 0          // % busy since the previous sample
    property real memUsed: 0      // GiB in use (total minus available)
    property real memTotal: 0     // GiB
    property var lastCpu: null

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + b, 0);
            if (root.lastCpu && total > root.lastCpu.total)
                root.cpu = 100 * (1 - (idle - root.lastCpu.idle) / (total - root.lastCpu.total));
            root.lastCpu = { total, idle };
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const kb = key => Number((text().match(new RegExp("^" + key + ":\\s+(\\d+)", "m")) ?? [0, 0])[1]);
            const total = kb("MemTotal");
            root.memTotal = total / 1048576;
            root.memUsed = (total - kb("MemAvailable")) / 1048576;
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: stat.reload()
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: meminfo.reload()
    }
}
