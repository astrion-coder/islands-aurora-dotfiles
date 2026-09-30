#!/bin/bash
# Regenerate the bar's SVG icons in the current palette.
# Usage: gen-icons.sh <accent> <accent2> <muted> <subtle> <error>
# Called by matugen's post_hook (see ~/.config/matugen/config.toml).

T=${1:-#8fd3c8} A=${2:-#f2b880} M=${3:-#6b7080} S=${4:-#aab0bf} R=${5:-#eb6f6f}
cd "$(dirname "$0")/../icons" || exit 1

svg() { echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$2\" height=\"$3\" viewBox=\"$4\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\">$5</svg>" > "$1.svg"; }
bat() { svg "$1" 22 11 "0 0 22 11" "<rect x=\"0.75\" y=\"0.75\" width=\"20.5\" height=\"9.5\" rx=\"2.25\" stroke=\"$S\" stroke-width=\"1.5\"/><rect x=\"2.5\" y=\"2.5\" width=\"$2\" height=\"6\" rx=\"1\" fill=\"$3\"/>"; }

WIFI='<path d="M2 8.5a15 15 0 0 1 20 0"/><path d="M5 12a10 10 0 0 1 14 0"/><path d="M8.5 15.5a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/>'
SPEAKER='<path d="M11 5 6 9H3v6h3l5 4z"/>'

svg wifi         14 14 "0 0 24 24" "<g stroke=\"$T\" stroke-width=\"2.2\">$WIFI</g>"
svg wifi-off     14 14 "0 0 24 24" "<g stroke=\"$M\" stroke-width=\"2.2\">$WIFI</g><path d=\"M3 3l18 18\" stroke=\"$R\" stroke-width=\"2.2\"/>"
svg ethernet     14 14 "0 0 24 24" "<g stroke=\"$T\" stroke-width=\"2.2\"><rect x=\"3\" y=\"4\" width=\"18\" height=\"12\" rx=\"2\"/><path d=\"M8 20h8\"/><path d=\"M12 16v4\"/><path d=\"M8 8v4M12 8v4M16 8v4\"/></g>"
svg volume       14 14 "0 0 24 24" "<g stroke=\"$T\" stroke-width=\"2.2\">$SPEAKER<path d=\"M15.5 8.5a5 5 0 0 1 0 7\"/></g>"
svg volume-muted 14 14 "0 0 24 24" "<g stroke=\"$M\" stroke-width=\"2.2\">$SPEAKER</g><path d=\"M16 9l5 6M21 9l-5 6\" stroke=\"$R\" stroke-width=\"2.2\"/>"
# opensnitch-ui tray states (installed as theme icons: scripts/opensnitch-ui.sh)
SHIELD='<path d="M12 21.5s7.5-3.6 7.5-9.4V5.6L12 2.8 4.5 5.6v6.5c0 5.8 7.5 9.4 7.5 9.4z"/>'
svg opensnitch-shield       24 24 "0 0 24 24" "<g stroke=\"$T\" stroke-width=\"2\">$SHIELD<path d=\"m8.8 12 2.2 2.2 4.2-4.3\"/></g>"
svg opensnitch-shield-off   24 24 "0 0 24 24" "<g stroke=\"$M\" stroke-width=\"2\">$SHIELD</g><path d=\"M4 3l16 18\" stroke=\"$R\" stroke-width=\"2\"/>"
svg opensnitch-shield-pause 24 24 "0 0 24 24" "<g stroke=\"$A\" stroke-width=\"2\">$SHIELD<path d=\"M10 9.5v5M14 9.5v5\"/></g>"
svg opensnitch-shield-alert 24 24 "0 0 24 24" "<g stroke=\"$R\" stroke-width=\"2\">$SHIELD<path d=\"M12 8v4.5\"/><circle cx=\"12\" cy=\"15.8\" r=\"0.4\"/></g>"
BT='<path d="m7 7 10 10-5 5V2l5 5L7 17"/>'
svg bluetooth       14 14 "0 0 24 24" "<g stroke=\"$T\" stroke-width=\"2.2\">$BT</g>"
svg bluetooth-muted 14 14 "0 0 24 24" "<g stroke=\"$M\" stroke-width=\"2.2\">$BT</g><path d=\"M19 15l4 4M23 15l-4 4\" stroke=\"$R\" stroke-width=\"2.2\"/>"
svg power        13 13 "0 0 24 24" "<g stroke=\"$A\" stroke-width=\"2.4\"><path d=\"M12 3v8\"/><path d=\"M6.3 7.3a8 8 0 1 0 11.4 0\"/></g>"

bat battery-100 17  "$A"
bat battery-75  13  "$A"
bat battery-50  8.5 "$A"
bat battery-25  4.5 "$A"
bat battery-10  2   "$R"
bat battery-charging 17 "$T"

# Install the opensnitch shields as theme icons: SVG for GTK (waybar), PNG for
# opensnitch-ui's Qt5, which can't read SVG icons without qt5-svg.
theme=${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor
for f in opensnitch-shield*.svg; do
    name=${f%.svg}
    mkdir -p "$theme/scalable/apps"
    ln -sf "$PWD/$f" "$theme/scalable/apps/$f"
    for size in 16 22 24 32 48; do
        mkdir -p "$theme/${size}x${size}/apps"
        rsvg-convert -w $size -h $size "$f" -o "$theme/${size}x${size}/apps/$name.png"
    done
done
touch "$theme"   # nudge GTK/Qt to rescan
