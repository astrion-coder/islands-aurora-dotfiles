#!/usr/bin/env python3
"""Right-click menu for the sound pill: mute, volume mixer, Bluetooth on/off and the
trusted Bluetooth devices (tick = connected, battery on the right; click to connect or
disconnect), plus Blueman's device manager.

Waybar's own menus are read once at startup, so they can't list devices; this draws a
menu that looks the same (palette from colors.css, frosted by the "blur-sound-menu"
layer rule in hyprland.lua). It covers the screen with a transparent layer so a click
anywhere else, or Esc, closes it.
"""
import fcntl
import os
import subprocess
import sys

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

HERE = os.path.dirname(os.path.realpath(__file__))
POPUP = os.path.join(HERE, "popup.sh")
BAR_BOTTOM = 56   # bar: margin-top 4 + height 48, plus a 4px gap
EDGE = 14         # keep clear of the screen edge, like the bar's margin

CSS = b"""
@define-color edge_mid rgba(255, 255, 255, 0.15);
* { font-family: "Noto Sans", sans-serif; font-size: 14px; font-weight: 500;
    font-feature-settings: "tnum"; }
window { background: transparent; }
.menu { background-color: alpha(@base, 0.45); border: 1px solid @edge_mid;
        border-radius: 12px; padding: 6px; }
.item { color: @fg; padding: 6px 12px; border-radius: 8px; background: none;
        border: none; box-shadow: none; outline: none; min-height: 0; }
.item:hover { background-color: alpha(@accent, 0.18); }
.item label { color: @fg; }
.item .tick { color: @accent; min-width: 18px; }
.item .side { color: @subtle; }
.separator { background-color: @edge_mid; min-height: 1px; margin: 4px 8px; }
"""


def run(*cmd):
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def muted():
    out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
                         capture_output=True, text=True).stdout
    return "MUTED" in out


def bluetooth():
    """(powered, [(name, address, connected, battery or None)]) for trusted devices;
    powered is None when there's no Bluetooth adapter / bluetoothd isn't running."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
        objs, = bus.call_sync("org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
                              "GetManagedObjects", None, None,
                              Gio.DBusCallFlags.NONE, 1000, None).unpack()
    except GLib.Error:
        return None, []
    powered, devices = None, []
    for ifaces in objs.values():
        if "org.bluez.Adapter1" in ifaces:
            powered = powered or ifaces["org.bluez.Adapter1"].get("Powered", False)
        dev = ifaces.get("org.bluez.Device1")
        if dev and dev.get("Trusted"):
            battery = ifaces.get("org.bluez.Battery1", {}).get("Percentage")
            devices.append((dev.get("Alias") or dev["Address"], dev["Address"],
                            dev.get("Connected", False), battery))
    devices.sort(key=lambda d: (not d[2], d[0].lower()))
    return powered, devices


def placement():
    """Where the menu's top-left corner should go, from the pointer (it was just
    right-clicked on the pill), in the focused monitor's coordinates."""
    import json
    cx, cy = (int(v) for v in subprocess.run(["hyprctl", "cursorpos"], capture_output=True,
                                             text=True).stdout.split(","))
    for m in json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True,
                                       text=True).stdout):
        if m["focused"]:
            scale = m["scale"]
            return cx - m["x"], int(m["width"] / scale)
    return cx, 1920


class Menu(Gtk.Window):
    def __init__(self):
        super().__init__()
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "sound-menu")
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        GtkLayerShell.set_exclusive_zone(self, -1)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        self.set_app_paintable(True)
        visual = self.get_screen().get_rgba_visual()
        if visual:
            self.set_visual(visual)

        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, halign=Gtk.Align.START,
                           valign=Gtk.Align.START)
        self.box.get_style_context().add_class("menu")
        self.fill()
        self.add(self.box)

        # position under the pointer, growing away from the nearer screen edge so it
        # always fits (its width isn't known until it's drawn)
        x, screen_w = placement()
        if x > screen_w / 2:
            self.box.set_halign(Gtk.Align.END)
            self.box.set_margin_end(max(EDGE, screen_w - x - 16))
        else:
            self.box.set_margin_start(max(EDGE, x - 16))
        self.box.set_margin_top(BAR_BOTTOM)

        self.connect("button-press-event", self.on_click_outside)
        self.connect("key-press-event", self.on_key)
        self.connect("destroy", Gtk.main_quit)

    def fill(self):
        is_muted = muted()
        self.item("Unmute" if is_muted else "Mute",
                  lambda: run("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"))
        self.item("Volume mixer", lambda: run(POPUP, "org.pulseaudio.pavucontrol", "pavucontrol"))

        powered, devices = bluetooth()
        if powered is None:          # no adapter: nothing Bluetooth to offer
            return
        self.separator()
        if powered:
            for name, address, connected, battery in devices:
                self.item(name, self.toggle_device(name, address, connected),
                          tick=connected,
                          side=f"{battery}%" if connected and battery is not None else "")
            if devices:
                self.separator()
        self.item("Bluetooth devices", lambda: run(POPUP, "blueman-manager", "blueman-manager"))
        self.item("Turn Bluetooth off" if powered else "Turn Bluetooth on",
                  lambda: run("bluetoothctl", "power", "off" if powered else "on"))

    def toggle_device(self, name, address, connected):
        verb = "disconnect" if connected else "connect"
        # connecting takes a few seconds: run it in the background and only speak up
        # if it fails (the sound pill switches icon by itself when audio moves over)
        script = f'bluetoothctl {verb} "$1" >/dev/null 2>&1 || ' \
                 f'notify-send -a Bluetooth "Couldn\'t {verb} $2"'
        return lambda: run("sh", "-c", script, "sh", address, name)

    def item(self, label, action, tick=False, side=""):
        button = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
        button.get_style_context().add_class("item")
        row = Gtk.Box(spacing=12)
        mark = Gtk.Label(label="✓" if tick else "", xalign=0)
        mark.get_style_context().add_class("tick")
        row.pack_start(mark, False, False, 0)
        row.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
        if side:
            right = Gtk.Label(label=side, xalign=1)
            right.get_style_context().add_class("side")
            row.pack_end(right, False, False, 0)
        button.add(row)
        button.connect("clicked", lambda _b: (action(), self.destroy()))
        self.box.pack_start(button, False, False, 0)

    def separator(self):
        line = Gtk.Box()
        line.get_style_context().add_class("separator")
        self.box.pack_start(line, False, False, 0)

    def on_click_outside(self, _widget, event):
        alloc = self.box.get_allocation()
        if not (alloc.x <= event.x < alloc.x + alloc.width
                and alloc.y <= event.y < alloc.y + alloc.height):
            self.destroy()

    def on_key(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.destroy()


def main():
    # one menu at a time: a second right-click while it's open just closes it
    lock = open(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "sound-menu.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)

    css = Gtk.CssProvider()
    colors = os.path.expanduser("~/.config/waybar/colors.css")
    css.load_from_data((open(colors, "rb").read() if os.path.exists(colors) else b"") + CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css,
                                             Gtk.STYLE_PROVIDER_PRIORITY_USER)
    Menu().show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
