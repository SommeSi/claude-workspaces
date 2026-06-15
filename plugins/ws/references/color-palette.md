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

**Design: dark jewel tones — rich but lightness-capped.** Backgrounds are
painted full-screen on the terminal (OSC 11) and the VS Code titleBar/statusBar,
both rendering **white text** on top. Eye strain comes from **lightness**, not
saturation — so colors are kept dark (relative luminance ≤ ~0.047, white-text
contrast ≥ 10:1) while staying saturated enough to tell apart (deep wine, navy,
forest, plum). Placed by farthest-point sampling in CIELAB: **min 16.6 ΔE
between any two** colors.

- Names/badges are **approximate** — dark warm tones read as wine/copper/gold
  rather than bright red/orange/yellow, and Unicode only has ~9 colored circles,
  so some badges repeat across families. The *colors* are all distinct.
- "White" is a neutral light grey badged ⚪ (a literal white fill would hide the
  text).
- **Slots 17+** generate a distinct hue per slot via golden-angle rotation
  (`hue = (slot-1) × 137.508° mod 360`), kept dark & saturated (`HLS L=0.14,
  S=0.85`) — effectively infinite, badge = nearest colored circle.

## Curated table (slots 1–16)

| Slot | Emoji | Hex       | Name    |
|------|-------|-----------|---------|
| 1    | 🔴    | `#360216` | Red     |
| 2    | 🩷    | `#6d182f` | Crimson |
| 3    | 🟤    | `#520e00` | Rust    |
| 4    | 🟠    | `#3c2115` | Copper  |
| 5    | 🟡    | `#4a3601` | Gold    |
| 6    | 🟩    | `#1c2200` | Lime    |
| 7    | 🟢    | `#174004` | Green   |
| 8    | 💚    | `#004332` | Teal    |
| 9    | 🔵    | `#003f59` | Blue    |
| 10   | 🩵    | `#003e74` | Azure   |
| 11   | 🟦    | `#151337` | Indigo  |
| 12   | 🟣    | `#402e69` | Violet  |
| 13   | 🟪    | `#4d1349` | Magenta |
| 14   | 💜    | `#502e45` | Plum    |
| 15   | ⚪    | `#3a3b3e` | White   |
| 16   | ⚫    | `#17181c` | Slate   |

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
