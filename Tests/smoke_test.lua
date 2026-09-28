-- Smoke test outside the game: loads every TOC file against a fake WoW API, fires the
-- login events and runs the slash commands. Addon messages loop back as if they came
-- from another raider. Catches Lua errors that WoW Forever would swallow silently.
-- Run from the addon folder: lua Tests/smoke_test.lua
local unpack = table.unpack or unpack
_G.unpack = unpack

-- Generic fake widget: known getters return sensible values, everything else is a no-op.
local GETTERS = {
    GetStringWidth = 50, GetStringHeight = 12, GetEffectiveScale = 1, GetWidth = 800, GetHeight = 600,
    GetLeft = 100, GetTop = 800, GetRight = 400, GetBottom = 100, GetFrameLevel = 1, IsEnabled = true,
    IsVisible = true, GetVerticalScroll = 0,
}
local scripts = {} -- strong: real frames are kept alive by their parent, mocks are not
local function mock(kind)
    local o = { _kind = kind, _shown = true }
    return setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end -- fields: nil, like real frames
        if k == "SetScript" then return function(self, name, fn) scripts[self] = scripts[self] or {}; scripts[self][name] = fn end end
        if k == "HookScript" then return function() end end
        if k == "RegisterEvent" then return function(_, e) if e:match("^FAKE") then error("unknown event") end end end
        if k == "Show" then return function(self) local was = self._shown; self._shown = true; local f = not was and scripts[self] and scripts[self].OnShow; if f then f(self) end end end
        if k == "Hide" then return function(self) local was = self._shown; self._shown = false; local f = was and scripts[self] and scripts[self].OnHide; if f then f(self) end end end
        if k == "SetShown" then return function(self, v) if v then self:Show() else self:Hide() end end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "SetColorTexture" or k == "SetTextColor" or k == "SetVertexColor" then
            return function(_, r, g, b, a)
                for i, v in ipairs({ r, g, b }) do assert(type(v) == "number", k .. ": component " .. i .. " is " .. type(v)) end
                assert(a == nil or type(a) == "number", k .. ": alpha is " .. type(a))
            end
        end
        if k == "SetFont" then return function() return true end end
        if k == "SetText" then return function(self, v) self._text = v end end
        if k == "GetText" then return function(self) return self._text or "" end end
        if k == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12 end end
        if k == "SetAlpha" then return function(self, v) self._alpha = v end end
        if k == "Insert" then return function(self, v) self._text = (self._text or "") .. v end end
        if k == "SetAttribute" then return function(self, key, v) self._attr = self._attr or {}; self._attr[key] = v end end
        if k == "CreateTexture" or k == "CreateFontString" then return function() return mock(k) end end
        if GETTERS[k] ~= nil then local v = GETTERS[k]; return function() return v end end
        return function() end
    end })
end

