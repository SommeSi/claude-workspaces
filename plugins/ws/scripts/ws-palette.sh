#!/bin/bash
# ws-palette.sh — Resolve a workspace's color/emoji/name from its slot.
#
# Single source of truth for the palette. Called by ws-preflight.sh (worktree)
# and by the attach / start-sandbox skills. Keeping the logic in one place
# means the curated table and the procedural generator never drift apart.
#
# Slots 1..16 use a hand-picked palette (dark tints, light text on top).
# Slots 17+ generate a distinct color via golden-angle hue rotation
# (effectively infinite — a new hue every slot), with the badge set to the
# nearest colored circle. The background always stays a dark tint so the
# white terminal/VS Code foreground remains readable.
#
# Usage:
#   ws-palette.sh <slot>
#
# Output (key=value, one per line):
#   COLOR=#1a3a2a
#   EMOJI=🟢
#   NAME=Green

set -euo pipefail

SLOT="${1:-}"
if [ -z "$SLOT" ]; then
  echo "Usage: ws-palette.sh <slot>" >&2
  exit 1
fi

python3 - "$SLOT" <<'PYEOF'
import sys, colorsys

# Curated palette — index = slot - 1. Backgrounds are dark tints because both
# the terminal and the VS Code titleBar render WHITE text on top of them.
# "White" is therefore a neutral dark grey badged ⚪, not a literal white fill.
CURATED = [
    ("#1a3a2a", "🟢", "Green"),
    ("#3a2a15", "🟠", "Orange"),
    ("#2a1a3a", "🟣", "Purple"),
    ("#3a1515", "🔴", "Red"),
    ("#15353a", "🩵", "Cyan"),
    ("#3a1a2e", "🩷", "Pink"),
    ("#3a3415", "🟡", "Yellow"),
    ("#1a2835", "🔵", "Blue"),
    ("#2e2e2e", "⚪", "White"),
    ("#3a2a1f", "🟤", "Brown"),
    ("#2a3a15", "🟩", "Lime"),
    ("#1a1f3a", "🟦", "Indigo"),
    ("#341a3a", "🟪", "Magenta"),
    ("#153a30", "💚", "Teal"),
    ("#3a2410", "🧡", "Amber"),
    ("#20242a", "⚫", "Slate"),
]

GOLDEN_ANGLE = 137.508  # degrees — maximally spreads successive hues

def emoji_for_hue(h):
    # h in [0, 360). Pick the nearest colored-circle badge.
    for upper, e in (
        (15, "🔴"), (45, "🟠"), (70, "🟡"), (160, "🟢"),
        (200, "🩵"), (255, "🔵"), (290, "🟣"), (345, "🩷"),
    ):
        if h < upper:
            return e
    return "🔴"  # wraps back to red past 345°

def resolve(slot):
    if 1 <= slot <= len(CURATED):
        return CURATED[slot - 1]
    # Procedural: a distinct hue per slot at a fixed dark tint.
    hue = ((slot - 1) * GOLDEN_ANGLE) % 360
    r, g, b = colorsys.hls_to_rgb(hue / 360.0, 0.16, 0.45)  # H, L, S
    color = "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))
    return (color, emoji_for_hue(hue), "Hue %d°" % round(hue))

try:
    slot = int(sys.argv[1])
except ValueError:
    sys.stderr.write("slot must be an integer\n")
    sys.exit(1)

color, emoji, name = resolve(slot)
sys.stdout.write("COLOR=%s\nEMOJI=%s\nNAME=%s\n" % (color, emoji, name))
PYEOF
