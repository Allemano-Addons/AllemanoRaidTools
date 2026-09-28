-- Timers: pull countdown, break timer and ready check for the raid leader, timer bars
-- for everyone. The pull uses Blizzard's own countdown when the client allows it (every
-- raider sees it, SRT or not); breaks are SRT bars plus a raid chat line.
local _, SRT = ...

local W = SRT.Widgets

local Timers = {}
SRT.Timers = Timers

local BAR_W, BAR_H, GAP = 240, 22, 4
local anchor
local bars = {}   -- [kind] = bar frame
local active = {} -- [kind] = { label, total, endsAt (GetTime) }
local ticker

local function fmtTime(s)
    s = max(0, floor(s + 0.5))
    if s >= 60 then return ("%d:%02d"):format(floor(s / 60), s % 60) end
    return tostring(s)
end
Timers.Format = fmtTime

-- ---------------------------------------------------------------------------
-- Bars
-- ---------------------------------------------------------------------------

local function savePosition()
    local _, _, _, x, y = anchor:GetPoint(1)
    SRT.db.timers.x, SRT.db.timers.y = x, y
end

local function getAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(BAR_W, BAR_H)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    local t = SRT.db.timers
    anchor:SetPoint("TOP", UIParent, "TOP", t.x or 0, t.y or -180)
    return anchor
end

