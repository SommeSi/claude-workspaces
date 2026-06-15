#!/bin/bash
# ws-palette.sh — Resolve a workspace's color/emoji/name from its slot.
#
# Single source of truth for the palette. Called by ws-preflight.sh (worktree)
# and by the attach / start-sandbox skills. Keeping the logic in one place
# means the curated table and the procedural generator never drift apart.
#
# Slots 1..16 use a hand-picked palette. The 16 colors were chosen by
# farthest-point sampling in CIELAB so EVERY pair is ≥ 19 ΔE apart — i.e. no
# two backgrounds look alike (the naive table this replaced had pairs as close
# as 4 ΔE, e.g. Blue/Indigo, Green/Teal). All stay in a dark band (L* 23-33)
# so the white terminal / VS Code foreground keeps ≥ 7:1 contrast.
#
# Slots 17+ generate a distinct color via golden-angle hue rotation in the same
# dark band (effectively infinite — a new hue every slot), badge = nearest
# colored circle.
#
# Usage:
#   ws-palette.sh <slot>
#
# Output (key=value, one per line):
#   COLOR=#6f0a2b
#   EMOJI=🔴
#   NAME=Red

set -euo pipefail

SLOT="${1:-}"
if [ -z "$SLOT" ]; then
  echo "Usage: ws-palette.sh <slot>" >&2
  exit 1
fi

python3 - "$SLOT" <<'PYEOF'
import sys, math

# Curated palette — index = slot - 1. Backgrounds are dark tints because both
# the terminal and the VS Code titleBar render WHITE text on top of them.
# "White" is therefore a neutral light-grey badged ⚪, not a literal white fill.
# Every pair is ≥ 19 ΔE apart (verified) so adjacent slots never look similar.
CURATED = [
    ("#6f0a2b", "🔴", "Red"),
    ("#753d42", "🟤", "Rust"),
    ("#652002", "🟠", "Orange"),
    ("#634224", "🧡", "Amber"),
    ("#5b4d00", "🟡", "Yellow"),
    ("#343a1b", "🟩", "Lime"),
    ("#004405", "🟢", "Green"),
    ("#005948", "💚", "Teal"),
    ("#00434a", "🩵", "Cyan"),
    ("#005578", "🔵", "Blue"),
    ("#1f498f", "🟦", "Indigo"),
    ("#43296b", "🟣", "Purple"),
    ("#553d63", "🟪", "Plum"),
    ("#731c52", "🩷", "Pink"),
    ("#58595c", "⚪", "White"),
    ("#23272e", "⚫", "Slate"),
]

GOLDEN_ANGLE = 137.508  # degrees — maximally spreads successive hues

def _lab_to_rgb(L, a, b):
    fy = (L + 16) / 116
    fx = fy + a / 500
    fz = fy - b / 200
    g = lambda t: t ** 3 if t ** 3 > 0.008856 else (t - 16 / 116) / 7.787
    X, Y, Z = g(fx) * 0.95047, g(fy), g(fz) * 1.08883
    r = X * 3.2406 + Y * -1.5372 + Z * -0.4986
    gr = X * -0.9689 + Y * 1.8758 + Z * 0.0415
    bl = X * 0.0557 + Y * -0.2040 + Z * 1.0570
    def enc(c):
        c = max(0.0, min(1.0, c))
        c = 1.055 * c ** (1 / 2.4) - 0.055 if c > 0.0031308 else 12.92 * c
        return max(0, min(255, round(c * 255)))
    return enc(r), enc(gr), enc(bl)

def _rel_luminance(r, g, b):
    lin = lambda c: (c / 255) / 12.92 if c <= 10.31 else (((c / 255) + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)

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
    # Procedural: a distinct hue per slot in the same dark band as the curated
    # palette. Render at L*=28 and the highest chroma that stays readable
    # (white text ≥ ~4.5:1), so generated colors match the curated aesthetic.
    hue = ((slot - 1) * GOLDEN_ANGLE) % 360
    L = 28.0
    rgb = None
    for chroma in range(40, 8, -2):
        a = chroma * math.cos(math.radians(hue))
        b = chroma * math.sin(math.radians(hue))
        cand = _lab_to_rgb(L, a, b)
        if _rel_luminance(*cand) <= 0.13:
            rgb = cand
            break
    if rgb is None:
        rgb = _lab_to_rgb(L, 0, 0)
    color = "#%02x%02x%02x" % rgb
    return (color, emoji_for_hue(hue), "Hue %d°" % round(hue))

try:
    slot = int(sys.argv[1])
except ValueError:
    sys.stderr.write("slot must be an integer\n")
    sys.exit(1)

color, emoji, name = resolve(slot)
sys.stdout.write("COLOR=%s\nEMOJI=%s\nNAME=%s\n" % (color, emoji, name))
PYEOF
