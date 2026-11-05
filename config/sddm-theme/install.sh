#!/bin/bash
# SDDM login screen with the Islands Aurora theme (password login; the lock screen is
# the shell's, quickshell/lock). Run once with sudo:
#   sudo ~/.config/sddm-theme/install.sh
# Takes effect at next boot.
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

user=${SUDO_USER:?run via sudo from your user account}
home=$(getent passwd "$user" | cut -d: -f6)
src="$home/.config/sddm-theme/islands-aurora"
dst=/usr/share/sddm/themes/islands-aurora

# theme files; dynamic/ (blurred wallpaper, palette, icons) stays user-owned so
# sync.sh refreshes it on every wallpaper change without sudo
mkdir -p "$dst/dynamic"
install -m 644 "$src/Main.qml" "$src/metadata.desktop" "$src/theme.conf" "$dst/"
ln -sfn dynamic/theme.conf.user "$dst/theme.conf.user"
chown "$user:" "$dst/dynamic"; chmod 755 "$dst/dynamic"

mkdir -p /etc/sddm.conf.d
printf '[Theme]\nCurrent=islands-aurora\n' > /etc/sddm.conf.d/10-islands-aurora.conf

# password login again: drop the old autologin setups (SDDM's and tty1's)
rm -f /etc/sddm.conf.d/20-autologin.conf
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
rmdir --ignore-fail-on-non-empty /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
systemctl daemon-reload
systemctl enable sddm.service

sudo -u "$user" "$home/.config/sddm-theme/sync.sh"
echo "Done. Reboot to log in through SDDM."
