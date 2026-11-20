#!/usr/bin/env python3
"""Merge the generated KDE colour scheme into ~/.config/kdeglobals.

Only the colour/icon sections are replaced, so anything else KDE apps store in
kdeglobals is kept. Qt/KDE apps pick up the new colours on their next start."""
import configparser, os

scheme = os.path.expanduser("~/.local/share/color-schemes/Matugen.colors")
target = os.path.expanduser("~/.config/kdeglobals")

def load(path):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str  # KDE keys are case-sensitive
    if os.path.exists(path):
        cp.read(path)
    return cp

src, dst = load(scheme), load(target)
for sec in src.sections():
    if sec.startswith("Colors:") or sec in ("WM",):
        dst.remove_section(sec)
    if not dst.has_section(sec):
        dst.add_section(sec)
    for k, v in src.items(sec):
        dst.set(sec, k, v)

with open(target, "w") as f:
    dst.write(f, space_around_delimiters=False)
