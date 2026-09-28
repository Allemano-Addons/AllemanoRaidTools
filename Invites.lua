-- Invites & groups: an invite queue (guild ranks, keyword whispers, the roster), automatic
-- convert to raid and assist, and sorting the raid's groups from an OXM roster export.
local _, SRT = ...

local Invites = {}
SRT.Invites = Invites

local INVITE_GAP = 0.2       -- seconds between two invites
local INVITE_TIMEOUT = 90    -- an unanswered invite stops holding a party slot
local SORT_GAP = 0.3         -- seconds between two group moves
local SORT_MAX_STEPS = 80

local listeners = {}
function Invites.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do SRT:Call("invites listener", fn) end
end

local function settings() return SRT.db.invite end

-- First-name key: rosters and exports often carry only the first name on Forever.
local function firstKey(name)
    return strlower(((name or ""):gsub("%-.*$", "")):match("^(%S+)") or "")
end
Invites.firstKey = firstKey

local function inGroup(name)
    return SRT.Compat.UnitForName(name) ~= nil
end

-- ---------------------------------------------------------------------------
-- Invite queue
-- ---------------------------------------------------------------------------

local queue = {}        -- names waiting to be invited
local outstanding = {}  -- [nameKey] = GetTime() of an invite not answered yet
local busy = false

function Invites.Pending() return #queue end

local function outstandingCount()
    local now, n = GetTime(), 0
    for key, t in pairs(outstanding) do
        if now - t > INVITE_TIMEOUT then outstanding[key] = nil else n = n + 1 end
    end
    return n
end

local process
local function schedule(delay)
    if busy then return end
    busy = true
    C_Timer.After(delay or INVITE_GAP, function()
        busy = false
        SRT:Call("invite queue", process)
    end)
end

