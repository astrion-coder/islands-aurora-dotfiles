#!/bin/bash
# OpenSnitch's tray icons (a shield per state) redrawn in the current palette and
# installed as theme icons, which scripts/opensnitch/sitecustomize.py swaps in.
# Usage: tray-icons.sh <accent> <accent2> <muted> <error>
# Called by matugen's post_hook (see ~/.config/matugen/config.toml).

T=${1:-#8fd3c8} A=${2:-#f2b880} M=${3:-#6b7080} R=${4:-#eb6f6f}
theme=${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor
mkdir -p "$theme/scalable/apps"

svg() {
    local out="$theme/scalable/apps/$1.svg"
    rm -f "$out"   # (older versions linked these to files in ~/.config/waybar)
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\">$2</svg>" > "$out"
    # PNGs too, for opensnitch-ui's Qt5, which can't read SVG icons without qt5-svg
    for size in 16 22 24 32 48; do
        mkdir -p "$theme/${size}x${size}/apps"
        rsvg-convert -w $size -h $size "$out" -o "$theme/${size}x${size}/apps/$1.png"
    done
}

SHIELD='<path d="M12 21.5s7.5-3.6 7.5-9.4V5.6L12 2.8 4.5 5.6v6.5c0 5.8 7.5 9.4 7.5 9.4z"/>'
svg opensnitch-shield       "<g stroke=\"$T\" stroke-width=\"2\">$SHIELD<path d=\"m8.8 12 2.2 2.2 4.2-4.3\"/></g>"
svg opensnitch-shield-off   "<g stroke=\"$M\" stroke-width=\"2\">$SHIELD</g><path d=\"M4 3l16 18\" stroke=\"$R\" stroke-width=\"2\"/>"
svg opensnitch-shield-pause "<g stroke=\"$A\" stroke-width=\"2\">$SHIELD<path d=\"M10 9.5v5M14 9.5v5\"/></g>"
svg opensnitch-shield-alert "<g stroke=\"$R\" stroke-width=\"2\">$SHIELD<path d=\"M12 8v4.5\"/><circle cx=\"12\" cy=\"15.8\" r=\"0.4\"/></g>"

touch "$theme"   # nudge GTK/Qt to rescan
