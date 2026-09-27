std = "lua51"
max_line_length = false
self = false
exclude_files = { "Tests/**" }

-- The only globals SlaughterRaidTools may write.
globals = {
    "SlaughterRaidToolsDB",
    "SLASH_SLAUGHTERRAIDTOOLS1", "SLASH_SLAUGHTERRAIDTOOLS2", "SlashCmdList",
}

-- WoW API used by SlaughterRaidTools (read-only). Extend as new APIs are used.
read_globals = {
    "_G",
    "strjoin", "strsplit", "strtrim", "strlower", "strupper", "tostringall", "tinsert", "tremove",
    "wipe", "sort", "floor", "ceil", "min", "max", "format", "date", "time", "CopyTable", "geterrorhandler", "unpack",
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME",
    "GetBuildInfo", "GetTime", "GetAddOnMetadata", "C_AddOns", "C_Timer", "Constants", "IsAddOnLoaded",
    "UnitGUID", "UnitName", "UnitFullName", "GetNormalizedRealmName", "UnitIsConnected", "UnitPosition", "C_Map",
    "C_ChatInfo", "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetRaidRosterInfo",
    "UnitIsGroupLeader", "UnitIsGroupAssistant", "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE",
    "C_PartyInfo", "C_UnitAuras", "C_GuildInfo", "C_IncomingSummon", "C_SummonInfo",
}
