#!/bin/bash
# ws-palette.sh — Resolve a workspace's color/emoji/name from its slot.
#
# Single source of truth for the palette. Called by ws-preflight.sh (worktree)
# and by the attach / start-sandbox skills. Keeping the logic in one place
# means the curated table and the procedural generator never drift apart.
#
# Design: MAXIMUM SEPARATION inside a comfort box. The colors are placed by
# farthest-point sampling in CIELAB within a dark, white-text-readable band
# (relative luminance ≤ 0.055 → AAA contrast, chroma capped at 32 so nothing is
# as punchy as the wine that got rejected at ~38). Both lightness AND chroma
# carry the separation, so 16 colors sit ≥16 ΔE apart pairwise (was ~10 — that
# narrow band is why everything looked alike). Slot order is farthest-next so
# consecutive workspaces are ≥19 ΔE apart (no more two blues side by side).
# Names are descriptive (Maroon/Teal/Indigo…) because dark jewel tones aren't
# bright primaries.
#
# Slots 17+ generate a distinct hue per slot via golden-angle rotation, in the
# same dark jewel register (effectively infinite), badge = nearest circle.
#
# Usage:
#   ws-palette.sh <slot>
#
# Output (key=value, one per line):
#   COLOR=#5c383c
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

# Curated palette — index = slot - 1. Dark jewel tones, max-dispersed in CIELAB
# then ordered farthest-next so no two adjacent slots look alike. Verified:
# min pairwise ΔE 16.7, min consecutive ΔE 19.7, white-text contrast ≥ 10:1.
CURATED = [
    ("#5c383c", "🔴", "Maroon"),
    ("#004c30", "🟢", "Emerald"),
    ("#400c30", "🟣", "Mulberry"),
    ("#343800", "🟡", "Olive"),
    ("#1c1c48", "🔵", "Sapphire"),
    ("#54280c", "🟤", "Bronze"),
    ("#004470", "🔵", "Azure"),
    ("#480814", "🔴", "Garnet"),
    ("#004854", "🩵", "Teal"),
    ("#6c2c48", "🩷", "Wine"),
    ("#102810", "🟢", "Pine"),
    ("#483c58", "🟣", "Heather"),
    ("#341c10", "🟤", "Coffee"),
    ("#00243c", "🔵", "Steel"),
    ("#48402c", "🟡", "Khaki"),
    ("#202424", "⚫", "Slate"),
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
    r, g, b = colorsys.hls_to_rgb(hue / 360.0, 0.15, 0.50)  # H, L, S — dark jewel
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
