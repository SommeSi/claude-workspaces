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

Apply color to current terminal:

```bash
# Set background color (OSC 11)
printf '\033]11;#1a3a2a\007'

# Set window/tab title (OSC 0)
printf '\033]0;🟢 feat/polo/export-csv [w1]\007'
```

## Reset Terminal

```bash
# Reset background to default (OSC 11 with empty value)
printf '\033]11;\007'

# Reset title
printf '\033]0;\007'
```
