-- Smoke test outside the game: loads every TOC file against a fake WoW API, fires the
-- login events and runs the slash commands. Addon messages loop back as if they came
-- from another raider. Catches Lua errors that WoW Forever would swallow silently.
-- Run from the addon folder: lua Tests/smoke_test.lua
local unpack = table.unpack or unpack
_G.unpack = unpack

local scripts = {} -- strong: real frames are kept alive by their parent, mocks are not
local function mock(kind)
    local o = { _kind = kind, _shown = true }
    return setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end -- fields: nil, like real frames
        if k == "SetScript" then return function(self, name, fn) scripts[self] = scripts[self] or {}; scripts[self][name] = fn end end
        if k == "RegisterEvent" then return function(_, e) if e:match("^FAKE") then error("unknown event") end end end
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
CreateFrame = function(kind, name) local f = mock(kind); if name then _G[name] = f end; return f end
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
IsInGroup = function(cat) return inRaid and cat ~= 2 end
GetNumGroupMembers = function() return inRaid and #ROSTER or 0 end
GetNumSubgroupMembers = function() return 0 end
GetRaidRosterInfo = function(i) return ROSTER[i] and ROSTER[i][1] end
UnitIsConnected = function() return true end
UnitIsGroupLeader = function(u) return u == "player" end
UnitIsGroupAssistant = function() return false end

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
step("help", function() SlashCmdList.SLAUGHTERRAIDTOOLS("") assert(chatHas("/srt version")) end)
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
