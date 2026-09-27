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

function Compat.GuildName()
    return IsInGuild() and GetGuildInfo("player") or nil
end
