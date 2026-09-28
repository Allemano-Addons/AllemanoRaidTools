-- SlaughterRaidTools: core namespace, event dispatcher, SavedVariables and slash command.
local addonName, SRT = ...

SRT.name = addonName
SRT.SCHEMA = 1
-- The SRT mark in white (Media/SRT_mark_white.tga, made from Media/SRT_logo_512.png), tinted
-- with the accent color wherever it is shown.
SRT.MARK = "Interface\\AddOns\\" .. addonName .. "\\Media\\SRT_mark_white"

function SRT:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cffc8332eSRT|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Errors: WoW Forever does not show Lua errors, so they are kept (last 10, also in
-- SlaughterRaidToolsDB.errors), announced once per session and listed by /srt errors.
-- ---------------------------------------------------------------------------

SRT.errors = {}
local announced = false

function SRT:RecordError(where, err)
    local list = self.errors
    list[#list + 1] = { t = time(), where = tostring(where), msg = tostring(err):sub(1, 400), v = self.version }
    while #list > 10 do tremove(list, 1) end
    if not announced then
        announced = true
        self:Print("|cffe8a33dhit an error|r (" .. tostring(where) .. "). /srt errors shows it.")
    end
    geterrorhandler()(err)
end

-- Run fn protected; errors are recorded instead of lost.
function SRT:Call(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then self:RecordError(where, err) end
    return ok
end

-- ---------------------------------------------------------------------------
-- Game events: several handlers per event, one shared frame. Each handler runs
-- protected so one failing part never stops the others.
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Returns false if the client does not know the event.
function SRT:RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = handler
    return true
end

function SRT:UnregisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then tremove(list, i) end
    end
    if #list == 0 then
        eventHandlers[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    -- In registration order, over a copy: a handler may unregister itself.
    local n = #list
    if n == 1 then
        local ok, err = pcall(list[1], event, ...)
        if not ok then SRT:RecordError(event, err) end
        return
    end
    local snapshot = { unpack(list, 1, n) }
    for i = 1, n do
        local ok, err = pcall(snapshot[i], event, ...)
        if not ok then SRT:RecordError(event, err) end
    end
end)

-- ---------------------------------------------------------------------------
-- SavedVariables: read at ADDON_LOADED, never at file load (WoW Forever quirk).
-- ---------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    debugComm = false,     -- print every addon message sent and received
    accent = "3FC7EB",
    useClassColor = false,
    font = "Friz Quadrata",
    textSize = "M",        -- S / M / L
    bgAlpha = 0.97,
    scale = 1,
    announceBreak = true,  -- post breaks in raid chat (for raiders without SRT)
    noteAutoShow = true,   -- open the note window when a new raid note arrives
    notePersonal = true,   -- show the personal note under the raid note
    noteAlpha = 0.85,      -- note window background opacity (0 = see-through)
    autoLog = true,        -- start the combat log in raid instances (CombatLog.lua)
    logDungeons = false,   -- ... and in 5-man dungeons
    advancedLogging = true, -- switch on advanced combat logging with it (Warcraft Logs)
    logAnnounce = true,    -- say in chat when the log starts or stops
    vnAcceptEveryone = false, -- visual notes from anyone in the group (default: leader and assistants)
    vnAutoShow = true,     -- open the viewer when a visual note arrives
}

local function fillDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            fillDefaults(dst[k], v)
        end
    end
end

-- Settings changes: listeners get (key, value). A failing listener never stops the others.
local settingListeners = {}
function SRT:OnSettingChanged(fn) settingListeners[#settingListeners + 1] = fn end

function SRT:SetSetting(key, value)
    self.db.settings[key] = value
    for _, fn in ipairs(settingListeners) do
        local ok, err = pcall(fn, key, value)
        if not ok then SRT:RecordError("setting " .. tostring(key), err) end
    end
end

local function initDB()
    if type(SlaughterRaidToolsDB) ~= "table" then SlaughterRaidToolsDB = {} end
    local db = SlaughterRaidToolsDB
    db.schema = db.schema or SRT.SCHEMA
    db.settings = db.settings or {}
    fillDefaults(db.settings, DEFAULT_SETTINGS)
    db.window = db.window or {}   -- main window position, last page
    db.timers = db.timers or {}   -- timer bar position, running timers (survive /reload)
    db.notes = db.notes or {}     -- the leader's saved notes: list, selected, nextId
    db.notes.list = db.notes.list or {}
    db.notes.nextId = db.notes.nextId or 1
    db.personal = db.personal or {} -- [guid] = personal note text
    db.noteWindow = db.noteWindow or {}
    db.invite = db.invite or {}   -- invite tools (see Invites.lua)
    fillDefaults(db.invite, { ranks = {}, keyword = "inv", keywordOn = false, guildOnly = true, autoConvert = true, assists = "",
        announce = "GUILD", announceText = "Inviting the raid roster now. Whisper me if you are missing an invite." })
    db.roster = db.roster or { text = "" } -- pasted OXM roster (text = the one being worked on)
    db.roster.profiles = db.roster.profiles or {} -- saved rosters by name (like MRT)
    if not next(db.roster.profiles) then db.roster.profiles.Default = db.roster.text or "" end
    if not db.roster.current or not db.roster.profiles[db.roster.current] then
        db.roster.current = db.roster.profiles.Default and "Default" or next(db.roster.profiles)
        db.roster.text = db.roster.profiles[db.roster.current]
    end
    db.pulls = db.pulls or {}     -- pull log (PullLog.lua), newest last
    db.visual = db.visual or {}   -- visual notes: saved (encoded), draft, received, viewer position
    db.visual.saved = db.visual.saved or {}
    db.visual.viewer = db.visual.viewer or {}
    db.raidcheck = db.raidcheck or {} -- raid check: categories (editable), options
    fillDefaults(db.raidcheck, { popup = "all", closeAfter = 8, minDurability = 50, onlyMissing = false, window = {} })
    if not db.raidcheck.categories then db.raidcheck.categories = CopyTable(SRT.RaidCheck.DEFAULTS) end
    db.launcher = db.launcher or {} -- launcher button position, hidden, locked (UI/Launcher.lua)
    db.toolbar = db.toolbar or {}  -- the small bar outside the main window (UI/Toolbar.lua)
    fillDefaults(db.toolbar, { shown = true, onlyInGroup = false, locked = false, vertical = false, rows = 1, scale = 1,
        items = { open = true, marks = true, world = true, readycheck = true, pull = true, breaktimer = true, note = true } })
    -- db.active = the raid note shown in the note window, db.lastSent = who confirmed ours
    -- Errors from before the saved data was loaded are kept too.
    db.errors = db.errors or {}
    for _, e in ipairs(SRT.errors) do tinsert(db.errors, e) end
    while #db.errors > 10 do tremove(db.errors, 1) end
    SRT.errors = db.errors
    SRT.db = db
end

-- Code that needs the saved data runs through SRT:OnReady (right away if already loaded).
local readyCallbacks = {}
function SRT:OnReady(fn)
    if self.ready then self:Call("OnReady", fn) else readyCallbacks[#readyCallbacks + 1] = fn end
end

SRT:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= addonName then return end
    initDB()
    SRT.version = SRT.Compat.GetAddOnMetadata(addonName, "Version") or "?"
    -- Errors from an older version were fixed (or are no longer relevant): drop them.
    for i = #SRT.errors, 1, -1 do
        local v = SRT.errors[i].v
        if v and v ~= SRT.version then tremove(SRT.errors, i) end
    end
end)

SRT:RegisterEvent("PLAYER_LOGIN", function()
    SRT.ready = true
    for _, fn in ipairs(readyCallbacks) do SRT:Call("OnReady", fn) end
    wipe(readyCallbacks)
end)

-- A blocked protected call is the only sign that Forever refused something: keep it.
local function blocked(event, addon, func)
    if addon == addonName then SRT:RecordError(event, tostring(func)) end
end
SRT:RegisterEvent("ADDON_ACTION_BLOCKED", blocked)
SRT:RegisterEvent("ADDON_ACTION_FORBIDDEN", blocked)

-- ---------------------------------------------------------------------------
-- Slash command: other files add subcommands with SRT:AddSlashCommand.
-- ---------------------------------------------------------------------------

local slashCommands, slashOrder = {}, {}

function SRT:AddSlashCommand(name, fn, help)
    if not slashCommands[name] then slashOrder[#slashOrder + 1] = name end
    slashCommands[name] = { fn = fn, help = help }
end

local function printHelp()
    SRT:Print("v" .. tostring(SRT.version) .. " commands (/srt alone opens the window):")
    for _, name in ipairs(slashOrder) do
        local c = slashCommands[name]
        if c.help then SRT:Print(("/srt %s - %s"):format(name, c.help)) end
    end
end

SRT:AddSlashCommand("errors", function(arg)
    if strlower(arg or "") == "clear" then
        wipe(SRT.errors)
        SRT:Print("Error list cleared.")
        return
    end
    if #SRT.errors == 0 then SRT:Print("No errors recorded.") return end
    for _, e in ipairs(SRT.errors) do
        SRT:Print(("[%s] %s (v%s): %s"):format(date("%d/%m %H:%M", e.t), e.where, tostring(e.v), e.msg))
    end
end, "show recent errors (/srt errors clear empties the list)")
SRT:AddSlashCommand("help", printHelp)

SLASH_SLAUGHTERRAIDTOOLS1 = "/srt"
SLASH_SLAUGHTERRAIDTOOLS2 = "/slaughterraidtools"
SlashCmdList.SLAUGHTERRAIDTOOLS = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    local c = slashCommands[cmd]
    if cmd == "" and SRT.Main then
        SRT.Main.Toggle()
    elseif c then
        local ok, err = pcall(c.fn, rest)
        if not ok then SRT:RecordError("/srt " .. cmd, err) end
    else
        printHelp()
    end
end
