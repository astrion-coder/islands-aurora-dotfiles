#!/bin/bash
# rofi mode: file search in $HOME (fd: skips hidden and git-ignored files). Enter opens.
if [ -z "$1" ]; then
    printf '\0no-custom\x1ftrue\n'
    fd . "$HOME" --type f --max-results 100000 2>/dev/null | sed "s|^$HOME/|~/|"
else
    setsid -f xdg-open "${1/#\~/$HOME}" >/dev/null 2>&1
fi
