#!/bin/bash
# ws-palette.sh — Resolve a workspace's color/emoji/name from its slot.
#
# Single source of truth for the palette. Called by ws-preflight.sh (worktree)
# and by the attach / start-sandbox skills. Keeping the logic in one place
# means the curated table and the procedural generator never drift apart.
#
# Design: COMFORT FIRST for a full-screen fill. The hard-won lesson — a saturated
# color is fatiguing across a whole terminal background even when it's dark, so
# the register is BOTH dark AND muted (relative luminance ≤ 0.030, low chroma;
# every color is calmer than the wine that got rejected). Placed by farthest-
# point sampling in CIELAB within that comfortable band → min ~10 ΔE between any
# two, which reads as "clearly different but calm". Names are descriptive
# (Olive/Steel/Plum…) because muted darks aren't bright primaries.
#
# Slots 17+ generate a distinct hue per slot via golden-angle rotation, kept in
# the same dark/muted register (effectively infinite), badge = nearest circle.
#
# Usage:
#   ws-palette.sh <slot>
#
# Output (key=value, one per line):
#   COLOR=#3f282c
#   EMOJI=🔴
#   NAME=Maroon

set -euo pipefail

SLOT="${1:-}"
if [ -z "$SLOT" ]; then
  echo "Usage: ws-palette.sh <slot>" >&2
  exit 1
fi

python3 - "$SLOT" <<'PYEOF'
import sys, colorsys

# Curated palette — index = slot - 1. Deep, muted, calm tints. "White" is a
# neutral grey badged ⚪ (a literal white fill would hide the white text).
CURATED = [
    ("#3f282c", "🔴", "Maroon"),
    ("#3a1b15", "🟤", "Rust"),
    ("#382c21", "🟡", "Olive"),
    ("#2c1a00", "🟠", "Khaki"),
    ("#262507", "🟡", "Gold"),
    ("#20331c", "🟢", "Forest"),
    ("#162014", "🟢", "Pine"),
    ("#002c22", "💚", "Spruce"),
    ("#072122", "🩵", "Teal"),
    ("#00343c", "🔵", "Steel"),
    ("#062a41", "🟦", "Iris"),
    ("#1e1a33", "🟣", "Plum"),
    ("#312b3d", "🟪", "Grape"),
    ("#391c2f", "🩷", "Rose"),
    ("#303034", "⚪", "White"),
    ("#191a1e", "⚫", "Slate"),
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
    # Procedural: a distinct hue per slot in the same dark/muted comfort register
    # (low lightness, low saturation) so generated colors match the curated feel.
    hue = ((slot - 1) * GOLDEN_ANGLE) % 360
    r, g, b = colorsys.hls_to_rgb(hue / 360.0, 0.13, 0.30)  # H, L, S
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
