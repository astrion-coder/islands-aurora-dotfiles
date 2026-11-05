"""Loaded automatically by Python when opensnitch-ui is started via
~/.config/quickshell/scripts/opensnitch-ui.sh (PYTHONPATH points here).

opensnitch-ui's tray icons are plain pixmaps, which Qt exports to the tray as
empty. So swap the tray's icons for named theme icons (opensnitch-shield*, drawn
in the wallpaper palette by scripts/tray-icons.sh), which the bar resolves on
every change.
Only the tray is touched; opensnitch's own windows keep their icons.
"""

try:
    from PyQt5 import QtGui
    from opensnitch.service import UIService

    _orig_setup_tray = UIService._setup_tray

    def _setup_tray(self):
        _orig_setup_tray(self)
        themed = {
            self.white_icon.cacheKey(): "opensnitch-shield",        # connected, firewall on
            self.off_icon.cacheKey():   "opensnitch-shield-off",    # daemon not connected
            self.pause_icon.cacheKey(): "opensnitch-shield-pause",  # firewall disabled
            self.alert_icon.cacheKey(): "opensnitch-shield-alert",  # pending alert
            self.red_icon.cacheKey():   "opensnitch-shield-alert",
        }
        tray = self._tray
        orig_set_icon = tray.setIcon

        def set_icon(icon):
            name = themed.get(icon.cacheKey())
            orig_set_icon(QtGui.QIcon.fromTheme(name) if name else icon)

        tray.setIcon = set_icon
        set_icon(tray.icon())

    UIService._setup_tray = _setup_tray
except Exception as e:  # never stop opensnitch-ui from starting
    print("opensnitch tray theme patch not applied:", e)
