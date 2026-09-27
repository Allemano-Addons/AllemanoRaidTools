-- Probe (step 0): records what the WoW Forever client really offers for the raid tools
-- SRT will build: which APIs and events exist, how names look and whether addon messages
-- arrive. Saved to SlaughterRaidToolsDB.probe so it can be read from the SavedVariables
-- file after /reload. Never calls protected functions.
local _, SRT = ...

local Probe = {}
SRT.Probe = Probe

-- A value as a string; secret values (WoW Forever in combat) are never touched.
local function str(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

-- Every return value as a string (keeps nils visible, never saves odd types).
local function pack(...)
    local t = { n = select("#", ...) }
    for i = 1, t.n do t[i] = str((select(i, ...))) end
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
    out._C_RestrictedActions = fns(C_RestrictedActions)
    out._C_Secrets = fns(C_Secrets)
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

local probeAuras, groupUnits -- below, with the combat probe

-- Addon messages: whisper ourselves and send to the group, record exactly what arrives.
local function runProbe()
    local key = UnitGUID("player") or SRT.Compat.PlayerName()
    local result = {
        t = time(), version = SRT.version, build = pack(GetBuildInfo()),
        playerName = SRT.Compat.PlayerName(), unitName = try(UnitName, "player"),
        unitFullName = try(UnitFullName, "player"), realm = try(GetNormalizedRealmName),
        apis = probeApis(), events = probeEvents(), addons = probeAddons(), group = probeGroup(),
        comm = { prefixResult = tostring(SRT.Comm.prefixResult), sent = {}, received = {} },
        auras = {},
    }
    for _, unit in ipairs(groupUnits()) do result.auras[unit] = probeAuras(unit, 6) end
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
        result.combat = SRT.db.probe[key] and SRT.db.probe[key].combat -- keep the combat probe
        SRT.db.probe[key] = result
        SRT:Print(("Probe saved (%d addon messages received). /reload, then send the SavedVariables file SlaughterRaidTools.lua.")
            :format(#comm.received))
    end)
end

-- ---------------------------------------------------------------------------
-- Auras: what an addon can read about buffs (consumable check, cooldowns).
-- ---------------------------------------------------------------------------

local AURA_FIELDS = { "name", "spellId", "icon", "duration", "expirationTime", "sourceUnit", "applications", "auraInstanceID" }

function probeAuras(unit, count)
    local out = {}
    local get = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
    if not get then return { missing = true } end
    for i = 1, count do
        local ok, a = pcall(get, unit, i)
        if not ok then out[i] = { err = str(a) } break end
        if a == nil then break end
        if issecretvalue and issecretvalue(a) then out[i] = "<secret table>" break end
        local row = {}
        for _, f in ipairs(AURA_FIELDS) do
            local okField, v = pcall(function() return a[f] end)
            row[f] = okField and str(v) or ("error: " .. str(v))
        end
        out[i] = row
    end
    return out
end

function groupUnits()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, min(5, GetNumGroupMembers()) do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

-- Calls every argument-less Is*/Should*/Get* function of a namespace (all read-only).
local function askNamespace(tbl)
    local out = {}
    if type(tbl) ~= "table" then return { missing = true } end
    for k, v in pairs(tbl) do
        if type(v) == "function" and (k:match("^Is") or k:match("^Should") or k:match("^Get") or k:match("^Are")) then
            out[k] = try(v)
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Combat probe: /srt probe combat arms it; each fight start (and boss pull) records a
-- snapshot two seconds in: are addon messages restricted, are auras, health and
-- cooldowns secret. Saved per character in probe[guid].combat.
-- ---------------------------------------------------------------------------

local MAX_SNAPSHOTS = 6

local function combatData()
    local key = UnitGUID("player") or SRT.Compat.PlayerName()
    SRT.db.probe = SRT.db.probe or {}
    SRT.db.probe[key] = SRT.db.probe[key] or {}
    local p = SRT.db.probe[key]
    p.combat = p.combat or { snapshots = {} }
    return p.combat
end

function Probe.CombatState()
    if not SRT.db then return nil end
    local key = UnitGUID("player") or SRT.Compat.PlayerName()
    local c = SRT.db.probe and SRT.db.probe[key] and SRT.db.probe[key].combat
    if not c then return nil end
    if c.armed then return "armed" end
    return #c.snapshots > 0 and "done" or nil
end

local function snapshot(trigger, extra)
    local c = combatData()
    if not c.armed then return end
    local inst = pack(GetInstanceInfo())
    local s = {
        t = time(), trigger = trigger, extra = extra, inCombat = str(InCombatLockdown()),
        instance = inst, inInstance = try(IsInInstance),
        addonRestricted = C_ChatInfo and try(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) or { missing = true },
        chatLockdown = C_ChatInfo and try(C_ChatInfo.InChatMessagingLockdown) or { missing = true },
        restricted = askNamespace(C_RestrictedActions),
        secrets = askNamespace(C_Secrets),
        health = { player = try(UnitHealth, "player"), target = try(UnitHealth, "target"), targetMax = try(UnitHealthMax, "target") },
        gcd = C_Spell and try(function()
            local cd = C_Spell.GetSpellCooldown(61304)
            return cd and str(cd.startTime), cd and str(cd.duration)
        end) or { missing = true },
        auras = {}, sent = {}, received = {},
    }
    for _, unit in ipairs(groupUnits()) do s.auras[unit] = probeAuras(unit, 3) end
    -- Can we send an addon message right now, and does it arrive?
    SRT.Comm.rawListener = function(text, channel, sender)
        s.received[#s.received + 1] = pack(text, channel, sender)
    end
    local channel = SRT.Compat.GroupChannel()
    if channel then s.sent.group = try(C_ChatInfo.SendAddonMessage, SRT.Comm.PREFIX, "probe combat", channel) end
    s.sent.whisper = try(C_ChatInfo.SendAddonMessage, SRT.Comm.PREFIX, "probe combat", "WHISPER", SRT.Compat.PlayerName())
    C_Timer.After(3, function()
        SRT.Comm.rawListener = nil
        s.receivedCount = #s.received
    end)
    tinsert(c.snapshots, s)
    SRT:Print(("Combat probe: snapshot %d/%d (%s)."):format(#c.snapshots, MAX_SNAPSHOTS, trigger))
    if #c.snapshots >= MAX_SNAPSHOTS then
        c.armed = nil
        SRT:Print("Combat probe done. /reload and send the SavedVariables file SlaughterRaidTools.lua.")
    end
    if SRT.Main then SRT.Main.Refresh() end
end

function Probe.ArmCombat()
    local c = combatData()
    c.armed = true
    c.snapshots = {}
    SRT:Print("Combat probe armed: fight something (a dungeon boss is best). Up to " .. MAX_SNAPSHOTS .. " fights are recorded.")
end

SRT:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if Probe.CombatState() ~= "armed" then return end
    C_Timer.After(2, function() SRT:Call("combat probe", snapshot, "combat") end)
end)
SRT:RegisterEvent("ENCOUNTER_START", function(_, encounterID, name)
    if Probe.CombatState() ~= "armed" then return end
    local extra = str(encounterID) .. " " .. str(name)
    C_Timer.After(2, function() SRT:Call("combat probe", snapshot, "encounter", extra) end)
end)

SRT:AddSlashCommand("probe", function(arg)
    if strlower(arg or "") == "combat" then Probe.ArmCombat() else runProbe() end
end, "record what this client supports (then /reload); /srt probe combat waits for fights")