-- Pull first, then break, then own timers by the time they end.
local function layout()
    local order = {}
    for kind in pairs(active) do order[#order + 1] = kind end
    local rank = { pull = 1, ["break"] = 2 }
    sort(order, function(a, b)
        local ra, rb = rank[a] or 3, rank[b] or 3
        if ra ~= rb then return ra < rb end
        return active[a].endsAt < active[b].endsAt
    end)
    for i, kind in ipairs(order) do
        local bar = bars[kind]
        bar:ClearAllPoints()
        bar:SetPoint("TOP", getAnchor(), "TOP", 0, -(i - 1) * (BAR_H + GAP))
    end
end

local function createBar(kind)
    local bar = CreateFrame("Frame", nil, getAnchor())
    bar:SetSize(BAR_W, BAR_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() anchor:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        savePosition()
    end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Timers.Stop(kind) end
    end)
    bar:SetScript("OnEnter", function(self) W.ShowTooltip(self, { active[kind] and active[kind].label or "", "Drag to move, right-click to hide." }) end)
    bar:SetScript("OnLeave", function() W.HideTooltip() end)
    bar.bg = W.Fill(bar, "window", 0.9)
    bar.bg:SetAllPoints()
    W.Border(bar, "line")
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    W.OnAccent(function(r, g, b) bar.fill:SetColorTexture(r, g, b, 0.55) end)
    bar.label = W.Text(bar, 0, "text")
    bar.label:SetPoint("LEFT", 8, 0)
    bar.time = W.Text(bar, 0, "text")
    bar.time:SetPoint("RIGHT", -8, 0)
    bars[kind] = bar
    return bar
end

local function update()
    local now = GetTime()
    local any = false
    for kind, t in pairs(active) do
        local left = t.endsAt - now
        local bar = bars[kind]
        if left <= 0 then
            Timers.Stop(kind)
        else
            any = true
            bar.time:SetText(fmtTime(left))
            bar.fill:SetWidth(max(1, (BAR_W - 2) * min(1, left / t.total)))
        end
    end
    if not any and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Shows a bar locally. kind = "pull" or "break".
function Timers.Start(kind, seconds, label, total)
    if seconds <= 0 then return Timers.Stop(kind) end
    active[kind] = { label = label, total = total or seconds, endsAt = GetTime() + seconds }
    SRT.db.timers.running = SRT.db.timers.running or {}
    SRT.db.timers.running[kind] = { label = label, total = total or seconds, ends = GetServerTime() + seconds }
    local bar = bars[kind] or createBar(kind)
    bar.label:SetText(label)
    bar:Show()
    layout()
    update()
    if not ticker then ticker = C_Timer.NewTicker(0.1, function() SRT:Call("timers", update) end) end
    if SRT.Main then SRT.Main.Refresh() end
    if SRT.Toolbar then SRT.Toolbar.Refresh() end
end

function Timers.Stop(kind)
    active[kind] = nil
    if SRT.db.timers.running then SRT.db.timers.running[kind] = nil end
    if bars[kind] then bars[kind]:Hide() end
    layout()
    if SRT.Main then SRT.Main.Refresh() end
    if SRT.Toolbar then SRT.Toolbar.Refresh() end
end

-- Seconds left, nil when not running.
function Timers.Remaining(kind)
    local t = active[kind]
    return t and max(0, t.endsAt - GetTime()) or nil
end

-- A break survives /reload (the pull is too short to matter).
SRT:OnReady(function()
    local running = SRT.db.timers.running
    if not running then return end
    for kind, t in pairs(running) do
        local left = (t.ends or 0) - GetServerTime()
        if left > 1 then Timers.Start(kind, left, t.label, t.total) else running[kind] = nil end
    end
end)

-- ---------------------------------------------------------------------------
-- Leader actions
-- ---------------------------------------------------------------------------

-- In a group only the leader and assistants may start timers; solo is allowed for testing.
function Timers.CanLead()
    return not IsInGroup() or SRT.Compat.IsLeaderOrAssist()
end

local function refuse()
    SRT:Print("Only the raid leader or an assistant can do that.")
end

function Timers.ReadyCheck()
    if not Timers.CanLead() then return refuse() end
    if not IsInGroup() then SRT:Print("You are not in a group.") return end
    if not SRT.Compat.DoReadyCheck() then SRT:Print("The game refused the ready check.") end
end

function Timers.Pull(seconds)
    if not Timers.CanLead() then return refuse() end
    seconds = floor(tonumber(seconds) or 10)
    if SRT.Compat.DoCountdown(seconds) then
        Timers.native = true
        return
    end
    -- No Blizzard countdown: SRT bars for SRT users, a chat line for everyone else.
    Timers.native = false
    Timers.Start("pull", seconds, "Pull")
    SRT.Comm.Send("TIMER", ("pull|%d"):format(seconds))
    local channel = SRT.Compat.GroupChatChannel()
    if channel and seconds > 0 then SRT.Compat.SendChat(("Pull in %d"):format(seconds), channel) end
end

function Timers.Break(minutes)
    if not Timers.CanLead() then return refuse() end
    minutes = tonumber(minutes) or 10
    local seconds = floor(minutes * 60)
    Timers.Start("break", seconds, "Break")
    SRT.Comm.Send("TIMER", ("break|%d"):format(seconds))
    local channel = SRT.Compat.GroupChatChannel()
    if channel and SRT.db.settings.announceBreak then
        if seconds > 0 then
            SRT.Compat.SendChat(("Break %s min, back at %s"):format(minutes, date("%H:%M", time() + seconds)), channel)
        else
            SRT.Compat.SendChat("Break is over", channel)
        end
    end
end

SRT.Comm.Register("TIMER", function(sender, payload)
    local unit = SRT.Compat.UnitForName(sender)
    if not unit or not SRT.Compat.IsLeaderOrAssist(unit) then return end
    -- Own timers: "c|seconds|label".
    local cs, label = payload:match("^c|(%d+)|(.+)$")
    if cs then
        Timers.Start("c:" .. label, tonumber(cs), label)
        return
    end
    local kind, seconds = payload:match("^(%a+)|(%d+)$")
    seconds = tonumber(seconds)
    if kind ~= "pull" and kind ~= "break" then return end
    Timers.Start(kind, seconds, kind == "pull" and "Pull" or "Break")
end)

-- ---------------------------------------------------------------------------
-- Own timers ("Buffs 5 min"): saved as presets, started for yourself or, as leader or
-- assistant in a group, for everyone with SRT.
-- ---------------------------------------------------------------------------

local function cleanLabel(label) return (strtrim(label or ""):gsub("|", ""):sub(1, 30)) end

-- Starts (seconds > 0) or stops (0) an own timer; shared when you may lead a group.
function Timers.Custom(label, seconds)
    label = cleanLabel(label)
    if label == "" then return false end
    seconds = floor(tonumber(seconds) or 0)
    local kind = "c:" .. label
    if seconds > 0 then Timers.Start(kind, seconds, label) else Timers.Stop(kind) end
    if IsInGroup() and SRT.Compat.IsLeaderOrAssist() then
        SRT.Comm.Send("TIMER", ("c|%d|%s"):format(max(0, seconds), label))
    end
    return true
end

-- Running timers: { { kind, label, left } }, pull and break first.
function Timers.Running()
    local out = {}
    for kind, t in pairs(active) do
        out[#out + 1] = { kind = kind, label = t.label, left = max(0, t.endsAt - GetTime()) }
    end
    sort(out, function(a, b) return a.left < b.left end)
    return out
end

-- Stops any running timer by kind (own timers are stopped for the group too).
function Timers.StopKind(kind)
    if kind:sub(1, 2) == "c:" then
        Timers.Custom(kind:sub(3), 0)
    elseif kind == "break" then
        Timers.Break(0)
    elseif kind == "pull" then
        Timers.Pull(0)
    else
        Timers.Stop(kind)
    end
end

function Timers.Presets() return SRT.db.timers.presets end

function Timers.AddPreset(label, minutes)
    label, minutes = cleanLabel(label), tonumber(minutes)
    if label == "" or not minutes or minutes <= 0 then return false end
    local list = SRT.db.timers.presets
    for _, p in ipairs(list) do
        if p.label == label then p.seconds = floor(minutes * 60) return true end
    end
    list[#list + 1] = { label = label, seconds = floor(minutes * 60) }
    return true
end

function Timers.RemovePreset(i)
    tremove(SRT.db.timers.presets, i)
end

-- Blizzard's countdown started (by anyone): our own pull bar would be a duplicate.
SRT:RegisterEvent("START_PLAYER_COUNTDOWN", function()
    if active.pull then Timers.Stop("pull") end
end)

SRT:AddSlashCommand("pull", function(arg) Timers.Pull(arg ~= "" and arg or 10) end, "pull countdown (/srt pull 15, /srt pull 0 cancels)")
SRT:AddSlashCommand("break", function(arg) Timers.Break(arg ~= "" and arg or 10) end, "break timer in minutes (/srt break 5, /srt break 0 ends it)")
SRT:AddSlashCommand("rc", Timers.ReadyCheck, "start a ready check")
