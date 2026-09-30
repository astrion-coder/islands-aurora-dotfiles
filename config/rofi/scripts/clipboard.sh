#!/bin/bash
# rofi mode: clipboard history (cliphist). Enter copies the entry back to the clipboard.
# History is recorded by `wl-paste --watch cliphist store` (started in hyprland.lua).
if [ -z "$ROFI_RETV" ] || [ "$ROFI_RETV" = 0 ]; then
    printf '\0no-custom\x1ftrue\n'
    printf '\0message\x1fEnter: copy  ·  Shift+Delete: remove entry\n'
    cliphist list | while IFS= read -r line; do
        printf '%s\0display\x1f%s\n' "$line" "${line#*$'\t'}"
    done
elif [ "$ROFI_RETV" = 1 ]; then
    cliphist decode <<<"$1" | wl-copy
elif [ "$ROFI_RETV" = 10 ]; then          # kb-custom-1: remove from history, stay open
    cliphist delete <<<"$1"
    exec "$0"
fi
