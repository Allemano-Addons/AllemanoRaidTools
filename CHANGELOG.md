# Changelog

## 0.8.0
- Auto logging: the combat log (/combatlog) starts when you enter a raid instance and stops
  when you leave (only a log SRT started; one you started yourself is left alone). Advanced
  combat logging (Warcraft Logs) is switched on with it. Options under Settings > Combat log:
  raids, dungeons too, advanced logging, chat line. `/srt log` starts/stops it by hand.

## 0.7.1
- Raid check sees SRT users who are too far away for the game to show their buffs: every
  SRT user sends their own buffs (spell ID and time left) at a ready check and when the
  leader scans; names and icons come from the spell ID, so the leader's categories decide
  what counts. Reports older than 5 minutes are not used. The tooltip says "Reported by SRT
  (out of range)". Far away players without SRT still show ?.
- Ready check window: stays open while the mouse is over it; closes 8 s after everyone is
  ready (was 3 s), adjustable under Raid check > Categories ("Close window").

## 0.7.0
- Ready check window: a ready check opens a small SRT window (not the main window) with the
  ready check timer in the title, a ready/not ready/waiting icon and the name in class color
  per player, and one column per category showing the buff's own icon (orange line = less
  than 10 min left, red x = missing, ? = out of range / no SRT). It updates when people take
  their buffs and closes itself 3 s after everyone is ready, or 15 s after the check when
  someone was not ready or away (afk). Drag the title to move it; "Details" opens the raid
  check page. `/srt rcwindow` shows it without a ready check.
- Mouse over a buff (in the window and in the raid check table) shows the game's tooltip for
  that buff: which flask, food etc. and the time left.
- Setting "Ready check window": Everyone (default), Leader/assist or Off (Raid check >
  Categories). The main window no longer opens on a ready check.

## 0.6.1
- Errors saved by an older SRT version are dropped when a new version loads (they were
  fixed); `/srt errors` only shows the current version's.

## 0.6.0
- Raid check (Before pull > Raid check, `/srt check`): a table of the group with one column
  per category. Cells show minutes left, "ok", "x" (missing, red), "?" (out of range or no
  SRT) or the ready check answer. The header shows have/total per column. "Only missing"
  filter, "Post missing" to raid chat (optional columns left out), "Scan".
- Categories are editable (Categories tab): short name, name, what counts (buff names or a
  part of them, and spell IDs, separated by commas), optional, on/off; add and remove your
  own; reset to defaults. Defaults (Classic, as a start): Ready, Flask, Battle elixir,
  Guardian elixir, Food, Oil, Rune (off, empty), Int, Stam, MotW, Spirit, AP, Scroll,
  Soulstone, Durability, Blessings (own column: Ki Mi Wi...).
- Weapon oil and durability cannot be read for other players: every SRT user reports their
  own at a ready check and when the leader scans.
- A ready check opens the raid check for the leader/assistants (can be turned off) and fills
  the Ready column as people answer.
- Home: the Raid readiness card shows bars for the first four required columns and who is
  missing the first one.

## 0.5.0
- Groups: party members count as "in the group" (not only raid members).
- New box "In the group, not on the roster": everyone in your party/raid who is not on the
  roster. Drag them into a group to add them; drag a roster name into the box to take it off.
- Names are shown in class color (group members and guild members); a colored stripe shows
  the status: in their group, in the group elsewhere (gN), can be invited, offline, same
  first name twice, not found.
- Dragging now only changes the plan. "Apply groups" (was "Sort groups") moves the raid.
  `/srt apply`.
- "Invite roster (N)" (was "Invite missing") invites everyone on the roster who is online in
  the guild and posts a message in guild or officer chat. Channel and message under Invite >
  Roster invite. `/srt invroster`.

## 0.4.3
- Toolbar rows: 1, 2 or 3 rows (columns when vertical), in Settings > Toolbar or the handle's
  right-click menu. Button groups stay together and are split so the rows are as even as
  possible.

## 0.4.2
- Fix: the toolbar x next to the world markers did not remove them ("/cwm 0" does nothing on
  WoW Forever). It now clears markers 1-8 one by one.

## 0.4.1
- Fix: clicking a raid target icon on the toolbar showed "SlaughterRaidTools has been blocked
  from an action only available to the Blizzard UI". Setting target icons is protected on WoW
  Forever, so the icon buttons are now secure "/tm N" macro buttons like the world markers.
  Clicking the same icon again no longer removes it; use the x next to the icons.
- The highlighted icon never errors in combat when the game hides the value.

## 0.4.0
- Toolbar: a small bar outside the main window (shown by default, `/srt bar` toggles it).
  Pick what it shows (Settings > Toolbar, or right-click its colored handle):
  - Open SRT
  - Raid target icons on your target (click again removes it; the icon on your target is
    highlighted) + remove
  - World markers (click, then click the ground) + remove all
  - Ready check, Pull (click 10, shift-click 15, right-click cancel), Break (click 10 min,
    shift-click 5, right-click or click while running ends it), Note window
  Options: only in a group, lock, vertical, size. The bar cannot change in combat; changes
  wait until combat ends.

