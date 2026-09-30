#!/bin/bash
# rofi mode: system actions
row() { printf '%s\0icon\x1f%s\n' "$1" "$2"; }
case $1 in
    "")          printf '\0no-custom\x1ftrue\n'
                 row "lock"      system-lock-screen
                 row "log out"   system-log-out
                 row "suspend"   system-suspend
                 row "reboot"    system-reboot
                 row "shut down" system-shutdown ;;
    "lock")      setsid -f hyprlock >/dev/null 2>&1 ;;
    "log out")   hyprctl dispatch 'hl.dsp.exit()' >/dev/null ;;
    "suspend")   systemctl suspend ;;
    "reboot")    systemctl reboot ;;
    "shut down") systemctl poweroff ;;
esac
