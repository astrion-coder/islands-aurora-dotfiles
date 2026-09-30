#!/bin/bash
# Raycast-style rofi: one main menu (apps + commands); commands open sub-menus.
#   launch.sh              main menu
#   launch.sh <menu>       straight into a sub-menu: clipboard | emoji | files | calc |
#                          windows | system  (and "result <expr>", used by the main menu)
# A shortcut pressed again closes rofi. Esc in a sub-menu opened from the main menu
# goes back to the main menu.
dir="$HOME/.config/rofi/scripts"

if [ "$1" = --from-root ]; then
    from_root=1; shift
    # wait for the main menu to close (rofi runs one instance at a time)
    for _ in $(seq 40); do pgrep -x rofi >/dev/null || break; sleep 0.05; done
else
    pkill -x rofi && exit 0
fi

menu=${1:-main}
case $menu in
    # Main menu: commands + apps. Typed maths + Enter -> "result" card (commands.sh)
    main)
        exec rofi -show combi -modi combi \
            -combi-modi "commands:$dir/commands.sh,drun" \
            -display-combi "search" -combi-display-format "{text}" ;;
    # Answer card for maths / conversions / time zones typed in the main menu:
    # query left, answer right (card.rasi, fields from evaluate.py). Answer is copied.
    result)
        mapfile -t f < <("$dir/evaluate.py" "$2")      # title, query, caption, answer, caption, copy
        [ ${#f[@]} -ge 6 ] || exit 0
        printf '%s' "${f[5]}" | wl-copy
        q() { local s=${1//\\/\\\\}; printf '"%s"' "${s//\"/\\\"}"; }   # rasi string
        # one rule per line: rofi reads a quoted string up to the line's last quote
        card="textbox-title { content: $(q "${f[0]}  ·  copied"); }
textbox-lmain { content: $(q "${f[1]}"); }
textbox-lcap { content: $(q "${f[2]}"); }
textbox-rmain { content: $(q "${f[3]}"); }
textbox-rcap { content: $(q "${f[4]}"); }"
        args=(-dmenu -no-custom -theme "$HOME/.config/rofi/card.rasi" -theme-str "$card")
        input=${f[5]} ;;
    clipboard) args=(-show clipboard -modi "clipboard:$dir/clipboard.sh"
                     -kb-custom-1 "Shift+Delete" -kb-delete-entry "") ;;
    emoji)     args=(-show emoji -modi emoji) ;;
    # Enter copies the result (rofi-calc runs -calc-command on "accept custom", so swap
    # it onto Enter; Ctrl+Enter saves to the calculator's history instead)
    calc)      args=(-show calc -modi calc -no-show-match -no-sort
                     -calc-command "echo -n '{result}' | wl-copy"
                     -kb-accept-custom "Return,KP_Enter" -kb-accept-entry "Control+Return") ;;
    files)     args=(-show files -modi "files:$dir/files.sh") ;;
    windows)   args=(-show window -modi window) ;;
    system)    args=(-show system -modi "system:$dir/system.sh") ;;
    *)         echo "unknown menu: $menu" >&2; exit 1 ;;
esac

[ -z "$from_root" ] && exec rofi "${args[@]}" <<<"$input"

# Opened from the main menu: Esc goes back to it. rofi exits 0 either way, so the
# cancel is flagged with its -on-menu-canceled hook.
canceled="${XDG_RUNTIME_DIR:-/tmp}/rofi-menu-canceled"
rm -f "$canceled"
rofi "${args[@]}" -on-menu-canceled "touch '$canceled'" <<<"$input" >/dev/null
[ -e "$canceled" ] && { rm -f "$canceled"; exec "$0"; }
exit 0
