-- Probe (step 0): records what the WoW Forever client really offers for the raid tools
-- SRT will build: which APIs and events exist, how names look and whether addon messages
-- arrive. Saved to SlaughterRaidToolsDB.probe so it can be read from the SavedVariables
-- file after /reload. Never calls protected functions.
local _, SRT = ...

-- Every return value as a string (keeps nils visible, never saves odd types).
local function pack(...)
    local t = { n = select("#", ...) }
    for i = 1, t.n do t[i] = tostring((select(i, ...))) end
    return t
end

local function try(fn, ...)
    if type(fn) ~= "function" then return { missing = true } end
    local res = pack(pcall(fn, ...))
    if res[1] ~= "true" then return { err = res[2] } end
    tremove(res, 1)
    res.n = res.n - 1
    return res
end

local API_NAMES = {
    -- addon messages and chat
    "C_ChatInfo", "SendAddonMessage", "RegisterAddonMessagePrefix", "Ambiguate", "SendChatMessage",
    -- group and invites
    "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetRaidRosterInfo",
    "UnitIsGroupLeader", "UnitIsGroupAssistant", "InviteUnit", "UninviteUnit", "C_PartyInfo",
    "ConvertToRaid", "ConvertToParty", "PromoteToAssistant", "DemoteAssistant", "PromoteToLeader",
    "SetEveryoneIsAssistant", "SetRaidSubgroup", "SwapRaidSubgroup", "UnitIsConnected",
    -- guild
    "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster", "C_GuildInfo", "GuildControlGetRankName",
    -- ready check and consumables
    "DoReadyCheck", "GetReadyCheckStatus", "ConfirmReadyCheck", "UnitAura", "UnitBuff", "C_UnitAuras", "AuraUtil",
    -- timers
    "C_PartyInfo", "RaidNotice_AddMessage", "RaidWarningFrame", "PlaySound", "PlaySoundFile", "SOUNDKIT",
    -- markers
    "SetRaidTarget", "GetRaidTargetIndex", "PlaceRaidMarker", "ClearRaidMarker", "IsRaidMarkerActive",
    "SetRaidTargetIconTexture", "CanBeRaidTarget",
    -- summons and positions
    "UnitPosition", "C_Map", "GetRealZoneText", "UnitInRange", "CheckInteractDistance", "UnitIsVisible",
    "C_IncomingSummon", "C_SummonInfo", "IsInInstance", "GetInstanceInfo",
    -- loot
    "GetLootMethod", "SetLootMethod", "C_LootHistory", "GetMasterLootCandidate",
    -- misc
    "issecretvalue", "InCombatLockdown", "SecureCmdOptionParse", "C_Timer", "C_AddOns", "IsAddOnLoaded",
}

local EVENTS = {
    "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "READY_CHECK", "READY_CHECK_CONFIRM",
    "READY_CHECK_FINISHED", "START_TIMER", "START_PLAYER_COUNTDOWN", "CANCEL_PLAYER_COUNTDOWN",
    "RAID_TARGET_UPDATE", "ENCOUNTER_START", "ENCOUNTER_END", "CONFIRM_SUMMON", "INCOMING_SUMMON_CHANGED",
    "PARTY_INVITE_REQUEST", "CHAT_MSG_WHISPER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "GUILD_ROSTER_UPDATE", "UNIT_AURA", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA",
}

local ADDONS = { "DBM-Core", "BigWigs", "BigWigs_Core", "MRT", "ExRT", "RCLootCouncil", "RCLootCouncil_Classic", "WeakAuras", "ForeverAuras" }

local function fns(tbl)
    local list = {}
    if type(tbl) == "table" then
        for k, v in pairs(tbl) do if type(v) == "function" then list[#list + 1] = k end end
    end
    sort(list)
    return table.concat(list, " ")
end

local function probeApis()
    local out = {}
    for _, name in ipairs(API_NAMES) do out[name] = type(_G[name]) end
    local ns = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^C_") and type(v) == "table" then ns[#ns + 1] = k end
    end
    sort(ns)
    out._namespaces = table.concat(ns, " ")
    out._C_ChatInfo = fns(C_ChatInfo)
    out._C_PartyInfo = fns(C_PartyInfo)
    out._C_UnitAuras = fns(C_UnitAuras)
    out._C_GuildInfo = fns(C_GuildInfo)
    out._C_Map = fns(C_Map)
    out._C_IncomingSummon = fns(C_IncomingSummon)
    out._C_SummonInfo = fns(C_SummonInfo)
    return out
end

local function probeEvents()
    local out = {}
    local f = CreateFrame("Frame")
    for _, e in ipairs(EVENTS) do
        out[e] = pcall(f.RegisterEvent, f, e) and "ok" or "unknown"
    end
    f:UnregisterAllEvents()
    return out
end

local function probeAddons()
    local out = {}
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    for _, name in ipairs(ADDONS) do out[name] = loaded and tostring(loaded(name)) or "?" end
    return out
end

local function probeGroup()
    local out = {
        channel = tostring(SRT.Compat.GroupChannel()),
        inRaid = try(IsInRaid), inGroup = try(IsInGroup),
        members = try(GetNumGroupMembers),
        leaderOrAssist = SRT.Compat.IsLeaderOrAssist(),
        units = {},
    }
    local units = { "player" }
    for i = 1, 4 do units[#units + 1] = (IsInRaid() and "raid" or "party") .. i end
    for _, unit in ipairs(units) do
        out.units[unit] = {
            name = try(UnitName, unit), full = SRT.Compat.UnitFullName(unit),
            guid = try(UnitGUID, unit), roster = IsInRaid() and try(GetRaidRosterInfo, tonumber(unit:match("%d+")) or 1) or nil,
            position = try(UnitPosition, unit),
            map = C_Map and try(C_Map.GetBestMapForUnit, unit) or nil,
        }
    end
    return out
end

-- Addon messages: whisper ourselves and send to the group, record exactly what arrives.
local function runProbe()
    local key = UnitGUID("player") or SRT.Compat.PlayerName()
    local result = {
        t = time(), version = SRT.version, build = pack(GetBuildInfo()),
        playerName = SRT.Compat.PlayerName(), unitName = try(UnitName, "player"),
        unitFullName = try(UnitFullName, "player"), realm = try(GetNormalizedRealmName),
        apis = probeApis(), events = probeEvents(), addons = probeAddons(), group = probeGroup(),
        comm = { prefixResult = tostring(SRT.Comm.prefixResult), sent = {}, received = {} },
    }
    local comm = result.comm
    SRT.Comm.rawListener = function(text, channel, sender, target)
        comm.received[#comm.received + 1] = pack(text, channel, sender, target)
    end
    local function send(label, channel, target)
        comm.sent[label] = try(C_ChatInfo.SendAddonMessage, SRT.Comm.PREFIX, "probe " .. label, channel, target)
    end
    send("whisperFirst", "WHISPER", (UnitName("player")))
    send("whisperFull", "WHISPER", SRT.Compat.PlayerName())
    if SRT.Compat.GroupChannel() then send("group", SRT.Compat.GroupChannel()) end
    send("guild", "GUILD")
    SRT:Print("Probing for 5 seconds...")
    C_Timer.After(5, function()
        SRT.Comm.rawListener = nil
        SRT.db.probe = SRT.db.probe or {}
        SRT.db.probe[key] = result
        SRT:Print(("Probe saved (%d addon messages received). /reload, then send the SavedVariables file SlaughterRaidTools.lua.")
            :format(#comm.received))
    end)
end

SRT:AddSlashCommand("probe", runProbe, "record what this client supports (then /reload)")
