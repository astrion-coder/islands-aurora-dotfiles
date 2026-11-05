#!/bin/sh
# Paste the clipboard into the window you're in: what the launcher does after copying
# something for you (clipboard history, the calculator, answers), once it has closed.
# Hyprland itself sends the paste shortcut to that window, as if from your keyboard
# (a simulated keyboard, wtype, is ignored by some apps, like VS Code and other Electron
# ones). Terminals paste with Ctrl+Shift+V, everything else with Ctrl+V. (A real paste,
# not typing: images paste too, and several lines arrive as one paste instead of being
# run line by line in a terminal.)
sleep 0.2
info=$(hyprctl activewindow)
addr=$(printf '%s\n' "$info" | sed -n 's/^Window \([0-9a-f]*\) .*/\1/p' | head -n 1)
class=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*class: //p' | head -n 1)
[ -n "$addr" ] || exit 0         # (no window: nowhere to paste)
case "$class" in
    *kitty*|*foot*|*[Aa]lacritty*|*wezterm*|*konsole*|*ghostty*|*[Tt]erminal*|*xterm*|*tilix*|*ptyxis*|st|st-*)
        mods="CTRL SHIFT" ;;
    *)
        mods="CTRL" ;;
esac
# (Lua Hyprland: dispatches are Lua)
exec hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"$mods\", key = \"V\", window = \"address:0x$addr\" })" >/dev/null
