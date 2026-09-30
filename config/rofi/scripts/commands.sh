#!/bin/bash
# The main menu's commands (shown alongside apps, like Raycast). Hidden keywords
# (meta) make partial words match, e.g. "paste" finds Clipboard History.
# Commands with a menu open it via launch.sh; system commands run directly.
# Typing maths or a time conversion ("15:39 utc") and pressing Enter shows the answer
# (and copies it).
launch="$HOME/.config/rofi/scripts/launch.sh"
row() { printf '%s\0icon\x1f%s\x1fmeta\x1f%s\n' "$1" "$2" "$3"; }

# Typed text that matched nothing (Enter): time-zone conversion or maths
# (evaluate.py prints nothing for anything else, and then nothing happens)
if [ "$ROFI_RETV" = 2 ]; then
    if [ -n "$("$HOME/.config/rofi/scripts/evaluate.py" "$1")" ]; then
        setsid -f "$launch" --from-root result "$1" >/dev/null 2>&1
    fi
    exit 0
fi

case $1 in
    "")
        row "Clipboard History" edit-paste            "clipboard clip paste copy history"
        row "Search Emoji"      face-smile            "emoji emoticon smiley symbol"
        row "Search Files"      system-search         "files find folder documents open"
        row "Calculator"        accessories-calculator "calculator calc math convert units"
        row "Switch Windows"    preferences-system-windows "windows switch window focus"
        row "Lock Screen"       system-lock-screen    "lock"
        row "Log Out"           system-log-out        "logout log out exit session"
        row "Suspend"           system-suspend        "suspend sleep"
        row "Reboot"            system-reboot         "reboot restart"
        row "Shut Down"         system-shutdown       "shutdown shut down power off poweroff"
        ;;
    # Open a sub-menu once this menu has closed (from-root: Esc there comes back here)
    "Clipboard History") setsid -f "$launch" --from-root clipboard >/dev/null 2>&1 ;;
    "Search Emoji")      setsid -f "$launch" --from-root emoji     >/dev/null 2>&1 ;;
    "Search Files")      setsid -f "$launch" --from-root files     >/dev/null 2>&1 ;;
    "Calculator")        setsid -f "$launch" --from-root calc      >/dev/null 2>&1 ;;
    "Switch Windows")    setsid -f "$launch" --from-root windows   >/dev/null 2>&1 ;;
    "Lock Screen")       setsid -f hyprlock >/dev/null 2>&1 ;;
    "Log Out")           hyprctl dispatch 'hl.dsp.exit()' >/dev/null ;;
    "Suspend")           systemctl suspend ;;
    "Reboot")            systemctl reboot ;;
    "Shut Down")         systemctl poweroff ;;
esac
