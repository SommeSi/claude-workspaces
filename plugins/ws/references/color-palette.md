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

**Design goal: dark & easy on the eyes first, distinct second.** Backgrounds are
painted full-screen on the terminal (OSC 11) and the VS Code titleBar/statusBar,
both rendering **white text** on top — so a bright/saturated fill is fatiguing.
Every color is a deep muted tint (relative luminance ≤ ~0.04, white-text
contrast ≥ 12:1). "White" is a neutral light grey badged ⚪, not a literal white
fill (which would hide the text).

At this comfortable dark level, 16 *mutually* distinct colors is physically
impossible — so the trade is:

- **Slots 1–8** (the ones actually run concurrently, since slots are handed out
  lowest-first) are both comfortable **and** distinct (≥ 8 ΔE apart).
- **Slots 9–16** add variety; a few warm tones (Orange/Brown/Amber) sit closer,
  but they rarely co-occur. Blue ↔ Indigo — the pair that motivated this — is
  ~15 ΔE apart.
- **Slots 17+** generate a distinct hue per slot via golden-angle rotation
  (`hue = (slot-1) × 137.508° mod 360`) in the same dark muted register
  (`HLS L=0.15, S=0.40`) — effectively infinite, badge = nearest colored circle.

## Curated table (slots 1–16)

| Slot | Emoji | Hex       | Name    |
|------|-------|-----------|---------|
| 1    | 🟢    | `#1a3a2a` | Green   |
| 2    | 🟠    | `#3a2a15` | Orange  |
| 3    | 🟣    | `#2a1a3a` | Purple  |
| 4    | 🔴    | `#3a1515` | Red     |
| 5    | 🩵    | `#15353a` | Cyan    |
| 6    | 🩷    | `#3a1a2e` | Pink    |
| 7    | 🟡    | `#3a3415` | Yellow  |
| 8    | 🔵    | `#1a2835` | Blue    |
| 9    | ⚪    | `#313133` | White   |
| 10   | 🟤    | `#38220f` | Brown   |
| 11   | 🟩    | `#2c3a12` | Lime    |
| 12   | ⚫    | `#1f2024` | Slate   |
| 13   | 💚    | `#103a33` | Teal    |
| 14   | 🟪    | `#3a153a` | Magenta |
| 15   | 🟦    | `#1c1f40` | Indigo  |
| 16   | 🧡    | `#3a2208` | Amber   |

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
