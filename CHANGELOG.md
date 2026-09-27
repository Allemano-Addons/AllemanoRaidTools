# Changelog

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
