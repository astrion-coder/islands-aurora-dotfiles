#!/bin/bash
# Restart the shell (bar, notifications, launcher, lock screen). Bound to Super+D in
# hyprland.lua.
running() { pgrep -x "qs|quickshell" >/dev/null; }
wait_gone() { for _ in $(seq "$1"); do running || return 0; sleep 0.1; done; return 1; }

qs kill >/dev/null 2>&1
# (an instance can hang while exiting; then ask it the usual way, then insist)
wait_gone 20 || { pkill -x "qs|quickshell"; wait_gone 20; } || { pkill -9 -x "qs|quickshell"; wait_gone 10; }
exec setsid -f qs -n -d >/dev/null 2>&1
