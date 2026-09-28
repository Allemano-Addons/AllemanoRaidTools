# SlaughterRaidTools (SRT)

Raid tools for **WoW Forever**, made for Slakthuset. Everyone in the raid should have it:
notes, ready check info and timers are shared between SRT users.

## Install

1. Unzip so you get `World of Warcraft\_classic_beta_\Interface\AddOns\SlaughterRaidTools\`.
2. Restart WoW (or log in). SRT shows in the addon list with its red logo.
3. Type `/srt` to open it. A small toolbar also shows at the top of the screen.

## What it does

| Where | What |
|---|---|
| **Home** | Tonight at a glance: raid readiness, the note, pulls tonight. |
| **Notes** | The raid leader writes notes and sends them; everyone sees them in the note window (`/srt note`). Raid icons `{skull}`, names in class color, `{p:Name}...{/p}` lines only those players see. A personal note of your own. |
| **Visual note** | Draw on a map or picture (pen, lines, arrows, icons, text) and share it with the raid (`/srt vn`). |
| **Raid check** | Flasks, elixirs, food, buffs, oil and durability for the whole raid. A ready check opens a small window with everyone's buff icons (mouse over for details). Categories are editable. |
| **Invites & groups** | Invite by guild rank or whisper keyword, auto convert and assist. Paste the OXM roster, drag players between groups, "Apply groups" moves the raid, "Invite roster" invites everyone on it. |
| **Pull log** | Every boss pull: time in combat, kill or wipe with the boss's health. |
| **Toolbar** | Raid icons, world markers, ready check, pull and break timers, note. Settings > Toolbar. |
| **Combat log** | Starts `/combatlog` by itself in raids (Settings > Combat log). |

Tools marked **SOON** in the sidebar are not built yet.

## Commands

`/srt` open or close · `/srt note` note window · `/srt vn` visual note · `/srt check` raid check ·
`/srt pull 10` · `/srt break 5` · `/srt rc` ready check · `/srt bar` toolbar · `/srt log` combat log ·
`/srt version` who runs which SRT version · `/srt errors` recent errors · `/srt help` everything

## Pictures for visual notes

Pictures are files in `SlaughterRaidTools\Images\`. Only the name is sent, so everyone who
should see a picture needs the same file. Make one from a screenshot or map (PNG/JPG):

```
powershell -ExecutionPolicy Bypass -File Tools\img2tga.ps1 -Src C:\path\map.png -Name wailing_caverns
```

Then **restart WoW** (a /reload does not find new files) and pick it under Visual note > Picture.

## Found a problem?

WoW Forever hides Lua errors. Type `/srt errors` and send a screenshot of what it says,
plus what you were doing, to Allemano.
