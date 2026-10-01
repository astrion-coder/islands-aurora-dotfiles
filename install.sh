#!/bin/bash
# Islands Aurora installer: a fresh, terminal-only Arch install -> the full desktop.
#
#   git clone <this repo> && cd <repo> && ./install.sh
#
# Options:
#   --with-opensnitch   also install the OpenSnitch application firewall (themed tray icon)
#   --no-packages       skip pacman (configs + theme only)
#   --no-sddm           don't install/enable the SDDM login screen
#
# Everything comes from the official Arch repositories (no AUR). Existing configs that
# would be overwritten are copied to ~/.config-backup-<date>/ first.

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WITH_OPENSNITCH=0; DO_PACKAGES=1; DO_SDDM=1
for arg in "$@"; do
    case $arg in
        --with-opensnitch) WITH_OPENSNITCH=1 ;;
        --no-packages)     DO_PACKAGES=0 ;;
        --no-sddm)         DO_SDDM=0 ;;
        -h|--help)         sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg (see --help)" >&2; exit 1 ;;
    esac
done

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f /etc/arch-release ]   || die "this installer is for Arch Linux"
[ "$(id -u)" -ne 0 ]       || die "run as your normal user (it asks for sudo when needed)"
command -v sudo >/dev/null || die "sudo is required (pacman -S sudo, and add yourself to wheel)"

# ---------------------------------------------------------------- 1. packages
if [ $DO_PACKAGES = 1 ]; then
    say "Installing packages (official repositories)"
    mapfile -t pkgs < <(sed -e 's/#.*//' -e '/^\s*$/d' "$REPO/packages.txt")
    [ $WITH_OPENSNITCH = 1 ] && pkgs+=(opensnitch)
    sudo pacman -Syu --needed "${pkgs[@]}"
fi

