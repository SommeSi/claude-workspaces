#!/bin/bash
# ws-palette.sh — Resolve a workspace's color/emoji/name from its slot.
#
# Single source of truth for the palette. Called by ws-preflight.sh (worktree)
# and by the attach / start-sandbox skills. Keeping the logic in one place
# means the curated table and the procedural generator never drift apart.
#
# Design goal: DARK & EASY ON THE EYES first, distinct second. Backgrounds are
# painted full-screen on the terminal + VS Code titleBar (with white text on
# top), so a bright/saturated fill is fatiguing. Every color here is a deep,
# muted tint (relative luminance ≤ ~0.04, white-text contrast ≥ 12:1).
#
# At this comfortable dark level, 16 *mutually* distinct colors is physically
# impossible — so the trade is: slots 1-8 (the ones actually run concurrently,
# since slots are handed out lowest-first) are both comfortable AND distinct
# (≥ 8 ΔE); slots 9-16 add variety but a few warm tones sit closer (they rarely
# co-occur). Blue vs Indigo — the pair that motivated this — is ~15 ΔE apart.
#
# Slots 17+ generate a distinct hue per slot via golden-angle rotation, kept in
# the same dark/muted register (effectively infinite), badge = nearest circle.
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

# Curated palette — index = slot - 1. Deep muted tints; "White" is a neutral
# light-grey badged ⚪ (not a literal white fill, which would hide the text).
CURATED = [
    ("#1a3a2a", "🟢", "Green"),
    ("#3a2a15", "🟠", "Orange"),
    ("#2a1a3a", "🟣", "Purple"),
    ("#3a1515", "🔴", "Red"),
    ("#15353a", "🩵", "Cyan"),
    ("#3a1a2e", "🩷", "Pink"),
    ("#3a3415", "🟡", "Yellow"),
    ("#1a2835", "🔵", "Blue"),
    ("#313133", "⚪", "White"),
    ("#38220f", "🟤", "Brown"),
    ("#2c3a12", "🟩", "Lime"),
    ("#1f2024", "⚫", "Slate"),
    ("#103a33", "💚", "Teal"),
    ("#3a153a", "🟪", "Magenta"),
    ("#1c1f40", "🟦", "Indigo"),
    ("#3a2208", "🧡", "Amber"),
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
    # Procedural: a distinct hue per slot, kept in the same deep/muted register
    # as the curated palette (low lightness, moderate saturation).
    hue = ((slot - 1) * GOLDEN_ANGLE) % 360
    r, g, b = colorsys.hls_to_rgb(hue / 360.0, 0.15, 0.40)  # H, L, S
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
