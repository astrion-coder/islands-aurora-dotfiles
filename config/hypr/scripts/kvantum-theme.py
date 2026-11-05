#!/usr/bin/env python3
"""Kvantum theme "Matugen": KvArcDark recoloured to the wallpaper palette, with
translucent window backgrounds (text stays opaque; Hyprland blurs behind).

The style for every Qt app (qt5ct/qt6ct style=kvantum): backgrounds frosted by
Hyprland, text and document pages solid. There is no whole-window opacity rule.
Writes ~/.config/Kvantum/Matugen/ and selects it in ~/.config/Kvantum/kvantum.kvconfig.
Run by hypr/scripts/wallpaper-theme.sh after matugen; applies when Okular starts.
"""

import colorsys
import configparser
import re
from pathlib import Path

BASE = Path("/usr/share/Kvantum/KvArcDark")
OUT = Path.home() / ".config/Kvantum/Matugen"
COLORS_CSS = Path.home() / ".config/quickshell/colors.css"

# How see-through window backgrounds / menus are (% opacity removed); ~kitty's 0.65
WINDOW_TRANSPARENCY = 35
MENU_TRANSPARENCY = 20

palette = dict(re.findall(r"@define-color (\w+)\s+(#[0-9a-fA-F]{6});", COLORS_CSS.read_text()))


def rgb(h):
    return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def hexc(r, g, b):
    return "#%02x%02x%02x" % tuple(round(max(0, min(1, v)) * 255) for v in (r, g, b))


base_h, _, base_s = colorsys.rgb_to_hls(*rgb(palette["base"]))
acc_h, acc_l, acc_s = colorsys.rgb_to_hls(*rgb(palette["accent"]))
acc2_h, acc2_l, acc2_s = colorsys.rgb_to_hls(*rgb(palette["accent2"]))
ARC_BLUE_L = colorsys.rgb_to_hls(*rgb("#5294e2"))[1]


def recolour(match):
    """Map one of KvArcDark's colours onto the palette, keeping its lightness."""
    h, l, s = colorsys.rgb_to_hls(*rgb(match.group(0)))
    if s > 0.45 and 0.5 < h < 0.72:          # Arc's blues -> accent (Arc's #5294e2 == accent)
        return hexc(*colorsys.hls_to_rgb(acc_h, acc_l + (l - ARC_BLUE_L), acc_s))
    if s > 0.45 and 0.72 <= h < 0.9:         # purples -> accent2
        return hexc(*colorsys.hls_to_rgb(acc2_h, l, acc2_s))
    if s < 0.35 and 0.5 < h < 0.75:          # blue-greys -> palette-tinted greys
        return hexc(*colorsys.hls_to_rgb(base_h, l, min(s, base_s + 0.08)))
    return match.group(0)                    # blacks, whites, reds, ... unchanged


def shade(hex_colour, lightness_delta):
    h, l, s = colorsys.rgb_to_hls(*rgb(hex_colour))
    return hexc(*colorsys.hls_to_rgb(h, min(1, l + lightness_delta), s))


OUT.mkdir(parents=True, exist_ok=True)
svg = re.sub(r"#[0-9a-fA-F]{6}\b", recolour, (BASE / "KvArcDark.svg").read_text())
# Selected list/grid items (Kvantum's itemview "pressed" = selected in the focused window,
# "toggled" = selected otherwise): a 35% accent tint, like the 20% hover tint, instead
# of a solid light block, so the item's light text stays readable (Dolphin draws its
# file names in the normal text colour whatever the selection colour).
i = svg.find('id="itemview-pressed-top"')
g = svg.rfind('<g style="', 0, i)
svg = svg[:g] + svg[g:i].replace('fill-rule:evenodd"', 'fill-rule:evenodd;fill-opacity:0.35"', 1) + svg[i:]
svg = re.sub(r'(<[a-z]+ style="fill:#[0-9a-fA-F]{6})(;[^"]*" id="itemview-toggled)', r"\1;fill-opacity:0.35\2", svg)
(OUT / "Matugen.svg").write_text(svg)

cfg = configparser.ConfigParser(interpolation=None, strict=False)
cfg.optionxform = str  # Kvantum keys are case-sensitive
cfg.read(BASE / "KvArcDark.kvconfig")

general = cfg["%General"]
general["comment"] = "KvArcDark recoloured from the wallpaper palette (generated; do not edit)"
general["composite"] = "true"
general["translucent_windows"] = "true"
general["reduce_window_opacity"] = str(WINDOW_TRANSPARENCY)
general["reduce_menu_opacity"] = str(MENU_TRANSPARENCY)
general["blurring"] = "false"          # KDE-only; Hyprland does the blur
general["popup_blurring"] = "false"

# Per-widget colours in the config (text.focus.color=#5796e8, ...) get the same
# palette mapping as the SVG; any alpha suffix (#rrggbbAA) is kept
for section in cfg.sections():
    for key, value in cfg[section].items():
        cfg[section][key] = re.sub(r"#[0-9a-fA-F]{6}(?=[0-9a-fA-F]{2}\b|\b)", recolour, value)

p = palette
cfg["GeneralColors"].update({
    "window.color": p["base"],
    # Lists/tables/text fields ("base") are clear, so they show the 65% window
    # background (and the blur) like the rest; alternating rows get a faint light tint
    "base.color": p["base"] + "00",
    "alt.base.color": p["fg"] + "0a",
    "button.color": shade(p["base"], 0.08),
    "light.color": shade(p["base"], 0.20),
    "highlight.color": p["accent"],
    "inactive.highlight.color": p["accent"],
    "text.color": p["fg"],
    "window.text.color": p["fg"],
    "button.text.color": p["fg"],
    "disabled.text.color": p["muted"],
    "tooltip.text.color": p["fg"],
    "highlight.text.color": p["ink"],
    # selections in unfocused lists (e.g. Dolphin's view) otherwise fall back to light text
    "inactive.highlight.text.color": p["ink"],
    "link.color": p["accent"],
    "link.visited.color": p["accent2"],
    "progress.indicator.text.color": p["ink"],
})

# Menu bar, toolbar, tab pages, group boxes and table headers: no painted background, so the
# translucent window background (and Hyprland's blur) shows through there too.
# (Text fields keep theirs so they still read as inputs.)
for section in ("MenuBar", "Toolbar", "TabFrame", "GroupBox", "HeaderSection"):
    cfg[section]["interior"] = "false"
    cfg[section]["frame"] = "false"

# Pressed / toggled buttons sit on the solid light accent: dark text there (also when
# the window isn't focused), white elsewhere. Tool buttons inherit PanelButtonCommand;
# toolbar buttons use Toolbar. Selected list items (ItemView) are on a translucent tint
# (see the SVG above), so they keep light text.
for section in ("PanelButtonCommand", "PanelButtonTool", "Toolbar"):
    for key in ("text.press.color", "text.toggle.color",
                "text.press.inactive.color", "text.toggle.inactive.color"):
        cfg[section][key] = p["ink"]
for key in ("text.press.color", "text.toggle.color",
            "text.press.inactive.color", "text.toggle.inactive.color"):
    cfg["ItemView"][key] = p["fg"]

if not cfg.has_section("Hacks"):
    cfg.add_section("Hacks")
cfg["Hacks"]["respect_darkness"] = "true"
cfg["Hacks"]["transparent_dolphin_view"] = "true"   # Dolphin's file view shows the blur too

with open(OUT / "Matugen.kvconfig", "w") as f:
    cfg.write(f, space_around_delimiters=False)

(OUT.parent / "kvantum.kvconfig").write_text("[General]\ntheme=Matugen\n")