# ---------------------------------------------------------------- 2. configs
say "Copying configs to ~/.config (backup of anything replaced goes to ~/.config-backup-*)"
backup="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
for dir in "$REPO"/config/*/; do
    name=$(basename "$dir")
    if [ -e "$HOME/.config/$name" ]; then
        mkdir -p "$backup"
        cp -a "$HOME/.config/$name" "$backup/"
    fi
done
[ -d "$backup" ] && echo "  backup: $backup"
mkdir -p "$HOME/.config"
cp -a "$REPO"/config/. "$HOME/.config/"
if [ $WITH_OPENSNITCH = 1 ] || command -v opensnitch-ui >/dev/null; then
    mkdir -p "$HOME/.local/share/applications"
    cp -a "$REPO"/local/share/applications/. "$HOME/.local/share/applications/"
fi

# paths that must be absolute
mkdir -p "$HOME/.local/share/applications"
grep -rl "__HOME__" "$HOME/.config/qt5ct" "$HOME/.config/qt6ct" "$HOME/.local/share/applications" 2>/dev/null \
    | xargs -r sed -i "s|__HOME__|$HOME|g"

find "$HOME/.config/hypr/scripts" "$HOME/.config/waybar/scripts" "$HOME/.config/rofi/scripts" \
     "$HOME/.config/matugen/scripts" "$HOME/.config/sddm-theme" -type f \( -name '*.sh' -o -name '*.py' \) \
     -exec chmod +x {} +

# login-screen assets live in ~/.cache/login (sync.sh); the theme source links to them
mkdir -p "$HOME/.cache/login"
ln -sfn "$HOME/.cache/login" "$HOME/.config/sddm-theme/islands-aurora/dynamic"
ln -sfn dynamic/theme.conf.user "$HOME/.config/sddm-theme/islands-aurora/theme.conf.user"

# ---------------------------------------------------------------- 3. wallpaper + theme
say "Picking a wallpaper and generating the colour theme from it"
walls="$HOME/Pictures/Wallpapers"
mkdir -p "$walls"
wallpaper=$(find "$walls" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort | head -n1)
if [ -z "$wallpaper" ]; then
    # no wallpaper yet: generate a soft aurora gradient (replace it any time with `awww img`)
    wallpaper="$walls/islands-aurora-default.png"
    ffmpeg -loglevel error -y -f lavfi \
        -i "gradients=s=3840x2160:c0=0x0b0d12:c1=0x1f5c63:c2=0x2c2f6b:c3=0x7a3f2c:n=4:x0=500:y0=600:x1=3300:y1=1800:type=radial:d=1" \
        -frames:v 1 -vf "gblur=sigma=120" "$wallpaper"
    echo "  generated $wallpaper"
else
    echo "  using $wallpaper"
fi
printf '%s' "$wallpaper" > "$HOME/.cache/wallpaper-theme.last"

# matugen writes every themed file (bar, borders, kitty, GTK, Qt, KDE, rofi, zathura, ...).
# Its reload hooks need a running desktop, so they may complain here; that's fine.
matugen image "$wallpaper" --mode dark --source-color-index 0 --continue-on-error >/dev/null 2>&1 || true
# bar icons, Qt style, login/lock screen assets (normally run on each wallpaper change)
eval "$(sed -n 's/^@define-color \([a-z0-9]*\) *\(#[0-9a-fA-F]\{6\}\);/\1=\2/p' "$HOME/.config/waybar/colors.css")"
"$HOME/.config/waybar/scripts/gen-icons.sh" "$accent" "$accent2" "$muted" "$subtle" "$error"
"$HOME/.config/hypr/scripts/kvantum-theme.py"
"$HOME/.config/sddm-theme/sync.sh" "$wallpaper"
[ -f "$HOME/.config/waybar/colors.css" ] || die "theme generation failed (is matugen installed?)"

# ---------------------------------------------------------------- 4. app settings
say "Applying app settings"
# KDE apps apply their own colour scheme on top of Qt's: point them at the generated one
for app in dolphinrc okularrc; do
    kwriteconfig6 --file "$app" --group UiSettings --key ColorScheme Matugen
done
# Okular: pale highlighters (they read well on the dark, lightness-inverted pages)
kwriteconfig6 --file okularpartrc --group Reviews --key QuickAnnotationTools \
    "$(cat "$REPO/extras/okular-annotation-tools.txt")"
# GTK dark preference + theme (also read by Firefox and portals)
dbus-run-session -- sh -c '
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    gsettings set org.gnome.desktop.interface icon-theme breeze-dark' 2>/dev/null \
    || warn "couldn't set GNOME/GTK preferences (gsettings); GTK apps still read gtk-3.0/settings.ini"
# PDFs open in zathura (Okular stays available for annotating)
xdg-mime default org.pwmt.zathura-pdf-mupdf.desktop application/pdf

# ---------------------------------------------------------------- 5. services
say "Enabling services"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable qalc-rates.timer 2>/dev/null \
    || warn "couldn't enable qalc-rates.timer now; run: systemctl --user enable qalc-rates.timer"
systemctl --user enable hyprpolkitagent.service 2>/dev/null \
    || warn "couldn't enable hyprpolkitagent; run: systemctl --user enable hyprpolkitagent.service"
sudo systemctl enable NetworkManager.service
[ $WITH_OPENSNITCH = 1 ] && sudo systemctl enable opensnitchd.service
if [ $DO_SDDM = 1 ]; then
    say "Installing the login screen (SDDM)"
    sudo "$HOME/.config/sddm-theme/install.sh"
fi

say "Done. Reboot to log in to Hyprland:  sudo reboot"
cat <<'EOF'

  Super+Q      terminal (kitty)        Super+Space  launcher (apps, clipboard, emoji, files, calc)
  Super+E      files (Dolphin)         Super+Esc    lock screen
  Super+C      close window            Super+M      log out

  Change wallpaper (and the whole colour theme):  awww img ~/Pictures/Wallpapers/<image>
EOF
