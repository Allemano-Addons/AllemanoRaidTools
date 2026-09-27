# Changelog

## 0.0.1
- Skeleton: core (events, saved data, error log `/srt errors`), slash command `/srt`.
- Addon messages between SRT users: long messages are split into parts, sending is paced
  (8 at once, then 1 per second) and retried when the client throttles, parts are joined
  again on arrival. `/srt comm test <bytes>` and `/srt comm debug` for testing.
- `/srt version`: which SRT version everyone in the group runs, who has no SRT, who is
  offline. A newer version seen in the group is mentioned once.
- `/srt probe`: records what the WoW Forever client supports (APIs, events, name formats,
  whether addon messages arrive) into the saved data for development.
