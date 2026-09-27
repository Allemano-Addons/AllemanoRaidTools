# Changelog

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
