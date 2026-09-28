-- Compat: everything that may differ on WoW Forever. Other files go through here
-- instead of calling version-sensitive APIs directly.
local _, SRT = ...

local Compat = {}
SRT.Compat = Compat

function Compat.GetAddOnMetadata(addon, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, field)
    end
    return GetAddOnMetadata(addon, field)
end

function Compat.After(seconds, fn)
    if C_Timer and C_Timer.After then return C_Timer.After(seconds, fn) end
    fn()
end

-- ---------------------------------------------------------------------------
-- Names. On WoW Forever UnitName returns first name and SURNAME separately, and first
-- names are not unique, so a character is always "First Last" (plus "-Realm" from
-- other realms).
-- ---------------------------------------------------------------------------

local function surnameSep()
    return Constants and Constants.CharacterNameSeparatorConsts
        and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

-- Full name of a unit ("First Last"), nil if the unit does not exist.
function Compat.UnitFullName(unit)
    local name, second = UnitName(unit)
    if not name or name == "" then return nil end
    if type(second) == "string" and second ~= "" then
        return name .. surnameSep() .. second
    end
    return name
end

function Compat.PlayerName()
    return Compat.UnitFullName("player") or "Unknown"
end

-- Name without realm, lower case: the key used to compare names from different sources
-- (roster, chat events, addon message senders).
function Compat.NameKey(name)
    if type(name) ~= "string" then return nil end
    return strlower((name:gsub("%-.*$", "")))
end

-- ---------------------------------------------------------------------------
-- Group.
-- ---------------------------------------------------------------------------

local HOME = LE_PARTY_CATEGORY_HOME or 1
local INSTANCE = LE_PARTY_CATEGORY_INSTANCE or 2

-- Addon message channel for the current group, nil when not grouped.
function Compat.GroupChannel()
    if IsInGroup(INSTANCE) and not IsInGroup(HOME) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Group members as a list of { name, unit, online }; the player is included.
function Compat.GroupMembers()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local name = Compat.UnitFullName(unit)
            if name then out[#out + 1] = { name = name, unit = unit, online = UnitIsConnected(unit) and true or false } end
        end
    else
        out[1] = { name = Compat.PlayerName(), unit = "player", online = true }
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            local name = Compat.UnitFullName(unit)
            if name then out[#out + 1] = { name = name, unit = unit, online = UnitIsConnected(unit) and true or false } end
        end
    end
    return out
end

-- Raid leader or assistant (or party leader): allowed to use the leader tools.
function Compat.IsLeaderOrAssist(unit)
    unit = unit or "player"
    if not IsInGroup() then return false end
    if UnitIsGroupLeader(unit) then return true end
    return IsInRaid() and UnitIsGroupAssistant(unit) and true or false
end

-- The group unit of a player name ("First Last", realm ignored), nil if not grouped with us.
function Compat.UnitForName(name)
    local key = Compat.NameKey(name)
    for _, m in ipairs(Compat.GroupMembers()) do
        if Compat.NameKey(m.name) == key then return m.unit end
    end
end

-- Members in the same map as the player (the summon question), and the group size.
function Compat.InZoneCount()
    local members = Compat.GroupMembers()
    local here = C_Map and C_Map.GetBestMapForUnit("player")
    local n = 0
    for _, m in ipairs(members) do
        if m.unit == "player" or (here and m.online and C_Map.GetBestMapForUnit(m.unit) == here) then n = n + 1 end
    end
    return n, #members
end

-- Chat channel for a normal message to the group, nil when not grouped.
function Compat.GroupChatChannel()
    return Compat.GroupChannel()
end

function Compat.SendChat(msg, channel)
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    return pcall(send, msg, channel)
end

-- Blizzard's ready check and pull countdown (C_PartyInfo on Forever). Return false when
-- the client lacks them or refuses the call.
function Compat.DoReadyCheck()
    local fn = C_PartyInfo and C_PartyInfo.DoReadyCheck or DoReadyCheck
    if not fn then return false end
    return (pcall(fn))
end

function Compat.DoCountdown(seconds)
    local fn = C_PartyInfo and C_PartyInfo.DoCountdown
    if not fn then return false end
    return (pcall(fn, seconds))
end

-- Group management (C_PartyInfo on Forever; the old globals are missing there). Each
-- returns false when the client lacks the call or refuses it.
local function call(ns, name, ...)
    local fn = (C_PartyInfo and C_PartyInfo[name]) or (ns and _G[name])
    if not fn then return false end
    return (pcall(fn, ...))
end

function Compat.InviteUnit(name) return call(true, "InviteUnit", name) end
function Compat.ConvertToRaid() return call(true, "ConvertToRaid") end
function Compat.PromoteToAssistant(unit) return call(true, "PromoteToAssistant", unit) end

function Compat.SetRaidSubgroup(index, group)
    if not SetRaidSubgroup then return false end
    return (pcall(SetRaidSubgroup, index, group))
end

function Compat.SwapRaidSubgroup(a, b)
    if not SwapRaidSubgroup then return false end
    return (pcall(SwapRaidSubgroup, a, b))
end

-- Raid members with their raid index and subgroup: { { index, unit, name, group, online } }.
function Compat.RaidRoster()
    local out = {}
    if not IsInRaid() then return out end
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local _, _, group, _, _, _, _, online = GetRaidRosterInfo(i)
        local name = Compat.UnitFullName(unit)
        if name then
            out[#out + 1] = { index = i, unit = unit, name = name, group = group or 1, online = online and true or false }
        end
    end
    return out
end

-- Everyone in the group, party or raid: like RaidRoster, but in a party everyone is in
-- group 1 and has no raid index (they cannot be moved).
function Compat.GroupRoster()
    if IsInRaid() then return Compat.RaidRoster() end
    local out = {}
    for _, m in ipairs(Compat.GroupMembers()) do
        out[#out + 1] = { unit = m.unit, name = m.name, group = 1, online = m.online }
    end
    return out
end

-- Guild members: { { name, rank, rankIndex, level, online, classFile } }. Ask the server
-- for a fresh list with Compat.RequestGuildRoster (GUILD_ROSTER_UPDATE answers).
function Compat.GuildRoster()
    local out = {}
    if not IsInGuild() then return out end
    for i = 1, GetNumGuildMembers() do
        local name, rank, rankIndex, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            out[#out + 1] = { name = name, rank = rank, rankIndex = rankIndex, level = level, online = online and true or false, classFile = classFile }
        end
    end
    return out
end

function Compat.RequestGuildRoster()
    local fn = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
    if fn then pcall(fn) end
end

function Compat.GuildName()
    return IsInGuild() and GetGuildInfo("player") or nil
end