function process()
    if #queue == 0 then return end
    if IsInGroup() and not SRT.Compat.IsLeaderOrAssist() then
        SRT:Print("Invites stopped: you are no longer leader or assistant.")
        wipe(queue)
        changed()
        return
    end
    if not IsInRaid() then
        local members = max(1, GetNumGroupMembers())
        if members + outstandingCount() >= 5 then
            -- The party is full (or will be): convert once someone has accepted.
            if IsInGroup() and settings().autoConvert then
                SRT.Compat.ConvertToRaid()
                schedule(1)
            elseif IsInGroup() and not settings().autoConvert and members >= 5 then
                SRT:Print(("The party is full: convert to a raid to invite the other %d."):format(#queue))
                wipe(queue)
                changed()
            else
                schedule(3) -- waiting for answers (or for unanswered invites to time out)
            end
            return
        end
    end
    local name = tremove(queue, 1)
    if not inGroup(name) then
        if SRT.Compat.InviteUnit(name) then
            outstanding[SRT.Compat.NameKey(name)] = GetTime()
        else
            SRT:Print("The game refused the invite for " .. name .. ".")
        end
    end
    changed()
    if #queue > 0 then schedule() end
end

-- Adds names (full names) to the queue; skips the player, members and duplicates.
function Invites.Queue(names)
    local me = SRT.Compat.NameKey(SRT.Compat.PlayerName())
    local added = 0
    for _, name in ipairs(names) do
        local key = SRT.Compat.NameKey(name)
        local dup = key == me or inGroup(name)
        for _, q in ipairs(queue) do if SRT.Compat.NameKey(q) == key then dup = true end end
        if not dup then
            queue[#queue + 1] = name
            added = added + 1
        end
    end
    changed()
    if added > 0 then schedule(0) end
    return added
end

function Invites.CanInvite()
    return not IsInGroup() or SRT.Compat.IsLeaderOrAssist()
end

-- ---------------------------------------------------------------------------
-- Guild
-- ---------------------------------------------------------------------------

-- { { index, name } } of the guild's ranks, from the roster.
function Invites.GuildRanks()
    local seen, out = {}, {}
    for _, m in ipairs(SRT.Compat.GuildRoster()) do
        if m.rankIndex and not seen[m.rankIndex] then
            seen[m.rankIndex] = true
            out[#out + 1] = { index = m.rankIndex, name = m.rank }
        end
    end
    sort(out, function(a, b) return a.index < b.index end)
    return out
end

-- Online guild members in the selected ranks who are not in the group.
function Invites.RankCandidates()
    local ranks, out = settings().ranks, {}
    local me = SRT.Compat.NameKey(SRT.Compat.PlayerName())
    for _, m in ipairs(SRT.Compat.GuildRoster()) do
        if m.online and ranks[m.rankIndex] and SRT.Compat.NameKey(m.name) ~= me and not inGroup(m.name) then
            out[#out + 1] = m.name
        end
    end
    return out
end

function Invites.InviteRanks()
    if not Invites.CanInvite() then SRT:Print("Only the raid leader or an assistant can invite.") return end
    local names = Invites.RankCandidates()
    local n = Invites.Queue(names)
    SRT:Print(("Inviting %d guild member%s."):format(n, n == 1 and "" or "s"))
end

local function guildMember(name)
    local key = SRT.Compat.NameKey(name)
    for _, m in ipairs(SRT.Compat.GuildRoster()) do
        if SRT.Compat.NameKey(m.name) == key then return m end
    end
end

-- ---------------------------------------------------------------------------
-- Keyword whispers, auto convert, auto assist
-- ---------------------------------------------------------------------------

SRT:RegisterEvent("CHAT_MSG_WHISPER", function(_, text, sender)
    local s = settings()
    if not s.keywordOn or not sender then return end
    if strlower(strtrim(text or "")) ~= strlower(strtrim(s.keyword or "")) then return end
    if not Invites.CanInvite() then return end
    if s.guildOnly and not guildMember(sender) then return end
    Invites.Queue({ sender })
end)

-- Names from the auto-assist list, as keys (first name or full name).
local function assistKeys()
    local keys = {}
    for entry in (settings().assists or ""):gmatch("[^,]+") do
        entry = strlower(strtrim(entry))
        if entry ~= "" then keys[entry] = true end
    end
    return keys
end

local promoted = {} -- [nameKey] = true: asked once per session
local function autoAssist()
    if not IsInRaid() or not UnitIsGroupLeader("player") then return end
    local keys = assistKeys()
    if not next(keys) then return end
    for _, m in ipairs(SRT.Compat.RaidRoster()) do
        local key = SRT.Compat.NameKey(m.name)
        if (keys[key] or keys[firstKey(m.name)]) and not promoted[key] and not UnitIsGroupAssistant(m.unit) then
            promoted[key] = true
            SRT.Compat.PromoteToAssistant(m.unit)
        end
    end
end

SRT:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    for key in pairs(outstanding) do
        if SRT.Compat.UnitForName(key) then outstanding[key] = nil end
    end
    if not IsInGroup() then wipe(promoted) end
    autoAssist()
    if #queue > 0 then schedule(0.5) end
    changed()
end)
SRT:RegisterEvent("GUILD_ROSTER_UPDATE", changed)

-- ---------------------------------------------------------------------------
-- Roster (OXM export): names top to bottom, five per group, blank lines ignored.
-- "Name/Other" = either of them.
-- ---------------------------------------------------------------------------

-- { { group, names = { "Name", "Other" } } } in order; at most 40 slots (8 groups).
-- A line "-" is an empty place (written by drag and drop, so a group can have gaps).
function Invites.ParseRoster(text)
    local slots = {}
    for _, line in ipairs(Invites.RosterLines(text)) do
        local names = {}
        for n in line:gmatch("[^/]+") do
            n = strtrim(n)
            if n ~= "" and n ~= "-" then names[#names + 1] = n end
        end
        slots[#slots + 1] = { group = floor(#slots / 5) + 1, names = names, pos = #slots + 1, empty = names[1] == nil or nil }
    end
    return slots
end

-- The roster's places in order (blank lines dropped, at most 40): "Name", "A/B" or "-".
function Invites.RosterLines(text)
    local lines = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        line = strtrim(line)
        if line ~= "" and #lines < 40 then lines[#lines + 1] = line end
    end
    return lines
end

-- Writes places back as text, a blank line after every 10 like the OXM export; empty
-- places at the end are dropped.
function Invites.SetRosterLines(lines)
    while lines[#lines] == "-" do lines[#lines] = nil end
    local out = {}
    for i, line in ipairs(lines) do
        out[#out + 1] = line
        if i % 10 == 0 and i < #lines then out[#out + 1] = "" end
    end
    SRT.db.roster.text = table.concat(out, "\n")
end

-- Drag and drop: move place `from` into group g (first empty place there), or swap two
-- places. Returns false and a reason when the group is full. The dragged players are
-- also moved in the raid when possible (see Invites.MoveLive).
function Invites.MoveToGroup(from, g)
    local lines = Invites.RosterLines(SRT.db.roster.text)
    if not lines[from] or lines[from] == "-" then return false end
    if floor((from - 1) / 5) + 1 == g then return true end
    for i = #lines + 1, g * 5 do lines[i] = "-" end
    for pos = (g - 1) * 5 + 1, g * 5 do
        if lines[pos] == "-" then
            lines[pos], lines[from] = lines[from], "-"
            Invites.SetRosterLines(lines)
            Invites.MoveLive({ pos })
            changed()
            return true
        end
    end
    return false, ("Group %d is full: drop on a player to swap."):format(g)
end

function Invites.SwapPlaces(a, b)
    local lines = Invites.RosterLines(SRT.db.roster.text)
    if a == b or not lines[a] then return false end
    for i = #lines + 1, b do lines[i] = "-" end
    lines[a], lines[b] = lines[b], lines[a]
    Invites.SetRosterLines(lines)
    Invites.MoveLive({ a, b })
    changed()
    return true
end

-- Keys a raid member can be found by: full name and first name. A first name shared
-- by two members is ambiguous.
local function indexMembers(members)
    local byKey, count = {}, {}
    for _, m in ipairs(members) do
        local full, first = SRT.Compat.NameKey(m.name), firstKey(m.name)
        byKey[full] = m
        count[first] = (count[first] or 0) + 1
        byKey[first] = m
    end
    return function(name)
        local key = SRT.Compat.NameKey(name)
        if name:find(" ", 1, true) then return byKey[key] end
        local first = firstKey(name)
        if (count[first] or 0) > 1 then return nil, "ambiguous" end
        return byKey[first]
    end
end

-- Each slot gets .member (raid member), .state ("raid", "self" = you while not in a raid,
-- "ambiguous", "guild" online in the guild, "offline", "unknown", "empty") and .name (the
-- name that matched or the first). You are never matched against the guild list, so an
-- alt with your first name does not make your name ambiguous.
function Invites.MatchRoster(slots)
    local find = indexMembers(SRT.Compat.RaidRoster())
    local me = SRT.Compat.NameKey(SRT.Compat.PlayerName())
    local guild = {}
    for _, g in ipairs(SRT.Compat.GuildRoster()) do
        if SRT.Compat.NameKey(g.name) ~= me then guild[#guild + 1] = g end
    end
    local function isMe(n)
        if n:find(" ", 1, true) then return SRT.Compat.NameKey(n) == me end
        return firstKey(n) == firstKey(me)
    end
    local used = {}
    for _, slot in ipairs(slots) do
        slot.member, slot.state, slot.name, slot.guildName = nil, slot.empty and "empty" or "unknown", slot.names[1], nil
        if not IsInRaid() then
            for _, n in ipairs(slot.names) do
                if isMe(n) then slot.state, slot.name = "self", n break end
            end
        end
        for _, n in ipairs(slot.state == "unknown" and slot.names or {}) do
            local m, why = find(n)
            if m and not used[m.index] then
                used[m.index] = true
                slot.member, slot.state, slot.name = m, "raid", n
                break
            elseif why == "ambiguous" then
                slot.state, slot.name = "ambiguous", n
            end
        end
        if slot.state == "unknown" then
            -- Not in the raid: can we invite one of them from the guild?
            for _, n in ipairs(slot.names) do
                local key, first = SRT.Compat.NameKey(n), firstKey(n)
                local online, offline, hits = nil, nil, 0
                for _, g in ipairs(guild) do
                    local match
                    if n:find(" ", 1, true) then match = SRT.Compat.NameKey(g.name) == key else match = firstKey(g.name) == first end
                    if match then
                        hits = hits + 1
                        if g.online then online = g else offline = g end
                    end
                end
                if online and hits == 1 then
                    slot.state, slot.name, slot.guildName = "guild", n, online.name
                    break
                elseif hits > 1 and online then
                    slot.state, slot.name = "ambiguous", n
                    break
                elseif offline then
                    slot.state, slot.name = "offline", n
                end
            end
        end
    end
    return slots
end

function Invites.Roster()
    return Invites.MatchRoster(Invites.ParseRoster(SRT.db.roster.text))
end

function Invites.InviteRosterMissing()
    if not Invites.CanInvite() then SRT:Print("Only the raid leader or an assistant can invite.") return end
    local names = {}
    for _, slot in ipairs(Invites.Roster()) do
        if slot.state == "guild" then names[#names + 1] = slot.guildName end
    end
    local n = Invites.Queue(names)
    SRT:Print(("Inviting %d player%s from the roster."):format(n, n == 1 and "" or "s"))
end

-- ---------------------------------------------------------------------------
-- Sorting: one move at a time (the raid list changes after each), every move places at
-- least one player in their roster group for good, so it always ends.
-- ---------------------------------------------------------------------------

-- The next (kind, a, b) move, or nil when everyone listed is in their group.
function Invites.NextMove(members, desired)
    local count = {}
    for _, m in ipairs(members) do count[m.group] = (count[m.group] or 0) + 1 end
    for _, m in ipairs(members) do
        local d = desired[m.index]
        if d and m.group ~= d then
            if (count[d] or 0) < 5 then return "set", m.index, d end
            for _, o in ipairs(members) do
                if o.group == d and desired[o.index] ~= d then return "swap", m.index, o.index end
            end
        end
    end
end

local sorting = false
function Invites.IsSorting() return sorting end

-- Runs moves until the raid matches the roster. only = set of roster places to place
-- (drag and drop), nil = everyone on the roster. quiet = no "Groups sorted." line.
local function runSort(only, quiet)
    if sorting then return end
    sorting = true
    local steps = 0
    local function step()
        local slots = Invites.Roster()
        local desired = {}
        for _, slot in ipairs(slots) do
            if slot.member and (not only or only[slot.pos]) then desired[slot.member.index] = slot.group end
        end
        local kind, a, b = Invites.NextMove(SRT.Compat.RaidRoster(), desired)
        if not kind or steps >= SORT_MAX_STEPS or InCombatLockdown() then
            sorting = false
            changed()
            if kind then
                SRT:Print("Sorting stopped before it was done (combat or too many moves). Try again.")
            elseif not quiet then
                SRT:Print("Groups sorted.")
            end
            return
        end
        steps = steps + 1
        local ok
        if kind == "set" then ok = SRT.Compat.SetRaidSubgroup(a, b) else ok = SRT.Compat.SwapRaidSubgroup(a, b) end
        if not ok then
            sorting = false
            changed()
            SRT:Print("The game refused to move players.")
            return
        end
        C_Timer.After(SORT_GAP, function() SRT:Call("sort groups", step) end)
    end
    changed()
    step()
end

function Invites.Sort()
    if sorting then return end
    if not IsInRaid() then SRT:Print("Sorting needs a raid.") return end
    if not SRT.Compat.IsLeaderOrAssist() then SRT:Print("Only the raid leader or an assistant can move players.") return end
    if InCombatLockdown() then SRT:Print("Groups cannot be changed in combat.") return end
    runSort(nil, false)
end

-- After a drag and drop: move just those players in the raid, when we are allowed to.
-- The roster change stands either way.
function Invites.MoveLive(places)
    if not IsInRaid() or not SRT.Compat.IsLeaderOrAssist() or InCombatLockdown() then return end
    local only = {}
    for _, p in ipairs(places) do only[p] = true end
    runSort(only, true)
end

SRT:AddSlashCommand("inv", function(arg)
    if arg ~= "" then
        Invites.Queue({ arg })
    else
        Invites.InviteRanks()
    end
end, "invite the selected guild ranks (/srt inv Name invites one player)")
SRT:AddSlashCommand("sort", function() Invites.Sort() end, "sort the raid's groups from the roster")
