import QtQuick
import qs.services
import "fuzzy.js" as Fuzzy

// Lock, log out, suspend, reboot, shut down.
Mode {
    prompt: "system"
    rows: Fuzzy.filter([
        { title: "Lock Screen", icon: "system-lock-screen", action: "lock", meta: "lock" },
        { title: "Log Out", icon: "system-log-out", action: "logout", meta: "logout exit session" },
        { title: "Suspend", icon: "system-suspend", action: "suspend", meta: "sleep" },
        { title: "Reboot", icon: "system-reboot", action: "reboot", meta: "restart" },
        { title: "Shut Down", icon: "system-shutdown", action: "poweroff", meta: "shutdown power off poweroff" }
    ], query)

    function activate(row, how) {
        if (row)
            Launcher.system(row.action);
    }
}
