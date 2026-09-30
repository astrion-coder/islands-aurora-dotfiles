#!/bin/bash
# Start opensnitch-ui with themed tray icons (see ../opensnitch/sitecustomize.py)
# OpenSnitch is optional: nothing to do if it isn't installed
command -v opensnitch-ui >/dev/null || exit 0
export PYTHONPATH="$HOME/.config/waybar/opensnitch${PYTHONPATH:+:$PYTHONPATH}"
exec opensnitch-ui "$@"
