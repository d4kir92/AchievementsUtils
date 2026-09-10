# AchievementsUtils

Everything the achievement window should have done from the start: a real search, suggestions
for what to do where you are standing, a watch list, related achievements, far more useful
tooltips and reminders for the things you would otherwise walk past.

No hardcoded achievement data. Everything is read from the game at runtime, so it works in
every client language and keeps working after a patch.

# Features

## Extra tabs in the achievement window

The extra tabs are added next to Blizzard's own tabs and open as an overlay, so nothing of the
default achievement UI is replaced, hidden or re-parented.

- **Search** - searches name, description and reward of every achievement, or an achievement ID
  directly. Typing gets faster with every character, not slower.
- **Suggestions** - open achievements for your current zone, your current subzone, the running
  holiday events and the current expansion, split into single and meta achievements.
- **Watch** - your own watch list, kept per character.
- **Related** - the series the selected achievement belongs to, what requires it and what it
  consists of.

Results are grouped under collapsible headers, the search box on top doubles as a filter on the
Suggestions and Watch tab, and achievements can be shown in two styles: the full Blizzard-style
plaque (**Default**) or a compact one-line row (**Compact**).

## Achievement tooltips

- Criteria in two columns with a ready/not-ready mark, including the progress the default UI
  hides
- Quantity criteria as a real progress bar inside the tooltip
- "Part of a series" as a numbered list and "Required by" for meta achievements
- Optional achievement ID
- Works on tracked achievements in the objective tracker too
- Adjustable criteria line limit

## Achievement links in chat

- A linked achievement is compared against your own progress
- Ctrl+Click a link twice to track that achievement
- Alt+Click an achievement for a Wowhead link

## Reminders

Hovering something in the world tells you whether it is still needed for an achievement:
critters and creatures, players (class names for holiday achievements), items such as food,
drinks and recipes, and objects such as books or fishing spots. Optionally with a sound, and
optionally including criteria you already completed.

This is driven by the criteria names read from the game itself - no shipped data tables, so it
covers every locale and needs no per-patch maintenance.

## Automatic tracking

Tracks achievements for you while you play: the ones for your current zone, timed achievements
the moment the timer starts, and optionally everything on your watch list. The number of
automatically tracked achievements is capped by a slider.

## Achievement window quality of life

- Draggable achievement window with a remembered position
- Back/forward buttons for visited achievements, with a right-click list
- Right-click context menu on any achievement: chat link, Wowhead link, watch list, tracking and
  the achievement's series
- Optionally restores the last tab and achievement between sessions

# Settings

Every module can be switched off on its own, and the settings window shows which option depends
on which - a child option is greyed out and labelled `requires <parent>` while its parent is off.
Nothing needs a reload.

Open the settings with the minimap button (optional, can be switched off) or:

```
/au
/achievementsutils
```

Other commands:

| Command | Does |
| --- | --- |
| `/ach <text>` | opens the Search tab with that term, e.g. `/ach food` |
| `/au reindex` | deletes the cached index and rebuilds it |
| `/au reset` | resets the achievement window position |

# Supported versions

Retail, Mists of Pandaria Classic, Cataclysm Classic, Wrath Classic, Burning Crusade Classic and
Classic Era.

# Download

https://addons.wago.io/addons/achievementsutils

https://www.curseforge.com/wow/addons/achievementsutils
