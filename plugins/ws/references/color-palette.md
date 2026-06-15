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

- **Slots 1–16** use a curated palette (table below). The 16 colors were chosen
  by farthest-point sampling in CIELAB so **every pair is ≥ 19 ΔE apart** — no
  two backgrounds look alike (e.g. Blue ↔ Indigo = 26 ΔE). The naive 8-color
  table this replaced had pairs as close as 4 ΔE.
- **Slots 17+** generate a distinct color procedurally: a golden-angle hue
  rotation (`hue = (slot-1) × 137.508° mod 360`) rendered in the same dark band
  (L* 28, max readable chroma). Every slot gets a fresh hue, so colors never
  repeat in practice. The badge becomes the nearest colored circle for that hue.

**Why backgrounds stay dark:** the color is painted as the terminal background
(OSC 11) and the VS Code titleBar/statusBar, both rendering **white text** on
top. So every color is a *dark tint* (L* 23–33, white-text contrast ≥ 7:1) —
"White" is a neutral light grey badged ⚪, not a literal white fill (which would
make the text invisible).

## Curated table (slots 1–16)

| Slot | Emoji | Hex       | Name    |
|------|-------|-----------|---------|
| 1    | 🔴    | `#6f0a2b` | Red     |
| 2    | 🟤    | `#753d42` | Rust    |
| 3    | 🟠    | `#652002` | Orange  |
| 4    | 🧡    | `#634224` | Amber   |
| 5    | 🟡    | `#5b4d00` | Yellow  |
| 6    | 🟩    | `#343a1b` | Lime    |
| 7    | 🟢    | `#004405` | Green   |
| 8    | 💚    | `#005948` | Teal    |
| 9    | 🩵    | `#00434a` | Cyan    |
| 10   | 🔵    | `#005578` | Blue    |
| 11   | 🟦    | `#1f498f` | Indigo  |
| 12   | 🟣    | `#43296b` | Purple  |
| 13   | 🟪    | `#553d63` | Plum    |
| 14   | 🩷    | `#731c52` | Pink    |
| 15   | ⚪    | `#58595c` | White   |
| 16   | ⚫    | `#23272e` | Slate   |

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