-- Fake clock and timers: time only moves when the test says so.
local now = 1000
GetTime = function() return now end
local timers = {}
C_Timer = {
    After = function(s, fn) timers[#timers + 1] = { at = now + s, fn = fn } end,
    NewTicker = function(s, fn)
        local t = { every = s, fn = fn, at = now + s }
        t.Cancel = function() t.cancelled = true end
        timers[#timers + 1] = t
        return t
    end,
}
local function advance(seconds)
    local stop = now + seconds
    while true do
        local nextT
        for _, t in ipairs(timers) do
            if not t.cancelled and not t.done and t.at <= stop and (not nextT or t.at < nextT.at) then nextT = t end
        end
        if not nextT then break end
        now = nextT.at
        if nextT.every then nextT.at = now + nextT.every else nextT.done = true end
        nextT.fn()
    end
    now = stop
end

-- WoW globals.
local allFrames = {}
CreateFrame = function(kind, name, _, template)
    local f = mock(kind)
    f._template = template
    allFrames[#allFrames + 1] = f
    if name then _G[name] = f end
    return f
end
UISpecialFrames = {}
GetServerTime = function() return 1790000000 + now end
GetPhysicalScreenSize = function() return 2560, 1440 end
GetCursorPosition = function() return 500, 500 end
UnitClass = function() return "Druid", "DRUID", 11 end
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druid", MAGE = "Mage" }
IsInGuild = function() return true end
GetGuildInfo = function() return "Slakthuset" end
IsInInstance = function() return false, "none" end
GetInstanceInfo = function() return "Kalimdor", "none", 0 end
InCombatLockdown = function() return false end
-- Secret values: any use but passing them around fails, like in the game.
local SECRET = setmetatable({}, { __add = function() error("arithmetic on a secret value") end,
    __tostring = function() error("tostring on a secret value") end,
    __index = function() error("indexing a secret value") end })
issecretvalue = function(v) return v == SECRET end
UnitHealth = function() return SECRET end
UnitHealthMax = function() return SECRET end
C_Spell = { GetSpellCooldown = function() return { startTime = SECRET, duration = 1.5 } end }
-- Buffs: auraOverride[unit] = list of auras; otherwise two "Flask" buffs (the player's
-- expiration time is secret, like in combat).
local auraOverride = {}
C_UnitAuras = { GetBuffDataByIndex = function(unit, i)
    if auraOverride[unit] then return auraOverride[unit][i] end
    if i > 2 then return nil end
    return { name = "Flask", spellId = 17628, icon = 1, duration = 7200, expirationTime = unit == "player" and SECRET or 9000 }
end }
local invisible = {}
UnitIsVisible = function(u) return not invisible[u] end
local durability = { cur = 50, max = 100 }
GetInventoryItemDurability = function(slot) if slot == 5 then return durability.cur, durability.max end end
local weaponEnchant = { true, 1200000 }
GetWeaponEnchantInfo = function() return weaponEnchant[1], weaponEnchant[2], 0, 1 end
C_RestrictedActions = { IsAddOnRestrictionActive = function() return true end, Something = function() end }
C_Secrets = { ShouldAurasBeSecret = function() return SECRET end }
local countdowns, readyChecks, chatLines = {}, 0, {}
local countdownWorks = true
local invited, converts, promotedUnits = {}, 0, {}
C_PartyInfo = {
    DoCountdown = function(s) if not countdownWorks then error("blocked") end countdowns[#countdowns + 1] = s end,
    DoReadyCheck = function() readyChecks = readyChecks + 1 end,
    InviteUnit = function(name) invited[#invited + 1] = name end,
    ConvertToRaid = function() converts = converts + 1 end,
    PromoteToAssistant = function(unit) promotedUnits[#promotedUnits + 1] = unit end,
}
-- Guild: Mårten twice (first names are not unique on Forever), Nylo offline.
local GUILD = {
    { "Allemano Moo", "Guild Master", 0, true }, { "Kogosh Boll", "Officer", 1, true },
    { "Aldera Stone", "Raider", 2, true }, { "Gretha Vale", "Raider", 2, true }, { "Nylo Ash", "Raider", 2, false },
    { "Mårten Ek", "Member", 3, true }, { "Mårten Al", "Member", 3, true },
}
GetNumGuildMembers = function() return #GUILD end
GetGuildRosterInfo = function(i)
    local g = GUILD[i]
    if g then return g[1], g[2], g[3], 20, "Druid", "Barrens", "", "", g[4], 0, "DRUID" end
end
C_GuildInfo = { GuildRoster = function() end }
UIParent = mock("Frame")
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m; print("[chat] " .. m) end }
SlashCmdList = {}
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
tostringall = function(...) local t = { ... } for i = 1, select("#", ...) do t[i] = tostring(t[i]) end return unpack(t, 1, select("#", ...)) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strupper, tinsert, tremove, sort, floor, ceil, min, max, format = string.lower, string.upper, table.insert, table.remove, table.sort, math.floor, math.ceil, math.min, math.max, string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
date, time = os.date, os.time
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
local errors = {}
geterrorhandler = function() return function(e) errors[#errors + 1] = e; print("ERROR: " .. tostring(e)) end end
C_AddOns = { GetAddOnMetadata = function() return "0.0.1" end, IsAddOnLoaded = function() return false end }
GetBuildInfo = function() return "1.60.1", "70009", "Sep 23 2026", 16001 end
UnitGUID = function(u) return "Player-1-" .. u end
GetNormalizedRealmName = function() return "ClassicBetaPvP2" end
UnitFullName = function() return "Allemano", "ClassicBetaPvP2" end
UnitPosition = function() return 1, 2, 0, 1 end
C_Map = { GetBestMapForUnit = function() return 1411 end }

-- A raid of four: us, two raiders with SRT (one on an older version) and one without.
local ROSTER = {
    { "Allemano", "Moo" }, { "Kogosh", "Boll" }, { "Whissel", "Ljud" }, { "Nobody", "Here" },
}
local inRaid = true
UnitName = function(unit)
    if unit == "player" then return "Allemano", "Moo" end
    local i = tonumber(unit:match("^raid(%d+)$"))
    if inRaid and i and ROSTER[i] then return ROSTER[i][1], ROSTER[i][2] end
    return nil
end
IsInRaid = function() return inRaid end
local partySize = 0 -- a party (not raid) of this many when inRaid is false
IsInGroup = function(cat) return (inRaid or partySize > 1) and cat ~= 2 end
GetNumGroupMembers = function() return inRaid and #ROSTER or partySize end
GetNumSubgroupMembers = function() return 0 end
GetRaidRosterInfo = function(i)
    local r = ROSTER[i]
    if r then return r[1], 0, r.group or 1, 20, "Druid", "DRUID", "Barrens", true end
end
local function groupCount(g)
    local n = 0
    for _, r in ipairs(ROSTER) do if (r.group or 1) == g then n = n + 1 end end
    return n
end
SetRaidSubgroup = function(i, g)
    assert(groupCount(g) < 5, "SetRaidSubgroup into a full group")
    ROSTER[i].group = g
end
SwapRaidSubgroup = function(a, b)
    ROSTER[a].group, ROSTER[b].group = ROSTER[b].group or 1, ROSTER[a].group or 1
end
UnitIsConnected = function() return true end
local targetIcon, hasTarget, shiftDown = 0, true, false
UnitExists = function(u) return u ~= "target" or hasTarget end
GetRaidTargetIndex = function() return targetIcon ~= 0 and targetIcon or nil end
SetRaidTarget = function() error("forbidden: SetRaidTarget is protected on Forever") end
IsShiftKeyDown = function() return shiftDown end
local leaderUnit = "player"
local assistants = {}
UnitIsGroupLeader = function(u) return u == leaderUnit end
UnitIsGroupAssistant = function(u) return assistants[u] or false end

-- Addon messages: everything sent is recorded; the test delivers messages itself.
local sent = {}
local throttleNext = 0
local fire
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return 0 end,
    SendAddonMessage = function(prefix, text, channel, target)
        assert(#text <= 255, "addon message too long: " .. #text)
        assert(#prefix <= 16, "prefix too long")
        if throttleNext > 0 then throttleNext = throttleNext - 1; return 3 end
        sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target, t = now }
        return 0
    end,
    SendChatMessage = function(msg, channel) chatLines[#chatLines + 1] = { msg = msg, channel = channel } end,
    AreOutgoingAddonChatMessagesRestricted = function() return false end,
}

-- Load the TOC files in order with the shared addon table.
local SRT = {}
for line in io.lines("SlaughterRaidTools.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then
        local chunk = assert(loadfile((line:gsub("\\", "/"))))
        chunk("SlaughterRaidTools", SRT)
    end
end

fire = function(event, ...)
    for f, s in pairs(scripts) do if s.OnEvent then s.OnEvent(f, event, ...) end end
end

-- Delivers sent messages as if `from` had sent them, then clears the outbox.
local function deliver(from)
    local list = sent
    sent = {}
    for _, m in ipairs(list) do fire("CHAT_MSG_ADDON", m.prefix, m.text, m.channel, from or "Allemano Moo-ClassicBetaPvP2", m.target) end
    return #list
end

local function step(name, fn)
    local ok, err = pcall(fn)
    print((ok and "ok   " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(err))))
    if not ok then errors[#errors + 1] = err end
end

local function chatHas(pattern)
    for _, m in ipairs(chat) do if m:find(pattern) then return true end end
    return false
end

step("ADDON_LOADED", function() fire("ADDON_LOADED", "SlaughterRaidTools") end)
step("PLAYER_LOGIN", function() fire("PLAYER_LOGIN") end)
step("help", function() SlashCmdList.SLAUGHTERRAIDTOOLS("help") assert(chatHas("/srt version")) end)
step("full name has the surname", function() assert(SRT.Compat.PlayerName() == "Allemano Moo", SRT.Compat.PlayerName()) end)

step("own messages are ignored", function()
    local got
    SRT.Comm.Register("TEST", function() got = true end)
    SRT.Comm.Send("TEST", "hi")
    deliver() -- from ourselves
    assert(not got, "handled our own message")
end)

step("short message arrives in one part", function()
    local got
    SRT.Comm.Register("TEST", function(sender, payload) got = { sender, payload } end)
    assert(SRT.Comm.Send("TEST", "hello|with|pipes") == 1)
    assert(deliver("Kogosh Boll") == 1)
    assert(got and got[1] == "Kogosh Boll" and got[2] == "hello|with|pipes", "wrong payload")
end)

step("long message is split, paced and joined", function()
    local body = {}
    for i = 1, 3000 do body[i] = string.char(33 + i % 90) end
    body = table.concat(body)
    local got
    SRT.Comm.Register("TEST", function(_, payload) got = payload end)
    advance(30) -- full burst
    local parts = SRT.Comm.Send("TEST", body)
    assert(parts == 13, "parts: " .. tostring(parts))
    assert(#sent == 8, "burst should send 8 at once, sent " .. #sent)
    advance(2.1)
    assert(#sent == 10, "pacing: expected 10 after 2 s, got " .. #sent)
    advance(10)
    assert(#sent == 13 and SRT.Comm.QueueSize() == 0, "not all parts sent")
    -- Deliver out of order.
    local list = sent
    sent = {}
    for i = #list, 1, -1 do fire("CHAT_MSG_ADDON", "SRT", list[i].text, "RAID", "Kogosh Boll", nil) end
    assert(got == body, "joined payload differs")
end)

step("throttled send is retried", function()
    local got
    SRT.Comm.Register("TEST", function(_, payload) got = payload end)
    advance(30)
    throttleNext = 1
    SRT.Comm.Send("TEST", "again")
    assert(#sent == 0 and SRT.Comm.QueueSize() == 1, "throttled message was dropped or sent")
    advance(2)
    assert(#sent == 1, "not retried")
    deliver("Kogosh Boll")
    assert(got == "again")
end)

step("other protocol and garbage are ignored", function()
    fire("CHAT_MSG_ADDON", "SRT", "2|TEST|1|1|1|x", "RAID", "Kogosh Boll")
    fire("CHAT_MSG_ADDON", "SRT", "probe whisper", "WHISPER", "Kogosh Boll")
    fire("CHAT_MSG_ADDON", "OTHER", "1|TEST|1|1|1|x", "RAID", "Kogosh Boll")
end)

step("comm test round trip", function()
    SlashCmdList.SLAUGHTERRAIDTOOLS("comm test 600")
    advance(10)
    deliver("Whissel Ljud")
    assert(chatHas("Whissel Ljud: 600 bytes, .*intact"), "echo not reported intact")
end)

step("version compare", function()
    local C = SRT.Version.Compare
    assert(C("0.10.0", "0.9.9") == 1 and C("0.0.1", "0.0.1") == 0 and C("1.0", "1.0.1") == -1)
end)

step("version check lists versions and missing", function()
    advance(30)
    SlashCmdList.SLAUGHTERRAIDTOOLS("version")
    assert(#sent == 1 and sent[1].text:find("|VQ|"), "no query sent")
    sent = {}
    -- Replies from two raiders, one with an older version.
    fire("CHAT_MSG_ADDON", "SRT", "1|VR|1|1|1|0.0.1", "RAID", "Kogosh Boll-ClassicBetaPvP2")
    fire("CHAT_MSG_ADDON", "SRT", "1|VR|1|1|1|0.0.0", "RAID", "Whissel Ljud")
    advance(4)
    assert(chatHas("0%.0%.1.*%(2%).*Allemano Moo, Kogosh Boll"), "current version line wrong")
    assert(chatHas("0%.0%.0.*%(1%).*Whissel Ljud"), "old version line wrong")
    assert(chatHas("no SRT.*%(1%).*Nobody Here"), "missing line wrong")
end)

step("answering a query and noticing a newer version", function()
    advance(30)
    fire("CHAT_MSG_ADDON", "SRT", "1|VQ|5|1|1|0.2.0", "RAID", "Kogosh Boll")
    assert(#sent == 1 and sent[1].text:find("|VR|.*0%.0%.1$"), "no reply")
    sent = {}
    assert(chatHas("Kogosh Boll runs a newer version %(0%.2%.0"), "newer version not mentioned")
end)

step("version alone", function()
    inRaid = false
    SlashCmdList.SLAUGHTERRAIDTOOLS("version")
    assert(chatHas("not in a group"), "solo version line missing")
    inRaid = true
end)

step("probe", function()
    SlashCmdList.SLAUGHTERRAIDTOOLS("probe")
    deliver("Allemano Moo")
    advance(6)
    local p = SRT.db.probe["Player-1-player"]
    assert(p and p.apis and p.events.CHAT_MSG_ADDON == "ok", "probe result missing")
    assert(#p.comm.received >= 1, "probe did not record received messages")
    assert(p.auras.player[1].expirationTime == "<secret>" and p.auras.raid2[1].name == "Flask", "aura probe wrong")
end)

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- The first visible button whose label is `label` (buttons keep their text in .text).
local function button(label)
    for f, s in pairs(scripts) do
        if s.OnClick and f.text and f.text._text == label and f._shown ~= false then return f end
    end
end
local function click(label)
    local b = assert(button(label), "no button '" .. label .. "'")
    scripts[b].OnClick(b, "LeftButton")
    return b
end

step("open window", function()
    SlashCmdList.SLAUGHTERRAIDTOOLS("")
    local f = _G.SlaughterRaidToolsFrame
    assert(f and f._shown, "window not shown")
    assert(SRT.db.window.page == "home", "not on home")
end)
step("every page opens", function()
    for _, section in ipairs(SRT.Main.NAV) do
        for _, item in ipairs(section[2]) do
            click(item[2])
            assert(SRT.db.window.page == item[1], "page " .. item[1] .. " not selected")
        end
    end
    click("Home")
end)
step("appearance: swatch, class color, font, sizes", function()
    click("Appearance")
    local sw
    for f, s in pairs(scripts) do if s.OnClick and f.hex == "C8332E" then sw = f end end
    scripts[sw].OnClick(sw)
    assert(SRT.db.settings.accent == "C8332E", "swatch did not set the accent")
    assert(select(1, SRT.Theme:Accent()) > 0.7, "accent not applied")
    SRT:SetSetting("useClassColor", true)
    local r, g = SRT.Theme:Accent()
    assert(r == 1 and g == 0.49, "class color not used")
    for _, kv in ipairs({ { "font", "Arial Narrow" }, { "textSize", "L" }, { "bgAlpha", 0.7 }, { "scale", 1.2 } }) do
        SRT:SetSetting(kv[1], kv[2])
    end
    click("Advanced")
    click("Home")
end)
step("ready check and pull use Blizzard's", function()
    click("Ready check")
    assert(readyChecks == 1, "no ready check")
    click("Pull 10s")
    assert(countdowns[1] == 10, "no countdown")
    assert(#sent == 0, "native pull should not need addon messages")
end)
step("pull falls back to SRT bars when refused", function()
    advance(30)
    countdownWorks = false
    SlashCmdList.SLAUGHTERRAIDTOOLS("pull 15")
    countdownWorks = true
    assert(SRT.Timers.Remaining("pull") == 15, "no local pull bar")
    assert(#sent == 1 and sent[1].text:find("|TIMER|.*pull|15$"), "no TIMER message")
    assert(chatLines[#chatLines].msg == "Pull in 15", "no chat line")
    sent = {}
    advance(16)
    assert(SRT.Timers.Remaining("pull") == nil, "pull bar did not end")
end)
step("break: bar, message, chat, end", function()
    advance(30)
    click("Break 10 min")
    assert(SRT.Timers.Remaining("break") == 600, "no break bar")
    assert(SRT.db.timers.running["break"].ends == GetServerTime() + 600, "break not saved for /reload")
    assert(sent[1].text:find("|TIMER|.*break|600$"), "no TIMER message")
    assert(chatLines[#chatLines].msg:find("^Break 10 min, back at"), "no chat line")
    sent = {}
    advance(1)
    assert(_G.SlaughterRaidToolsFrame and button("End break"), "button did not switch to End break")
    click("End break")
    assert(SRT.Timers.Remaining("break") == nil, "break did not end")
    assert(chatLines[#chatLines].msg == "Break is over")
    sent = {}
end)
step("timers from raiders: only leader or assist", function()
    fire("CHAT_MSG_ADDON", "SRT", "1|TIMER|7|1|1|break|300", "RAID", "Kogosh Boll")
    assert(SRT.Timers.Remaining("break") == nil, "a normal raider started a break")
    assistants.raid2 = true
    fire("CHAT_MSG_ADDON", "SRT", "1|TIMER|8|1|1|break|300", "RAID", "Kogosh Boll")
    assert(SRT.Timers.Remaining("break") == 300, "assistant's break ignored")
    fire("CHAT_MSG_ADDON", "SRT", "1|TIMER|9|1|1|break|0", "RAID", "Kogosh Boll")
    assert(SRT.Timers.Remaining("break") == nil, "break 0 did not stop it")
    assistants.raid2 = nil
end)
step("not leader: buttons disabled, slash refused", function()
    leaderUnit = "raid2"
    SRT.Main.Refresh()
    assert(button("Pull 10s").disabledReason, "pull not disabled")
    local before = #countdowns
    SlashCmdList.SLAUGHTERRAIDTOOLS("pull")
    assert(#countdowns == before and chatHas("Only the raid leader"), "pull not refused")
    leaderUnit = "player"
    SRT.Main.Refresh()
    assert(not button("Pull 10s").disabledReason, "pull still disabled")
end)
step("combat probe", function()
    click("Home")
    click("Run probe")
    assert(SRT.Probe.CombatState() == "armed")
    fire("PLAYER_REGEN_DISABLED")
    advance(2)
    deliver("Allemano Moo")
    advance(4)
    local c = SRT.db.probe["Player-1-player"].combat
    assert(#c.snapshots == 1, "no snapshot")
    local s = c.snapshots[1]
    assert(s.health.player[1] == "<secret>", "secret health not masked")
    assert(s.addonRestricted[1] == "false" and s.restricted.IsAddOnRestrictionActive[1] == "true", "restriction info missing")
    assert(s.secrets.ShouldAurasBeSecret[1] == "<secret>", "secret return not masked")
    assert(s.receivedCount >= 1, "combat message not recorded")
    fire("ENCOUNTER_START", 610, "Onyxia")
    advance(3)
    assert(#c.snapshots == 2 and c.snapshots[2].extra == "610 Onyxia", "encounter snapshot missing")
    -- A normal probe afterwards keeps the combat results.
    SlashCmdList.SLAUGHTERRAIDTOOLS("probe")
    advance(6)
    assert(SRT.db.probe["Player-1-player"].combat == c, "normal probe dropped the combat probe")
end)
step("resize grip saves the size, reset clears it", function()
    local grip
    for f, s in pairs(scripts) do if s.OnMouseDown and f.dots then grip = f end end
    assert(grip, "no resize grip")
    scripts[grip].OnMouseDown(grip, "LeftButton")
    scripts[grip].OnMouseUp(grip, "LeftButton")
    assert(SRT.db.window.w == 800 and SRT.db.window.h == 600, "size not saved")
    SRT.Main.ResetPosition()
    assert(SRT.db.window.w == nil, "reset kept the size")
end)

-- ---------------------------------------------------------------------------
-- Notes
-- ---------------------------------------------------------------------------

local Notes = SRT.Notes
step("note text survives escaping", function()
    local s = "Line 1\nTabs\there ~ and ~n literally || pipes\n\nend~"
    assert(Notes.unescape(Notes.escape(s)) == s, "round trip changed the text")
    assert(not Notes.escape(s):find("[\n\t]"), "newline or tab left in the payload")
end)
step("rendering: icons, names, private blocks", function()
    SRT:SetSetting("useClassColor", false)
    SRT:SetSetting("accent", "C8332E")
    local out = Notes.Render("{rt1} {skull} Kogosh Boll tanks, Whissel heals\n{p:Whissel Ljud}secret{/p}{p:allemano}mine{/p} Allemano")
    assert(out:find("UI%-RaidTargetingIcon_1") and out:find("UI%-RaidTargetingIcon_8"), "icons missing")
    assert(out:find("|cff%x+Kogosh Boll|r"), "full name not colored as one")
    assert(not out:find("|cff%x+Kogosh|r"), "first name colored inside the full name")
    assert(out:find("|cff%x+Whissel|r"), "first name not colored")
    assert(not out:find("secret") and out:find("mine"), "private blocks wrong")
    assert(out:find("|cffff7d0aAllemano|r"), "own name not in class color: " .. out)
    assert(not out:find("c8332e"), "accent used in the note")
    local solo
    inRaid = false
    solo = Notes.Render("Allemano Moo")
    inRaid = true
    assert(solo:find("|cffff7d0aAllemano Moo|r"), "own full name not class colored solo: " .. solo)
end)
step("notes page: new note, edit, send solo shows it to me", function()
    sent = {}
    SlashCmdList.SLAUGHTERRAIDTOOLS("")
    click("Notes")
    click("New note")
    local n = Notes.Selected()
    assert(n and n.title == "Note 1", "no new note")
    Notes.Save(n.id, "Onyxia", "{skull} Onyxia\nKogosh Boll tanks\n{p:Whissel Ljud}Whissel: dispel{/p}")
    Notes.Changed()
    inRaid = false
    SRT.Main.Refresh()
    click("Show to me")
    inRaid = true
    assert(Notes.Active() and Notes.Active().title == "Onyxia", "not shown locally")
    assert(#sent == 0, "sent while solo")
    assert(SRT.NoteWindow.IsShown(), "note window did not open")
end)
local lastHash
step("send to raid: parts, confirmations, missing list", function()
    advance(30)
    SRT.Main.Refresh()
    click("Send to raid")
    assert(#sent >= 1 and sent[1].text:find("^1|NOTE|"), "no NOTE message")
    lastHash = SRT.db.lastSent.hash
    sent = {}
    fire("CHAT_MSG_ADDON", "SRT", "1|NACK|3|1|1|" .. lastHash, "WHISPER", "Kogosh Boll")
    fire("CHAT_MSG_ADDON", "SRT", "1|NACK|3|1|1|999", "WHISPER", "Whissel Ljud") -- other note
    local s = Notes.Status()
    assert(s.have == 2 and s.total == 4, ("have %d of %d"):format(s.have, s.total))
    assert(#s.missing == 2, "missing list wrong")
    for _, m in ipairs(s.missing) do
        if m.name == "Nobody Here" then assert(m.noSRT, "Nobody should be marked no SRT") end
        if m.name == "Whissel Ljud" then assert(not m.noSRT, "Whissel runs SRT") end
    end
    click("Home") -- the card shows the status
end)
step("late joiner asks, the sender answers by whisper", function()
    advance(30)
    fire("CHAT_MSG_ADDON", "SRT", "1|NREQ|4|1|1|", "RAID", "Whissel Ljud")
    assert(#sent >= 1 and sent[1].channel == "WHISPER" and sent[1].target == "Whissel Ljud" and sent[1].text:find("|NOTE|"), "no answer")
    sent = {}
end)
step("receiving: only from leader or assist, confirms by whisper", function()
    advance(30)
    local text = {}
    for i = 1, 60 do text[i] = ("Line %d: {rt%d} Whissel moves ~ left"):format(i, i % 8 + 1) end
    text = table.concat(text, "\n")
    local payload = "4242\t" .. Notes.escape("Nefarian") .. "\t" .. Notes.escape(text)
    -- Build the parts like a real sender would, then deliver them from Kogosh.
    local realSent = sent
    SRT.Comm.Send("NOTE", payload)
    advance(20)
    local parts = sent
    sent = realSent
    assert(#parts > 5, "long note should be several parts")
    for _, m in ipairs(parts) do fire("CHAT_MSG_ADDON", "SRT", m.text, "RAID", "Kogosh Boll") end
    assert(Notes.Active().title == "Onyxia", "a normal raider changed the note")
    sent = {}
    assistants.raid2 = true
    for _, m in ipairs(parts) do fire("CHAT_MSG_ADDON", "SRT", m.text, "RAID", "Kogosh Boll") end
    assistants.raid2 = nil
    local a = Notes.Active()
    assert(a.title == "Nefarian" and a.text == text and a.sender == "Kogosh Boll", "note not received intact")
    advance(2)
    assert(sent[1] and sent[1].text:find("|NACK|.*|4242$") and sent[1].target == "Kogosh Boll", "no confirmation")
    sent = {}
end)
step("joining a group asks for the note", function()
    inRaid = false
    fire("GROUP_ROSTER_UPDATE")
    inRaid = true
    fire("GROUP_ROSTER_UPDATE")
    advance(4)
    assert(sent[1] and sent[1].text:find("|NREQ|"), "no request after joining")
    sent = {}
end)
step("post in raid chat skips private text", function()
    local before = #chatLines
    Notes.PostToChat("{skull} Onyxia\n\n{p:Whissel Ljud}Whissel: dispel{/p}\nGo")
    advance(2)
    local got = {}
    for i = before + 1, #chatLines do got[#got + 1] = chatLines[i].msg end
    assert(#got == 2 and got[1] == "{skull} Onyxia" and got[2] == "Go", "chat lines: " .. table.concat(got, " / "))
end)
step("personal note, opacity and note window toggle", function()
    Notes.SetPersonal("Bring fire resistance")
    SRT.NoteWindow.Refresh()
    click("Appearance")
    SRT:SetSetting("noteAlpha", 0)
    SRT:SetSetting("noteAlpha", 0.5)
    click("Home")
    SlashCmdList.SLAUGHTERRAIDTOOLS("note")
    assert(not SRT.NoteWindow.IsShown(), "note window did not hide")
    assert(not SRT.db.noteWindow.shown, "hidden state not saved")
    SlashCmdList.SLAUGHTERRAIDTOOLS("note")
    assert(SRT.NoteWindow.IsShown(), "note window did not show")
    click("Notes")
    click("Personal note")
    click("Raid notes")
    click("Delete")
end)

-- ---------------------------------------------------------------------------
-- Invites & groups
-- ---------------------------------------------------------------------------

local Invites = SRT.Invites
local OXM = [[
Aldera
Gavztahx
Helixspal
Gretha
Erikdsham
Nylo
Sterlings
Blowfish
Tyrís
Vandiia

Lurre
Swiftmendarn
Zalthenia
Bluelazer/Tryan
Mercifultoad
Wallengrèn
Kaupi
Allemano
Crabthief
Helgonet

Mårten
Hajteck
Pjexie
]]
step("roster: five per group, blank lines ignored, alternatives", function()
    local slots = Invites.ParseRoster(OXM)
    assert(#slots == 23, "slots: " .. #slots)
    assert(slots[1].group == 1 and slots[5].group == 1 and slots[6].group == 2 and slots[11].group == 3, "groups wrong")
    assert(slots[23].group == 5 and slots[23].names[1] == "Pjexie", "last slot wrong")
    assert(#slots[14].names == 2 and slots[14].names[2] == "Tryan", "alternatives wrong")
    assert(Invites.ParseRoster("a\r\nb\r\n")[2].names[1] == "b", "CRLF lines")
end)
step("roster matching: raid, guild, offline, ambiguous, unknown", function()
    local slots = Invites.MatchRoster(Invites.ParseRoster("Kogosh\nWhissel Ljud\nAldera\nMårten\nNylo\nGhost\nNobody/Allemano"))
    local st = {}
    for i, s in ipairs(slots) do st[i] = s.state end
    assert(table.concat(st, ",") == "raid,raid,guild,ambiguous,offline,unknown,raid", table.concat(st, ","))
    assert(slots[3].guildName == "Aldera Stone", "guild name for invite")
    assert(slots[7].member.name == "Nobody Here", "first alternative in raid should win")
end)
step("sorting moves: set into free group, swap into full group", function()
    local members = {}
    for i = 1, 5 do members[i] = { index = i, group = 1 } end
    members[6] = { index = 6, group = 2 }
    local kind, a, b = Invites.NextMove(members, { [1] = 1, [2] = 1, [3] = 1, [4] = 1, [6] = 1 })
    assert(kind == "swap" and a == 6 and b == 5, "expected a swap with the unlisted player")
    kind, a, b = Invites.NextMove(members, { [6] = 3 })
    assert(kind == "set" and a == 6 and b == 3, "expected a set")
    assert(Invites.NextMove(members, { [1] = 1, [6] = 2 }) == nil, "already sorted")
end)
step("sort the raid from the roster", function()
    SRT.db.roster.text = "Kogosh\nWhissel\nNobody\nGhost\nGhost2\nAllemano"
    for _, r in ipairs(ROSTER) do r.group = 1 end
    Invites.Sort()
    advance(5)
    assert(ROSTER[1].group == 2 and ROSTER[2].group == 1 and ROSTER[3].group == 1 and ROSTER[4].group == 1, "not sorted")
    assert(not Invites.IsSorting() and chatHas("Groups applied"), "sorting did not finish")
end)
step("groups page renders the roster", function()
    SRT.db.roster.text = OXM
    SlashCmdList.SLAUGHTERRAIDTOOLS("")
    click("Invites & groups")
    click("Groups")
    click("Invite")
end)
step("invite guild ranks (raid: everyone at once)", function()
    wipe(invited)
    SRT.db.invite.ranks[2] = true
    SRT.Main.Refresh()
    click("Invite online (2)")
    advance(2)
    assert(#invited == 2 and invited[1] == "Aldera Stone" and invited[2] == "Gretha Vale", "invited: " .. table.concat(invited, ","))
    SRT.db.invite.ranks[2] = nil
end)
step("keyword whispers", function()
    wipe(invited)
    local s = SRT.db.invite
    s.keywordOn, s.keyword, s.guildOnly = true, "inv", true
    fire("CHAT_MSG_WHISPER", " INV ", "Mårten Ek")
    fire("CHAT_MSG_WHISPER", "inv", "Stranger Danger")
    fire("CHAT_MSG_WHISPER", "inv please", "Aldera Stone")
    advance(2)
    assert(#invited == 1 and invited[1] == "Mårten Ek", "guild-only keyword: " .. table.concat(invited, ","))
    s.guildOnly = false
    fire("CHAT_MSG_WHISPER", "inv", "Stranger Danger")
    advance(2)
    assert(invited[2] == "Stranger Danger", "keyword for anyone")
    s.keywordOn = false
    fire("CHAT_MSG_WHISPER", "inv", "Other Guy")
    advance(2)
    assert(#invited == 2, "keyword off still invites")
end)
step("party first: 4 invites, convert, then the rest", function()
    advance(100) -- earlier unanswered invites stop holding party slots
    wipe(invited)
    local savedRoster = ROSTER
    inRaid, partySize = false, 0
    local names = {}
    for i = 1, 7 do names[i] = "Player" .. i .. " X" end
    Invites.Queue(names)
    advance(3)
    assert(#invited == 4, "a party only takes 4 invites, sent " .. #invited)
    partySize = 2 -- someone accepted
    fire("GROUP_ROSTER_UPDATE")
    advance(2)
    assert(converts >= 1, "did not convert to raid")
    ROSTER = { { "Allemano", "Moo" }, { "Player1", "X" } }
    inRaid, partySize = true, 0
    fire("GROUP_ROSTER_UPDATE")
    advance(3)
    assert(#invited == 7 and Invites.Pending() == 0, "rest not invited: " .. #invited)
    ROSTER = savedRoster
    fire("GROUP_ROSTER_UPDATE")
end)
step("your own name is never ambiguous with your alt", function()
    table.insert(GUILD, { "Allemano Mu", "Member", 3, true })
    inRaid = false
    local slots = Invites.MatchRoster(Invites.ParseRoster("Allemano"))
    inRaid = true
    assert(slots[1].state == "raid" and slots[1].member.unit == "player", "solo: " .. slots[1].state)
    slots = Invites.MatchRoster(Invites.ParseRoster("Allemano"))
    assert(slots[1].state == "raid" and slots[1].member.name == "Allemano Moo", "raid: " .. slots[1].state)
    table.remove(GUILD)
end)
step("party members count as in the group; the rest are listed; class colors", function()
    inRaid = false
    local realName, realSub = UnitName, GetNumSubgroupMembers
    GetNumSubgroupMembers = function() return 1 end
    UnitName = function(u)
        if u == "party1" then return "Boogie", "Wonde" end
        return realName(u)
    end
    partySize = 2
    local slots, others = Invites.MatchRoster(Invites.ParseRoster("Aldera\nAllemano"))
    assert(slots[1].state == "guild" and slots[1].classFile == "DRUID", "guild member class")
    assert(slots[2].state == "raid" and slots[2].member.group == 1 and slots[2].classFile == "DRUID", "you in the party")
    assert(#others == 1 and others[1].name == "Boogie Wonde", "party member not on the roster")
    -- Drag Boogie from "not on the roster" into group 2, then back out.
    SRT.db.roster.text = "Aldera\nAllemano"
    assert(Invites.AddToGroup("Boogie Wonde", 2))
    assert(SRT.db.roster.text == "Aldera\nAllemano\n-\n-\n-\nBoogie Wonde", "add: " .. SRT.db.roster.text)
    slots, others = Invites.Roster()
    assert(slots[6].state == "raid" and #others == 0, "Boogie now on the roster")
    assert(Invites.AddToGroup("Kogosh", 1, 2) and SRT.db.roster.text:find("^Aldera\nAllemano\nKogosh"), "occupied place: first free")
    assert(Invites.RemovePlace(6) and not SRT.db.roster.text:find("Boogie"), "take off the roster")
    UnitName, GetNumSubgroupMembers, partySize = realName, realSub, 0
    inRaid = true
end)
step("drag and drop: move into a group, full group, swap, empty places", function()
    SRT.db.roster.text = "A\nB\nC\nD\nE\nF"
    assert(Invites.MoveToGroup(1, 2))
    assert(SRT.db.roster.text == "-\nB\nC\nD\nE\nF\nA", "move: " .. SRT.db.roster.text)
    SRT.db.roster.text = "A\nB\nC\nD\nE\nF\nG\nH\nI\nJ"
    local ok, why = Invites.MoveToGroup(1, 2)
    assert(not ok and why:find("full"), "full group accepted")
    assert(Invites.SwapPlaces(1, 12))
    assert(SRT.db.roster.text == "-\nB\nC\nD\nE\nF\nG\nH\nI\nJ\n\n-\nA", "swap: " .. SRT.db.roster.text)
    local slots = Invites.ParseRoster(SRT.db.roster.text)
    assert(slots[1].empty and slots[11].empty and slots[12].names[1] == "A" and slots[12].group == 3, "empty places")
    -- Moving the last name away drops the trailing empty places.
    assert(Invites.MoveToGroup(12, 1))
    assert(SRT.db.roster.text == "A\nB\nC\nD\nE\nF\nG\nH\nI\nJ", "trim: " .. SRT.db.roster.text)
end)
step("drag and drop changes the plan; Apply groups moves the raid", function()
    SRT.db.roster.text = "Kogosh\nWhissel\nNobody\n-\n-\nAllemano"
    for i, r in ipairs(ROSTER) do r.group = i == 1 and 2 or 1 end
    Invites.SwapPlaces(1, 6)
    advance(2)
    assert(ROSTER[2].group == 1 and ROSTER[1].group == 2, "the drag moved the raid")
    Invites.Sort()
    advance(3)
    assert(ROSTER[2].group == 2 and ROSTER[1].group == 1, "Apply groups did not move Kogosh/Allemano")
    assert(ROSTER[3].group == 1 and ROSTER[4].group == 1, "others moved")
    assert(chatHas("Groups applied"), "no confirmation")
end)
step("invite roster announces in guild chat", function()
    advance(100)
    wipe(invited)
    SRT.db.roster.text = "Aldera\nGretha\nKogosh"
    local before = #chatLines
    Invites.InviteRoster()
    advance(2)
    assert(#invited == 2, "invited: " .. table.concat(invited, ","))
    local line = chatLines[before + 1]
    assert(line and line.channel == "GUILD" and line.msg:find("Inviting the raid roster"), "no guild announcement")
    SRT.db.invite.announce = "OFF"
    before = #chatLines
    advance(100)
    wipe(invited)
    Invites.InviteRoster()
    assert(#chatLines == before, "announced while off")
    SRT.db.invite.announce = "GUILD"
end)
step("drag and drop in the page", function()
    SRT.db.roster.text = "Kogosh\nWhissel\nNobody"
    SlashCmdList.SLAUGHTERRAIDTOOLS("")
    click("Invites & groups")
    click("Groups")
    local src, dst
    for f, s in pairs(scripts) do
        if s.OnDragStart and f.pos == 1 and f.filled then src = f end
        if s.OnDragStart and f.pos == 7 and f.box and f.box._shown then dst = f end
    end
    assert(src and dst, "group lines not found (is group 2 shown as a drop target?)")
    scripts[src].OnDragStart(src)
    rawset(dst, "IsMouseOver", function() return true end)
    rawset(dst.box, "IsMouseOver", function() return true end)
    scripts[src].OnDragStop(src)
    rawset(dst, "IsMouseOver", nil)
    rawset(dst.box, "IsMouseOver", nil)
    assert(SRT.db.roster.text == "-\nWhissel\nNobody\n-\n-\n-\nKogosh", "drop: " .. SRT.db.roster.text)
    advance(3)
    -- From "not on the roster" (you are in the raid but not listed) into place 1.
    local chip, first
    for f, s in pairs(scripts) do
        if s.OnDragStart and f.name == "Allemano Moo" and f._shown then chip = f end
        if s.OnDragStart and f.pos == 1 then first = f end
    end
    assert(chip and first, "not-on-the-roster name not shown")
    scripts[chip].OnDragStart(chip)
    rawset(first, "IsMouseOver", function() return true end)
    rawset(first.box, "IsMouseOver", function() return true end)
    scripts[chip].OnDragStop(chip)
    rawset(first, "IsMouseOver", nil)
    rawset(first.box, "IsMouseOver", nil)
    assert(SRT.db.roster.text:find("^Allemano Moo\nWhissel"), "member drop: " .. SRT.db.roster.text)
end)
step("auto assist when they join", function()
    wipe(promotedUnits)
    SRT.db.invite.assists = "kogosh, Whissel Ljud, Somebody"
    fire("GROUP_ROSTER_UPDATE")
    table.sort(promotedUnits)
    assert(table.concat(promotedUnits, ",") == "raid2,raid3", "promoted: " .. table.concat(promotedUnits, ","))
    fire("GROUP_ROSTER_UPDATE")
    assert(#promotedUnits == 2, "promoted twice")
end)

-- ---------------------------------------------------------------------------
-- Toolbar
-- ---------------------------------------------------------------------------

local Toolbar = SRT.Toolbar
local function secure(macro)
    for _, f in ipairs(allFrames) do if f._attr and f._attr.macrotext == macro then return f end end
end
step("toolbar is shown after login", function()
    assert(Toolbar.IsShown(), "toolbar hidden")
end)
step("toolbar: world markers are secure macro buttons", function()
    for i = 1, 8 do
        local b = assert(secure("/wm " .. i), "no button for /wm " .. i)
        assert(b._template == "SecureActionButtonTemplate" and b._attr.type == "macro", "world marker " .. i .. " not secure")
    end
    local clear = assert(secure("/cwm 1\n/cwm 2\n/cwm 3\n/cwm 4\n/cwm 5\n/cwm 6\n/cwm 7\n/cwm 8"), "no clear-all button")
    assert(#clear._attr.macrotext <= 255, "macro text too long")
end)
step("toolbar: target icons are secure /tm buttons (SetRaidTarget is forbidden)", function()
    for i = 0, 8 do
        local b = assert(secure("/tm " .. i), "no button for /tm " .. i)
        assert(b._template == "SecureActionButtonTemplate" and b._attr.type == "macro", "/tm " .. i .. " not secure")
    end
end)
step("toolbar: target icon highlight, also with a secret value in combat", function()
    targetIcon = 8
    fire("RAID_TARGET_UPDATE")
    local realIndex = GetRaidTargetIndex
    GetRaidTargetIndex = function() return SECRET end
    fire("RAID_TARGET_UPDATE")
    GetRaidTargetIndex = realIndex
    targetIcon = 0
    fire("PLAYER_TARGET_CHANGED")
end)
step("toolbar: pull, break, ready check, note", function()
    advance(30)
    local rc = readyChecks
    click("RC")
    assert(readyChecks == rc + 1, "no ready check")
    local pull = click("Pull")
    assert(countdowns[#countdowns] == 10, "pull 10")
    shiftDown = true
    scripts[pull].OnClick(pull, "LeftButton")
    shiftDown = false
    assert(countdowns[#countdowns] == 15, "shift pull 15")
    scripts[pull].OnClick(pull, "RightButton")
    assert(countdowns[#countdowns] == 0, "right-click cancels")
    click("Break")
    assert(SRT.Timers.Remaining("break") == 600, "break not started")
    click("Break")
    assert(SRT.Timers.Remaining("break") == nil, "break not ended")
    sent = {}
    local shown = SRT.NoteWindow.IsShown()
    click("Note")
    assert(SRT.NoteWindow.IsShown() ~= shown, "note window not toggled")
    click("Note")
end)
step("toolbar: items, combat waits, only in group, /srt bar", function()
    local realCombat = InCombatLockdown
    InCombatLockdown = function() return true end
    Toolbar.SetItem("marks", false)
    assert(secure("/tm 8")._shown, "changed in combat")
    InCombatLockdown = realCombat
    fire("PLAYER_REGEN_ENABLED")
    assert(not secure("/tm 8")._shown, "not changed after combat")
    Toolbar.SetItem("marks", true)
    -- Rows: groups stay whole and in order; the longest line is as short as possible.
    local g = function(len) return { len = len } end
    local lines = Toolbar.SplitLines({ g(40), g(226), g(226), g(170) }, 2)
    assert(#lines == 2 and #lines[1] == 2 and #lines[2] == 2, "2 rows: open+marks / world+rest")
    lines = Toolbar.SplitLines({ g(40), g(226), g(226), g(170) }, 3)
    assert(#lines == 3 and #lines[1] == 2 and #lines[2] == 1 and #lines[3] == 1, "3 rows")
    assert(#Toolbar.SplitLines({ g(40) }, 3) == 1, "never more lines than groups")
    assert(#Toolbar.SplitLines({}, 2) == 1, "no groups")
    for _, rows in ipairs({ 2, 3, 1 }) do
        Toolbar.Set("rows", rows)
        Toolbar.Set("vertical", true)
        Toolbar.Set("vertical", false)
    end
    Toolbar.Set("vertical", true)
    Toolbar.Set("vertical", false)
    SRT.db.toolbar.onlyInGroup = true
    inRaid = false
    fire("GROUP_ROSTER_UPDATE")
    assert(not Toolbar.IsShown(), "shown outside a group")
    inRaid = true
    fire("GROUP_ROSTER_UPDATE")
    assert(Toolbar.IsShown(), "not shown in the group")
    SRT.db.toolbar.onlyInGroup = false
    SlashCmdList.SLAUGHTERRAIDTOOLS("bar")
    assert(not Toolbar.IsShown(), "/srt bar did not hide")
    SlashCmdList.SLAUGHTERRAIDTOOLS("bar")
    assert(Toolbar.IsShown(), "/srt bar did not show")
    Toolbar.Menu()
    SlashCmdList.SLAUGHTERRAIDTOOLS("")
    click("Toolbar")
end)

-- ---------------------------------------------------------------------------
-- Raid check
-- ---------------------------------------------------------------------------

local RaidCheck = SRT.RaidCheck
local function cellOf(result, name, cat)
    for _, r in ipairs(result.rows) do
        if r.name == name then return r.cells[cat] end
    end
end
step("raid check: auras, blessings, out of range, secret values", function()
    for i, r in ipairs(ROSTER) do r.group = i <= 2 and 1 or 2 end
    auraOverride.raid2 = {
        { name = "Supreme Power", spellId = 17628, expirationTime = now + 3600 },
        { name = "Well Fed", spellId = 24799, expirationTime = now + 900 },
        { name = "Greater Blessing of Kings", spellId = 25898, expirationTime = 0 },
        { name = "Blessing of Might", spellId = 19838, expirationTime = now + 300 },
        { name = SECRET, spellId = SECRET, expirationTime = SECRET },
        { name = "Soulstone Resurrection", spellId = 20707, expirationTime = now + 1800 },
    }
    auraOverride.raid3 = { { name = "Arcane Intellect", spellId = 10157, expirationTime = now + 1500 } }
    auraOverride.raid1 = { { name = "Flask", spellId = 17628, expirationTime = SECRET } }
    invisible.raid4 = true
    local res = RaidCheck.Scan()
    assert(cellOf(res, "Kogosh Boll", "flask").text == "60m", "flask time")
    assert(cellOf(res, "Kogosh Boll", "food").state == "yes", "food")
    assert(cellOf(res, "Kogosh Boll", "bless").text == "Ki Mi", "blessings: " .. cellOf(res, "Kogosh Boll", "bless").text)
    assert(cellOf(res, "Kogosh Boll", "ss").state == "yes", "soulstone")
    assert(cellOf(res, "Whissel Ljud", "flask").state == "no" and cellOf(res, "Whissel Ljud", "int").state == "yes", "Whissel")
    assert(cellOf(res, "Whissel Ljud", "ss").state == "optional", "optional category missing is not 'no'")
    assert(cellOf(res, "Nobody Here", "flask").state == "unknown", "out of range should be unknown")
    assert(cellOf(res, "Allemano Moo", "flask").text == "ok", "secret expiration shown as ok")
    local t = res.totals.flask
    assert(t.have == 2 and t.total == 3, ("flask totals %d/%d"):format(t.have, t.total))
end)
step("raid check: SRT reports for oil and durability", function()
    fire("CHAT_MSG_ADDON", "SRT", "1|RCR|1|1|1|87|1|1800", "RAID", "Kogosh Boll")
    fire("CHAT_MSG_ADDON", "SRT", "1|RCR|1|1|1|40|0|", "RAID", "Whissel Ljud")
    local res = RaidCheck.Last()
    assert(cellOf(res, "Kogosh Boll", "dur").text == "87%" and cellOf(res, "Kogosh Boll", "oil").text == "30m", "Kogosh report")
    assert(cellOf(res, "Whissel Ljud", "dur").state == "no" and cellOf(res, "Whissel Ljud", "oil").state == "no", "Whissel report")
    assert(cellOf(res, "Nobody Here", "oil").state == "unknown", "no SRT = unknown")
end)
step("raid check: ready check opens it, reports go out, answers are shown", function()
    advance(30)
    sent = {}
    SRT.Main.Toggle()
    fire("READY_CHECK", "Allemano Moo", 30)
    assert(SRT.db.window.page == "raidcheck", "raid check did not open for the leader")
    local kinds = {}
    for _, m in ipairs(sent) do kinds[#kinds + 1] = m.text:match("^1|(%u+)|") end
    local k = table.concat(kinds, ",")
    assert(k:find("RCR") and k:find("RCQ"), "sent: " .. k)
    local own = RaidCheck.Last()
    assert(cellOf(own, "Allemano Moo", "dur").text == "50%" and cellOf(own, "Allemano Moo", "oil").text == "20m", "own report")
    assert(cellOf(own, "Allemano Moo", "ready").state == "yes", "initiator is ready")
    fire("READY_CHECK_CONFIRM", "raid2", true)
    fire("READY_CHECK_CONFIRM", "raid3", false)
    local res = RaidCheck.Last()
    assert(cellOf(res, "Kogosh Boll", "ready").state == "yes" and cellOf(res, "Whissel Ljud", "ready").state == "no", "answers")
    sent = {}
    fire("CHAT_MSG_ADDON", "SRT", "1|RCQ|9|1|1|", "RAID", "Kogosh Boll")
    assert(sent[1] and sent[1].text:find("|RCR|.*50|1|1200$"), "no answer to a report request")
    sent = {}
    advance(4)
end)
step("raid check: post missing, only missing, categories", function()
    local before = #chatLines
    RaidCheck.PostMissing()
    advance(3)
    local got = {}
    for i = before + 1, #chatLines do got[#got + 1] = chatLines[i].msg end
    local all = table.concat(got, " | ")
    assert(all:find("Missing Flask %(1%): Whissel"), "post: " .. all)
    assert(not all:find("Soulstone"), "optional category posted")
    SRT.db.raidcheck.onlyMissing = true
    SRT.Main.Refresh()
    SRT.db.raidcheck.onlyMissing = false
    click("Categories")
    click("Add category")
    local cats = RaidCheck.Categories()
    local new = cats[#cats]
    assert(new.custom and new.on, "no custom category")
    new.short, new.name, new.match = "Rune", "Demonic rune", "Demonic Rune, 27869"
    auraOverride.raid3[2] = { name = "Demonic Rune", spellId = 27869, expirationTime = 0 }
    local res = RaidCheck.Scan()
    assert(cellOf(res, "Whissel Ljud", new.id).state == "yes", "custom category not matched")
    RaidCheck.RemoveCategory(new.id)
    assert(#RaidCheck.Categories() == #cats, "not removed")
    RaidCheck.ResetCategories()
    assert(#RaidCheck.Categories() == #RaidCheck.DEFAULTS, "reset")
    click("Check")
    auraOverride.raid1, auraOverride.raid2, auraOverride.raid3, invisible.raid4 = nil, nil, nil, nil
    click("Home")
end)
step("close window", function()
    SlashCmdList.SLAUGHTERRAIDTOOLS("")
    assert(not _G.SlaughterRaidToolsFrame._shown, "window did not close")
end)

step("comm debug toggle", function()
    SlashCmdList.SLAUGHTERRAIDTOOLS("comm debug")
    SRT.Comm.Send("TEST", "x")
    SlashCmdList.SLAUGHTERRAIDTOOLS("comm debug")
end)
step("errors", function() SlashCmdList.SLAUGHTERRAIDTOOLS("errors") end)
step("no addon errors recorded", function()
    assert(#SRT.errors == 0, "recorded: " .. tostring(SRT.errors[1] and SRT.errors[1].msg))
end)

print(#errors == 0 and "ALL OK" or (#errors .. " error(s)"))
os.exit(#errors == 0 and 0 or 1)
