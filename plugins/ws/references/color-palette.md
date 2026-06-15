# Color Palette

Colors are assigned by slot and are **effectively infinite**. Never compute a
color by hand — always resolve it through the single source of truth:

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-palette.sh" <slot>
# → COLOR=#1a3a2a
#   EMOJI=🟢
#   NAME=Green
```

## How it works

**Design: comfort first for a full-screen fill.** Backgrounds are painted
full-screen on the terminal (OSC 11) and the VS Code titleBar/statusBar, both
rendering **white text** on top. A saturated color is fatiguing across a whole
screen *even when it's dark* — so the register is BOTH dark AND muted (relative
luminance ≤ 0.030, low chroma; every color is calmer than the wine that got
rejected). Placed by farthest-point sampling in CIELAB within that comfortable
band → **min ~10 ΔE** between any two, which reads as "clearly different but
calm".

- Names are **descriptive** (Olive/Steel/Plum…) because muted darks aren't
  bright primaries. Badges are the nearest colored circle and may repeat across
  families — the *colors* are what's distinct.
- "White" is a neutral grey badged ⚪ (a literal white fill would hide the text).
- **Slots 17+** generate a distinct hue per slot via golden-angle rotation
  (`hue = (slot-1) × 137.508° mod 360`), kept dark & muted (`HLS L=0.13,
  S=0.30`) — effectively infinite, badge = nearest colored circle.

## Curated table (slots 1–16)

| Slot | Emoji | Hex       | Name   |
|------|-------|-----------|--------|
| 1    | 🔴    | `#3f282c` | Maroon |
| 2    | 🟤    | `#3a1b15` | Rust   |
| 3    | 🟡    | `#382c21` | Olive  |
| 4    | 🟠    | `#2c1a00` | Khaki  |
| 5    | 🟡    | `#262507` | Gold   |
| 6    | 🟢    | `#20331c` | Forest |
| 7    | 🟢    | `#162014` | Pine   |
| 8    | 💚    | `#002c22` | Spruce |
| 9    | 🩵    | `#072122` | Teal   |
| 10   | 🔵    | `#00343c` | Steel  |
| 11   | 🟦    | `#062a41` | Iris   |
| 12   | 🟣    | `#1e1a33` | Plum   |
| 13   | 🟪    | `#312b3d` | Grape  |
| 14   | 🩷    | `#391c2f` | Rose   |
| 15   | ⚪    | `#303034` | White  |
| 16   | ⚫    | `#191a1e` | Slate  |

## Terminal Coloring

Apply color to current terminal. **Important:** Claude Code's Bash tool captures stdout, so escape sequences must be written directly to the parent process's TTY device.

```bash
# Detect the parent terminal device
TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# Set background color (OSC 11)
printf '\033]11;#1a3a2a\007' > "$TTY_DEV" 2>/dev/null

# Set tab name (OSC 1) and window title (OSC 0)
printf '\033]1;🟢 feat/polo/export-csv [w1]\007' > "$TTY_DEV" 2>/dev/null
printf '\033]0;🟢 feat/polo/export-csv [w1]\007' > "$TTY_DEV" 2>/dev/null
```

## Reset Terminal

```bash
TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# Reset background to default
printf '\033]11;\007' > "$TTY_DEV" 2>/dev/null

# Reset tab name and window title
printf '\033]1;\007' > "$TTY_DEV" 2>/dev/null
printf '\033]0;\007' > "$TTY_DEV" 2>/dev/null
```
