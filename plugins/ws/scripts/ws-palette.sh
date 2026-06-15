#!/bin/bash
# ws-palette.sh — Resolve a workspace's color/emoji/name from its slot.
#
# Single source of truth for the palette. Called by ws-preflight.sh (worktree)
# and by the attach / start-sandbox skills. Keeping the logic in one place
# means the curated table and the procedural generator never drift apart.
#
# Design: DARK JEWEL TONES — rich/saturated but with LIGHTNESS capped low, so
# every background is comfortable (relative luminance ≤ ~0.047, white-text
# contrast ≥ 10:1) yet the hues stay vivid enough to tell apart. The key
# realization: eye strain comes from LIGHTNESS, not saturation — a deep
# saturated color (wine, navy, forest) is both calm and distinct, whereas a
# *bright* saturated color is not. Colors were placed by farthest-point sampling
# in CIELAB within that dark band → min 16.6 ΔE between any two (the muted
# palette this replaced sat at ~10; the original naive table at ~4).
#
# Slots 17+ generate a distinct hue per slot via golden-angle rotation, kept
# dark & saturated to match (effectively infinite), badge = nearest circle.
#
# Usage:
#   ws-palette.sh <slot>
#
# Output (key=value, one per line):
#   COLOR=#360216
#   EMOJI=🔴
#   NAME=Red

set -euo pipefail

SLOT="${1:-}"
if [ -z "$SLOT" ]; then
  echo "Usage: ws-palette.sh <slot>" >&2
  exit 1
fi

python3 - "$SLOT" <<'PYEOF'
import sys, colorsys

# Curated palette — index = slot - 1. Deep jewel tones; "White" is a neutral
# light-grey badged ⚪ (not a literal white fill, which would hide the text).
# Names/badges are approximate — dark warm tones read as wine/copper/gold
# rather than bright red/orange/yellow, and Unicode has only ~9 colored circles.
CURATED = [
    ("#360216", "🔴", "Red"),
    ("#6d182f", "🩷", "Crimson"),
    ("#520e00", "🟤", "Rust"),
    ("#3c2115", "🟠", "Copper"),
    ("#4a3601", "🟡", "Gold"),
    ("#1c2200", "🟩", "Lime"),
    ("#174004", "🟢", "Green"),
    ("#004332", "💚", "Teal"),
    ("#003f59", "🔵", "Blue"),
    ("#003e74", "🩵", "Azure"),
    ("#151337", "🟦", "Indigo"),
    ("#402e69", "🟣", "Violet"),
    ("#4d1349", "🟪", "Magenta"),
    ("#502e45", "💜", "Plum"),
    ("#3a3b3e", "⚪", "White"),
    ("#17181c", "⚫", "Slate"),
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
    # Procedural: a distinct hue per slot, kept dark & saturated (lightness
    # capped low for comfort, high saturation for a recognizable jewel tone).
    hue = ((slot - 1) * GOLDEN_ANGLE) % 360
    r, g, b = colorsys.hls_to_rgb(hue / 360.0, 0.14, 0.85)  # H, L, S
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
