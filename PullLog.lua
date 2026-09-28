-- Pull log: every boss pull (ENCOUNTER_START / ENCOUNTER_END) with the boss, combat time,
-- kill or wipe, and the boss's health when it ended. Pulls are grouped by raid night
-- (a night runs until 06:00 the next morning).
local _, SRT = ...

local PullLog = {}
SRT.PullLog = PullLog

local MAX_PULLS = 500
local NIGHT_SHIFT = 6 * 3600 -- 01:30 still belongs to the evening before

local listeners = {}
function PullLog.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do SRT:Call("pull log listener", fn) end
end

local function db() return SRT.db.pulls end

function PullLog.NightOf(t) return date("%Y-%m-%d", (t or time()) - NIGHT_SHIFT) end

-- ---------------------------------------------------------------------------
-- Boss health: read all through the fight (the game may hide it in combat: then the
-- last value it did show is kept).
-- ---------------------------------------------------------------------------

local function safe(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Health % of the main boss (boss1, else the first boss unit), nil when unknown.
function PullLog.BossPercent()
    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) then
            local okH, hp = pcall(UnitHealth, unit)
            local okM, maxHp = pcall(UnitHealthMax, unit)
            hp, maxHp = okH and safe(hp), okM and safe(maxHp)
            if hp and maxHp and maxHp > 0 then return hp / maxHp * 100 end
            -- Retail-style clients: a 0-1 fraction when the raw numbers are hidden.
            if UnitHealthPercent then
                local ok, p = pcall(UnitHealthPercent, unit)
                p = ok and safe(p)
                if type(p) == "number" then return p <= 1 and p * 100 or p end
            end
            return nil
        end
    end
end

local current -- the pull in progress: { encounterID, name, difficulty, size, startTime, start, pct }
local ticker

-- The lowest health seen: after a wipe the boss resets (heals to full) before the
-- encounter officially ends, so the last reading would say 100%.
local function sample()
    if not current then return end
    local p = PullLog.BossPercent()
    if p and (not current.pct or p < current.pct) then current.pct = p end
end

function PullLog.Current() return current end

SRT:RegisterEvent("ENCOUNTER_START", function(_, encounterID, name, difficultyID, groupSize)
    current = {
        encounterID = safe(encounterID), name = safe(name) or "Unknown boss", difficulty = safe(difficultyID),
        size = safe(groupSize), startTime = GetTime(), start = time(), zone = GetInstanceInfo(),
    }
    sample()
    if not ticker then ticker = C_Timer.NewTicker(1, function() SRT:Call("pull log", sample) end) end
    changed()
end)

SRT:RegisterEvent("UNIT_HEALTH", function(_, unit)
    if current and unit == "boss1" then sample() end
end)

SRT:RegisterEvent("ENCOUNTER_END", function(_, encounterID, name, difficultyID, groupSize, success)
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    local pull = current
    current = nil
    if not pull then
        -- Started before a /reload: we only know how it ended.
        pull = { encounterID = safe(encounterID), name = safe(name) or "Unknown boss", difficulty = safe(difficultyID),
            size = safe(groupSize), start = time(), zone = GetInstanceInfo() }
    end
    local kill = safe(success) == 1 or safe(success) == true
    local entry = {
        t = pull.start, night = PullLog.NightOf(pull.start), boss = pull.name, id = pull.encounterID,
        zone = pull.zone, difficulty = pull.difficulty, size = pull.size, kill = kill,
        duration = pull.startTime and floor(GetTime() - pull.startTime + 0.5) or nil,
        pct = (not kill and pull.pct) and floor(pull.pct * 10 + 0.5) / 10 or nil,
    }
    local list = db()
    list[#list + 1] = entry
    while #list > MAX_PULLS do tremove(list, 1) end
    changed()
    local result = kill and "Kill" or ("Wipe" .. (entry.pct and (" at %.1f%%"):format(entry.pct) or ""))
    SRT:Print(("%s #%d: %s after %s."):format(entry.boss, PullLog.PullNumber(entry), result, PullLog.FormatTime(entry.duration)))
end)

-- ---------------------------------------------------------------------------
-- Reading the log
-- ---------------------------------------------------------------------------

function PullLog.FormatTime(s)
    if not s then return "?" end
    return ("%d:%02d"):format(floor(s / 60), s % 60)
end

-- Raid nights that have pulls, newest first.
function PullLog.Nights()
    local seen, out = {}, {}
    for i = #db(), 1, -1 do
        local n = db()[i].night
        if n and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    return out
end

-- Pulls of one night (default: the newest), oldest first.
function PullLog.Pulls(night)
    night = night or PullLog.Nights()[1]
    local out = {}
    for _, p in ipairs(db()) do
        if p.night == night then out[#out + 1] = p end
    end
    return out, night
end

-- Which pull of that boss this was, that night (1 = first).
function PullLog.PullNumber(entry)
    local n = 0
    for _, p in ipairs(db()) do
        if p.night == entry.night and p.boss == entry.boss then
            n = n + 1
            if p == entry then return n end
        end
    end
    return n
end

-- Per boss that night, in order of the first pull: { boss, pulls, kills, best (lowest %
-- on a wipe), killTime (the first kill's combat time), combat (seconds) }.
function PullLog.Summary(night)
    local pulls = PullLog.Pulls(night)
    local order, byBoss = {}, {}
    local total = { pulls = #pulls, kills = 0, combat = 0 }
    for _, p in ipairs(pulls) do
        local s = byBoss[p.boss]
        if not s then
            s = { boss = p.boss, pulls = 0, kills = 0, combat = 0 }
            byBoss[p.boss] = s
            order[#order + 1] = s
        end
        s.pulls = s.pulls + 1
        s.combat = s.combat + (p.duration or 0)
        total.combat = total.combat + (p.duration or 0)
        if p.kill then
            s.kills = s.kills + 1
            total.kills = total.kills + 1
            s.killTime = s.killTime or p.duration
        elseif p.pct and (not s.best or p.pct < s.best) then
            s.best = p.pct
        end
    end
    return order, total
end

function PullLog.DeleteNight(night)
    local list = db()
    for i = #list, 1, -1 do
        if list[i].night == night then tremove(list, i) end
    end
    changed()
end

SRT:AddSlashCommand("pulls", function() SRT.Main.Toggle("pulllog") end, "open the pull log")
