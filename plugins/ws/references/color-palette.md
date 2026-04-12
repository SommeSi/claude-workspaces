# Color Palette

8 colors, assigned by slot. Slots beyond 8 cycle: `index = ((slot - 1) % 8)`.

| Index | Slot(s)      | Emoji | Hex       | Name   |
|-------|--------------|-------|-----------|--------|
| 0     | 1, 9, 17...  | 🟢    | `#1a3a2a` | Green  |
| 1     | 2, 10, 18... | 🟠    | `#3a2a15` | Orange |
| 2     | 3, 11, 19... | 🟣    | `#2a1a3a` | Purple |
| 3     | 4, 12, 20... | 🔴    | `#3a1515` | Red    |
| 4     | 5, 13, 21... | 🩵    | `#15353a` | Cyan   |
| 5     | 6, 14, 22... | 🩷    | `#3a1a2e` | Pink   |
| 6     | 7, 15, 23... | 🟡    | `#3a3415` | Yellow |
| 7     | 8, 16, 24... | 🔵    | `#1a2835` | Blue   |

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
