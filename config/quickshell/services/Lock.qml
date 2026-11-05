pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// The lock screen's state and password check (replaces hyprlock). Lock with
//   qs ipc call lock lock
// The password goes through PAM's "login" service, like hyprlock's.
Singleton {
    id: root

    property bool locked: false
    property bool unlocking: false      // fading out after the right password
    property bool busy: false           // checking a password
    property string message: ""         // "wrong password", or what PAM says
    property bool failed: false
    property int attempt: 0             // bumps on each failure (the field shakes)
    property string pending: ""

    function lock() {
        if (locked)
            return;
        message = "";
        failed = false;
        unlocking = false;
        locked = true;
    }

    function tryUnlock(password) {
        if (busy || password === "")
            return;
        pending = password;
        busy = true;
        message = "";
        failed = false;
        pam.start();
    }

    PamContext {
        id: pam
        config: "login"

        onPamMessage: {
            if (responseRequired) {
                respond(root.pending);
                root.pending = "";
            } else if (message !== "") {
                root.message = message.toLowerCase();    // e.g. account locked after failures
            }
        }
        onCompleted: result => {
            root.busy = false;
            root.pending = "";
            if (result === PamResult.Success) {
                root.unlocking = true;
                unlock.restart();
            } else {
                root.failed = true;
                if (root.message === "")
                    root.message = "wrong password";
                root.attempt++;
            }
        }
        onError: error => {
            root.busy = false;
            root.pending = "";
            root.failed = true;
            root.message = "couldn't check the password";
            root.attempt++;
        }
    }

    // The right password: the lock's clock, avatar and line fade, then the lock goes and
    // the desktop is there.
    SequentialAnimation {
        id: unlock
        PauseAnimation { duration: 220 }
        ScriptAction {
            script: {
                root.locked = false;
                root.unlocking = false;
                root.message = "";
            }
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock();
        }
    }
}
