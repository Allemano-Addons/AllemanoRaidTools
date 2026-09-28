-- Invites & groups: an invite queue (guild ranks, keyword whispers, the roster), automatic
-- convert to raid and assist, and sorting the raid's groups from an OXM roster export.
local _, ART = ...

local Invites = {}
ART.Invites = Invites

local INVITE_GAP = 0.2       -- seconds between two invites
local INVITE_TIMEOUT = 90    -- an unanswered invite stops holding a party slot
local SORT_GAP = 0.3         -- seconds between two group moves
local SORT_MAX_STEPS = 80

local listeners = {}
function Invites.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do ART:Call("invites listener", fn) end
end

local function settings() return ART.db.invite end

-- First-name key: rosters and exports often carry only the first name on Forever.
local function firstKey(name)
    return strlower(((name or ""):gsub("%-.*$", "")):match("^(%S+)") or "")
end
Invites.firstKey = firstKey

local function inGroup(name)
    return ART.Compat.UnitForName(name) ~= nil
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
        ART:Call("invite queue", process)
    end)
end

function process()
    if #queue == 0 then return end
    if IsInGroup() and not ART.Compat.IsLeaderOrAssist() then
        ART:Print("Invites stopped: you are no longer leader or assistant.")
        wipe(queue)
        changed()
        return
    end
    if not IsInRaid() then
        local members = max(1, GetNumGroupMembers())
        if members + outstandingCount() >= 5 then
            -- The party is full (or will be): convert once someone has accepted.
            if IsInGroup() and settings().autoConvert then
                ART.Compat.ConvertToRaid()
                schedule(1)
            elseif IsInGroup() and not settings().autoConvert and members >= 5 then
                ART:Print(("The party is full: convert to a raid to invite the other %d."):format(#queue))
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
        if ART.Compat.InviteUnit(name) then
            outstanding[ART.Compat.NameKey(name)] = GetTime()
        else
            ART:Print("The game refused the invite for " .. name .. ".")
        end
    end
    changed()
    if #queue > 0 then schedule() end
end

-- Adds names (full names) to the queue; skips the player, members and duplicates.
function Invites.Queue(names)
    local me = ART.Compat.NameKey(ART.Compat.PlayerName())
    local added = 0
    for _, name in ipairs(names) do
        local key = ART.Compat.NameKey(name)
        local dup = key == me or inGroup(name)
        for _, q in ipairs(queue) do if ART.Compat.NameKey(q) == key then dup = true end end
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
    return not IsInGroup() or ART.Compat.IsLeaderOrAssist()
end

-- ---------------------------------------------------------------------------
-- Guild
-- ---------------------------------------------------------------------------

-- { { index, name } } of the guild's ranks, from the roster.
function Invites.GuildRanks()
    local seen, out = {}, {}
    for _, m in ipairs(ART.Compat.GuildRoster()) do
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
    local me = ART.Compat.NameKey(ART.Compat.PlayerName())
    for _, m in ipairs(ART.Compat.GuildRoster()) do
        if m.online and ranks[m.rankIndex] and ART.Compat.NameKey(m.name) ~= me and not inGroup(m.name) then
            out[#out + 1] = m.name
        end
    end
    return out
end

function Invites.InviteRanks()
    if not Invites.CanInvite() then ART:Print("Only the raid leader or an assistant can invite.") return end
    local names = Invites.RankCandidates()
    local n = Invites.Queue(names)
    ART:Print(("Inviting %d guild member%s."):format(n, n == 1 and "" or "s"))
end

local function guildMember(name)
    local key = ART.Compat.NameKey(name)
    for _, m in ipairs(ART.Compat.GuildRoster()) do
        if ART.Compat.NameKey(m.name) == key then return m end
    end
end

-- ---------------------------------------------------------------------------
-- Keyword whispers, auto convert, auto assist
-- ---------------------------------------------------------------------------

ART:RegisterEvent("CHAT_MSG_WHISPER", function(_, text, sender)
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
    for _, m in ipairs(ART.Compat.RaidRoster()) do
        local key = ART.Compat.NameKey(m.name)
        if (keys[key] or keys[firstKey(m.name)]) and not promoted[key] and not UnitIsGroupAssistant(m.unit) then
            promoted[key] = true
            ART.Compat.PromoteToAssistant(m.unit)
        end
    end
end

ART:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    for key in pairs(outstanding) do
        if ART.Compat.UnitForName(key) then outstanding[key] = nil end
    end
    if not IsInGroup() then wipe(promoted) end
    autoAssist()
    if #queue > 0 then schedule(0.5) end
    changed()
end)
ART:RegisterEvent("GUILD_ROSTER_UPDATE", changed)

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
    Invites.SetRosterText(table.concat(out, "\n"))
end

-- ---------------------------------------------------------------------------
-- Roster profiles (like MRT): several saved rosters by name. db.roster.text is the one
-- being worked on; every change is also saved in the current profile.
-- ---------------------------------------------------------------------------

function Invites.SetRosterText(text)
    local r = ART.db.roster
    r.text = text or ""
    r.profiles[r.current] = r.text
end

function Invites.Profiles()
    local out = {}
    for name in pairs(ART.db.roster.profiles) do out[#out + 1] = name end
    sort(out)
    return out
end

function Invites.CurrentProfile() return ART.db.roster.current end

function Invites.SelectProfile(name)
    local r = ART.db.roster
    if not r.profiles[name] then return false end
    r.current, r.text = name, r.profiles[name]
    changed()
    return true
end

-- A new, empty roster with this name (or the existing one), switched to. New first, then
-- paste: pasting first would overwrite the roster you were in (everything saves itself).
function Invites.NewProfile(name)
    name = strtrim(name or "")
    if name == "" then return false end
    local r = ART.db.roster
    r.profiles[name] = r.profiles[name] or ""
    r.current, r.text = name, r.profiles[name]
    changed()
    return true
end

-- Deletes a profile; the last one left is kept (emptied) so there is always one.
function Invites.DeleteProfile(name)
    local r = ART.db.roster
    if not r.profiles[name] then return false end
    r.profiles[name] = nil
    if not next(r.profiles) then r.profiles.Default = "" end
    if r.current == name then
        local first = Invites.Profiles()[1]
        r.current, r.text = first, r.profiles[first]
    end
    changed()
    return true
end

-- Drag and drop only changes the plan; "Apply groups" (Invites.Sort) moves the raid.
-- Move place `from` into group g (first empty place there), or swap two places. Returns
-- false and a reason when the group is full.
local function firstFree(lines, g)
    for i = #lines + 1, g * 5 do lines[i] = "-" end
    for pos = (g - 1) * 5 + 1, g * 5 do
        if lines[pos] == "-" then return pos end
    end
end

function Invites.MoveToGroup(from, g)
    local lines = Invites.RosterLines(ART.db.roster.text)
    if not lines[from] or lines[from] == "-" then return false end
    if floor((from - 1) / 5) + 1 == g then return true end
    local pos = firstFree(lines, g)
    if not pos then return false, ("Group %d is full: drop on a player to swap."):format(g) end
    lines[pos], lines[from] = lines[from], "-"
    Invites.SetRosterLines(lines)
    changed()
    return true
end

function Invites.SwapPlaces(a, b)
    local lines = Invites.RosterLines(ART.db.roster.text)
    if a == b or not lines[a] then return false end
    for i = #lines + 1, b do lines[i] = "-" end
    lines[a], lines[b] = lines[b], lines[a]
    Invites.SetRosterLines(lines)
    changed()
    return true
end

-- A group member who is not on the roster, dropped into group g: at place `pos` when it
-- is empty, otherwise the group's first free place.
function Invites.AddToGroup(name, g, pos)
    local lines = Invites.RosterLines(ART.db.roster.text)
    if pos and pos <= 40 and floor((pos - 1) / 5) + 1 == g then
        for i = #lines + 1, pos do lines[i] = "-" end
        if lines[pos] ~= "-" then pos = nil end
    else
        pos = nil
    end
    pos = pos or firstFree(lines, g)
    if not pos then return false, ("Group %d is full."):format(g) end
    lines[pos] = name
    Invites.SetRosterLines(lines)
    changed()
    return true
end

-- Takes a place off the roster (dragged to "not on the roster").
function Invites.RemovePlace(pos)
    local lines = Invites.RosterLines(ART.db.roster.text)
    if not lines[pos] then return false end
    lines[pos] = "-"
    Invites.SetRosterLines(lines)
    changed()
    return true
end

-- Keys a raid member can be found by: full name and first name. A first name shared
-- by two members is ambiguous.
local function indexMembers(members)
    local byKey, count = {}, {}
    for _, m in ipairs(members) do
        local full, first = ART.Compat.NameKey(m.name), firstKey(m.name)
        byKey[full] = m
        count[first] = (count[first] or 0) + 1
        byKey[first] = m
    end
    return function(name)
        local key = ART.Compat.NameKey(name)
        if name:find(" ", 1, true) then return byKey[key] end
        local first = firstKey(name)
        if (count[first] or 0) > 1 then return nil, "ambiguous" end
        return byKey[first]
    end
end

-- Each slot gets .member (group member, party or raid), .state ("raid" = in the group,
-- "ambiguous", "guild" online in the guild, "offline", "unknown", "empty"), .name (the
-- name that matched or the first) and .classFile when known. You are never matched
-- against the guild list, so an alt with your first name does not make yours ambiguous.
-- Also returns the group members who are not on the roster.
function Invites.MatchRoster(slots)
    local members = ART.Compat.GroupRoster()
    local find = indexMembers(members)
    local me = ART.Compat.NameKey(ART.Compat.PlayerName())
    local guild = {}
    for _, g in ipairs(ART.Compat.GuildRoster()) do
        if ART.Compat.NameKey(g.name) ~= me then guild[#guild + 1] = g end
    end
    local used = {}
    for _, slot in ipairs(slots) do
        slot.member, slot.state, slot.name, slot.guildName, slot.classFile = nil, slot.empty and "empty" or "unknown", slot.names[1], nil, nil
        for _, n in ipairs(slot.state == "unknown" and slot.names or {}) do
            local m, why = find(n)
            if m and not used[m.unit] then
                used[m.unit] = true
                slot.member, slot.state, slot.name = m, "raid", n
                slot.classFile = select(2, UnitClass(m.unit))
                break
            elseif why == "ambiguous" then
                slot.state, slot.name = "ambiguous", n
            end
        end
        if slot.state == "unknown" then
            -- Not in the raid: can we invite one of them from the guild?
            for _, n in ipairs(slot.names) do
                local key, first = ART.Compat.NameKey(n), firstKey(n)
                local online, offline, hits = nil, nil, 0
                for _, g in ipairs(guild) do
                    local match
                    if n:find(" ", 1, true) then match = ART.Compat.NameKey(g.name) == key else match = firstKey(g.name) == first end
                    if match then
                        hits = hits + 1
                        if g.online then online = g else offline = g end
                    end
                end
                if online and hits == 1 then
                    slot.state, slot.name, slot.guildName, slot.classFile = "guild", n, online.name, online.classFile
                    break
                elseif hits > 1 and online then
                    slot.state, slot.name = "ambiguous", n
                    break
                elseif offline then
                    slot.state, slot.name = "offline", n
                    if hits == 1 then slot.classFile = offline.classFile end
                end
            end
        end
    end
    local others = {}
    for _, m in ipairs(members) do
        if not used[m.unit] then
            others[#others + 1] = { name = m.name, unit = m.unit, classFile = select(2, UnitClass(m.unit)) }
        end
    end
    return slots, others
end

function Invites.Roster()
    return Invites.MatchRoster(Invites.ParseRoster(ART.db.roster.text))
end

-- Invites everyone on the roster who is online in the guild and not in the group, and
-- announces it (settings: announce = "GUILD", "OFFICER" or "OFF", announceText).
function Invites.InviteRoster()
    if not Invites.CanInvite() then ART:Print("Only the raid leader or an assistant can invite.") return end
    local names = {}
    for _, slot in ipairs((Invites.Roster())) do
        if slot.state == "guild" then names[#names + 1] = slot.guildName end
    end
    local n = Invites.Queue(names)
    ART:Print(("Inviting %d player%s from the roster."):format(n, n == 1 and "" or "s"))
    local s = settings()
    if n > 0 and s.announce ~= "OFF" and IsInGuild() then
        local text = strtrim(s.announceText or "")
        if text ~= "" then ART.Compat.SendChat(text, s.announce) end
    end
end
Invites.InviteRosterMissing = Invites.InviteRoster

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

-- "Apply groups": moves players until the raid matches the roster.
function Invites.Sort()
    if sorting then return end
    if not IsInRaid() then ART:Print("Applying groups needs a raid (convert the party first).") return end
    if not ART.Compat.IsLeaderOrAssist() then ART:Print("Only the raid leader or an assistant can move players.") return end
    if InCombatLockdown() then ART:Print("Groups cannot be changed in combat.") return end
    sorting = true
    local steps = 0
    local function step()
        local slots = Invites.Roster()
        local desired = {}
        for _, slot in ipairs(slots) do
            if slot.member then desired[slot.member.index] = slot.group end
        end
        local kind, a, b = Invites.NextMove(ART.Compat.RaidRoster(), desired)
        if not kind or steps >= SORT_MAX_STEPS or InCombatLockdown() then
            sorting = false
            changed()
            if kind then
                ART:Print("Applying groups stopped before it was done (combat or too many moves). Try again.")
            else
                ART:Print("Groups applied.")
            end
            return
        end
        steps = steps + 1
        local ok
        if kind == "set" then ok = ART.Compat.SetRaidSubgroup(a, b) else ok = ART.Compat.SwapRaidSubgroup(a, b) end
        if not ok then
            sorting = false
            changed()
            ART:Print("The game refused to move players.")
            return
        end
        C_Timer.After(SORT_GAP, function() ART:Call("sort groups", step) end)
    end
    changed()
    step()
end

ART:AddSlashCommand("inv", function(arg)
    if arg ~= "" then
        Invites.Queue({ arg })
    else
        Invites.InviteRanks()
    end
end, "invite the selected guild ranks (/art inv Name invites one player)")
ART:AddSlashCommand("apply", function() Invites.Sort() end, "move the raid into the roster's groups")
ART:AddSlashCommand("invroster", function() Invites.InviteRoster() end, "invite everyone on the roster (and announce it)")