## 0.3.1
- Groups: drag names between the group boxes. Dropped on a name (or an empty place) the two
  swap; dropped elsewhere in a box the name goes to its first free place. The roster text is
  updated ("-" marks an empty place), and in a raid (leader/assistant, out of combat) the
  dragged players are moved right away. An empty extra group is shown to drop into.
- Fix: your own name showed as "same first name twice" when an alt shares your first name.
  You are never matched against the guild list; outside a raid you show as "(you)".

## 0.3.0
- Invites & groups page, tab Invite:
  - Guild ranks: tick ranks, "Invite online (N)" invites their online members.
  - Keyword invite: players who whisper the keyword (default "inv") are invited, optionally
    guild members only.
  - Convert to raid automatically when the party is full; the invite queue fills the party
    first (4 invites), converts once someone accepts, then invites the rest.
  - Give assist to a list of names when they join (raid leader only).
- Tab Groups: paste the OXM roster (names top to bottom, five per group, blank lines ignored,
  "Name/Other" = either). Groups 1-8 show who is in their group, in the raid elsewhere, can be
  invited from the guild, offline, has a first name shared by two players, or is not found;
  plus raid members who are not on the roster. "Invite missing" and "Sort groups" (one move
  at a time, stops in combat).
- `/srt inv` (ranks) or `/srt inv Name`, `/srt sort`.

## 0.2.1
- Note window background opacity: Appearance > Note window (0% = see-through, only the
  text shows; the border fades with it).
- Your own name in notes now uses your class color like everyone else, not the accent.

## 0.2.0
- Notes page: saved raid notes (list + editor, saved while typing), raid icon buttons,
  "Insert name" from the group, formatting help. "Send to raid" (leader/assistant), "Post in
  raid chat" (skips private text), Delete. Solo, "Show to me" shows the note only to you.
- Formatting: {rt1}..{rt8} / {skull}..., {spell:ID}, {p:Name, Name}...{/p} (only those players
  see it). Group members are shown in class color, your own name in the accent.
- Note window for everyone (`/srt note`): moves, resizes, locks, scrolls; stays open through
  ESC; opens by itself when a new note arrives (can be turned off). Personal note per
  character under the raid note.
- Raiders confirm the note: the leader sees "N of M have it" and who is missing (offline, no
  SRT) on Home. Resend and Post in raid chat on the Home card. Players who join later (or
  /reload) ask for the note and get it from the leader.
- Notes are only accepted from the raid leader or an assistant.
- Header "Send note" sends the note selected under Notes.

## 0.1.1
- The window can be resized from the bottom right corner (820x560 up to 1800x1200); the
  size is saved. "Reset" under Appearance also restores the default size.
- Sidebar section titles (Overview, Plan, Before pull...) use the accent color.

## 0.1.0
- Main window (`/srt`): sidebar with every tool grouped Overview / Plan / Before pull /
  During / After / Settings. Tools that are not built yet say what they will do.
- Header: raid status (online, in zone, when the raid formed, break time left) and the
  leader's quick actions: Ready check, Pull 10s, Break 10 min / End break, Send note (not
  yet). Greyed out for raiders who are not leader or assistant.
- Pull uses Blizzard's own countdown (everyone sees it, SRT or not). If the client refuses
  it, SRT shows its own pull bar to SRT users and posts "Pull in N" in raid chat.
- Break timer: a bar for everyone with SRT (drag to move, right-click hides), posted in raid
  chat for the rest ("Break 10 min, back at 21:14", can be turned off). Survives /reload.
  `/srt pull [seconds]`, `/srt break [minutes]` (0 ends), `/srt rc`.
- Home page with the cards from the mockup (filled in as the tools arrive).
- Settings pages: Appearance (accent color like Hush: default, class colors and more, or
  "use my class color"; font; text size; background; window scale; reset position) and
  Advanced (break announcements, addon message debug, probes, version check, errors).
- `/srt probe` also reads group members' buffs; `/srt probe combat` (or "Run probe" on
  Home) records the next fights: addon message restrictions, secret values in auras,
  health and cooldowns, what C_RestrictedActions / C_Secrets report.
- Blocked protected calls are recorded in `/srt errors`.


## 0.0.1
- Skeleton: core (events, saved data, error log `/srt errors`), slash command `/srt`.
- Addon messages between SRT users: long messages are split into parts, sending is paced
  (8 at once, then 1 per second) and retried when the client throttles, parts are joined
  again on arrival. `/srt comm test <bytes>` and `/srt comm debug` for testing.
- `/srt version`: which SRT version everyone in the group runs, who has no SRT, who is
  offline. A newer version seen in the group is mentioned once.
- `/srt probe`: records what the WoW Forever client supports (APIs, events, name formats,
  whether addon messages arrive) into the saved data for development.
