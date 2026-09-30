# Allemano Raid Tools (ART)

Part of **Allemano Addons**.

Raid tools for **WoW Forever**, made for raid groups. Everyone in the raid should have it:
notes, ready check info and timers are shared between ART users.

## Install

1. Unzip so you get `World of Warcraft\_classic_beta_\Interface\AddOns\AllemanoRaidTools\`.
2. Restart WoW (or log in). ART shows in the addon list with its red logo.
3. Type `/art` to open it. A small toolbar also shows at the top of the screen.

## What it does

| Where | What |
|---|---|
| **Home** | Tonight at a glance: raid readiness, the note, pulls tonight. |
| **Notes** | The raid leader writes notes and sends them; everyone sees them in the note window (`/art note`). Raid icons `{skull}`, names in class color, `{p:Name}...{/p}` lines only those players see. A personal note of your own. |
| **Visual note** | Draw on a map or picture (pen, lines, arrows, icons, text) and share it with the raid (`/art vn`). |
| **Raid check** | Flasks, elixirs, food, buffs, oil and durability for the whole raid. A ready check opens a small window with everyone's buff icons (mouse over for details). Categories are editable. |
| **Invites & groups** | Invite by guild rank or whisper keyword, auto convert and assist. Roster profiles: several saved rosters by name ("New", then paste the OXM roster). Drag players between groups, "Apply groups" moves the raid, "Invite roster" invites everyone on it. |
| **Marks** | Hold Ctrl and scroll the mouse wheel over a mob: it gets a raid icon. Give mobs their own icon lists ("Add target"): before the pull every mob gets the next free icon of its list, and a marked mob keeps its icon, so you can just scroll over the pack. |
| **Pull log** | Every boss pull: time in combat, kill or wipe with the boss's health. |
| **Toolbar** | Raid icons, world markers, ready check, pull and break timers, note. Settings > Toolbar. Plus a small ART button on the screen (drag to move, `/art button` hides it). |
| **Combat log** | Starts `/combatlog` by itself in raids (Settings > Combat log). |

Tools marked **SOON** in the sidebar are not built yet.

## Commands

`/art` open or close · `/art note` note window · `/art vn` visual note · `/art check` raid check ·
`/art pull 10` · `/art break 5` · `/art rc` ready check · `/art bar` toolbar · `/art log` combat log ·
`/art button` launcher button · `/art version` who runs which ART version · `/art errors` recent errors · `/art help` everything

## Pictures for visual notes

Pictures are files in `AllemanoRaidTools\Images\`. Only the name is sent, so everyone who
should see a picture needs the same file. Make one from a screenshot or map (PNG/JPG):

```
powershell -ExecutionPolicy Bypass -File Tools\img2tga.ps1 -Src C:\path\map.png -Name wailing_caverns
```

Then **restart WoW** (a /reload does not find new files) and pick it under Visual note > Picture.

## Found a problem?

WoW Forever hides Lua errors. Type `/art errors` and send a screenshot of what it says,
plus what you were doing, to Allemano.
