std = "lua51"
max_line_length = false
self = false
exclude_files = { "Tests/**" }

-- The only globals SlaughterRaidTools may write.
globals = {
    "SlaughterRaidToolsDB",
    "SLASH_SLAUGHTERRAIDTOOLS1", "SLASH_SLAUGHTERRAIDTOOLS2", "SlashCmdList",
    "SlaughterRaidToolsFrame", -- named only so ESC closes it (UISpecialFrames)
}

-- WoW API used by SlaughterRaidTools (read-only). Extend as new APIs are used.
read_globals = {
    "_G",
    "strjoin", "strsplit", "strtrim", "strlower", "strupper", "tostringall", "tinsert", "tremove",
    "wipe", "sort", "floor", "ceil", "min", "max", "format", "date", "time", "CopyTable", "geterrorhandler", "unpack",
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "GameTooltip", "UISpecialFrames", "GetCursorPosition", "GetPhysicalScreenSize", "LibStub",
    "GetBuildInfo", "GetTime", "GetServerTime", "GetAddOnMetadata", "C_AddOns", "C_Timer", "Constants", "IsAddOnLoaded",
    "UnitGUID", "UnitName", "UnitFullName", "UnitClass", "GetNormalizedRealmName", "UnitIsConnected", "UnitPosition", "C_Map",
    "UnitHealth", "UnitHealthMax", "C_Spell", "GetSpellInfo", "LoggingCombat", "SetCVar", "C_CVar", "issecretvalue", "InCombatLockdown", "C_RestrictedActions", "C_Secrets",
    "C_ChatInfo", "SendChatMessage", "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetRaidRosterInfo",
    "UnitIsGroupLeader", "UnitIsGroupAssistant", "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE", "DoReadyCheck",
    "C_PartyInfo", "C_UnitAuras", "C_GuildInfo", "C_IncomingSummon", "C_SummonInfo", "IsInInstance", "GetInstanceInfo",
    "IsInGuild", "GetGuildInfo", "UnitExists", "UnitIsVisible", "GetInventoryItemDurability", "GetWeaponEnchantInfo", "GetRaidTargetIndex", "IsShiftKeyDown", "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster", "SetRaidSubgroup", "SwapRaidSubgroup", "PromoteToAssistant", "ConvertToRaid", "InviteUnit", "CUSTOM_CLASS_COLORS", "RAID_CLASS_COLORS", "LOCALIZED_CLASS_NAMES_MALE",
}
