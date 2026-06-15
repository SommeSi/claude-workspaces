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

- **Slots 1–16** use a curated palette (table below).
- **Slots 17+** generate a distinct color procedurally: a golden-angle hue
  rotation (`hue = (slot-1) × 137.508° mod 360`) rendered at a fixed dark tint
  (`HSL(hue, 45%, 16%)`). Every slot gets a fresh hue, so colors never repeat
  in practice. The badge becomes the nearest colored circle for that hue.

**Why backgrounds stay dark:** the color is painted as the terminal background
(OSC 11) and the VS Code titleBar/statusBar, both rendering **white text** on
top. So every color is a *dark tint* — "White" is a neutral dark grey badged
⚪, not a literal white fill (which would make the text invisible).

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
| 9    | ⚪    | `#2e2e2e` | White   |
| 10   | 🟤    | `#3a2a1f` | Brown   |
| 11   | 🟩    | `#2a3a15` | Lime    |
| 12   | 🟦    | `#1a1f3a` | Indigo  |
| 13   | 🟪    | `#341a3a` | Magenta |
| 14   | 💚    | `#153a30` | Teal    |
| 15   | 🧡    | `#3a2410` | Amber   |
| 16   | ⚫    | `#20242a` | Slate   |

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
