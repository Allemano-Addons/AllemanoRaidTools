-- Auto logging: starts the combat log (/combatlog) when entering a raid instance (and
-- optionally dungeons) and stops it when leaving, but only a log SRT started itself.
-- Advanced combat logging (needed by Warcraft Logs) is switched on with it.
local _, SRT = ...

local CombatLog = {}
SRT.CombatLog = CombatLog

local startedBySRT = false

local function settings() return SRT.db.settings end

-- Is the combat log running? (C_ChatInfo on Forever, LoggingCombat() on older clients.)
function CombatLog.IsLogging()
    if C_ChatInfo and C_ChatInfo.IsLoggingCombat then
        local ok, on = pcall(C_ChatInfo.IsLoggingCombat)
        if ok then return on and true or false end
    end
    if LoggingCombat then
        local ok, on = pcall(LoggingCombat)
        if ok then return on and true or false end
    end
    return false
end

-- Turns the combat log on or off; returns true when the game did it.
function CombatLog.Set(on)
    if not LoggingCombat then return false end
    if on and settings().advancedLogging then
        local set = (C_CVar and C_CVar.SetCVar) or SetCVar
        if set then pcall(set, "advancedCombatLogging", "1") end
    end
    local ok = pcall(LoggingCombat, on and true or false)
    return ok and CombatLog.IsLogging() == (on and true or false)
end

local function say(msg)
    if settings().logAnnounce then SRT:Print(msg) end
end

-- The instance we are in counts for logging: raids, and dungeons when chosen.
local function wantedHere()
    local inInstance, kind = IsInInstance()
    if not inInstance then return false end
    if kind == "raid" then return true end
    return kind == "party" and settings().logDungeons
end

local function check()
    if not settings().autoLog then return end
    local name = GetInstanceInfo()
    if wantedHere() then
        if not CombatLog.IsLogging() then
            if CombatLog.Set(true) then
                startedBySRT = true
                say(("Combat log started (%s). Logs\\WoWCombatLog*.txt"):format(name or "instance"))
            else
                SRT:Print("Could not start the combat log. Type /combatlog yourself.")
            end
        end
    elseif startedBySRT and CombatLog.IsLogging() then
        if CombatLog.Set(false) then say("Combat log stopped.") end
        startedBySRT = false
    end
end

-- The instance type is only reliable a moment after the loading screen.
local function later() C_Timer.After(2, function() SRT:Call("auto log", check) end) end
SRT:RegisterEvent("PLAYER_ENTERING_WORLD", later)
SRT:RegisterEvent("ZONE_CHANGED_NEW_AREA", later)

function CombatLog.Toggle()
    local on = not CombatLog.IsLogging()
    if CombatLog.Set(on) then
        startedBySRT = false -- a manual choice is left alone
        SRT:Print(on and "Combat log started." or "Combat log stopped.")
    else
        SRT:Print("The game refused. Type /combatlog yourself.")
    end
    if SRT.Main then SRT.Main.Refresh() end
end

SRT:AddSlashCommand("log", function() CombatLog.Toggle() end, "start or stop the combat log")
