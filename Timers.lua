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

local function layout()
    local i = 0
    for _, kind in ipairs({ "pull", "break" }) do
        local bar = bars[kind]
        if bar and bar:IsShown() then
            bar:ClearAllPoints()
            bar:SetPoint("TOP", getAnchor(), "TOP", 0, -i * (BAR_H + GAP))
            i = i + 1
        end
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
    local kind, seconds = payload:match("^(%a+)|(%d+)$")
    seconds = tonumber(seconds)
    if kind ~= "pull" and kind ~= "break" then return end
    Timers.Start(kind, seconds, kind == "pull" and "Pull" or "Break")
end)

-- Blizzard's countdown started (by anyone): our own pull bar would be a duplicate.
SRT:RegisterEvent("START_PLAYER_COUNTDOWN", function()
    if active.pull then Timers.Stop("pull") end
end)

SRT:AddSlashCommand("pull", function(arg) Timers.Pull(arg ~= "" and arg or 10) end, "pull countdown (/srt pull 15, /srt pull 0 cancels)")
SRT:AddSlashCommand("break", function(arg) Timers.Break(arg ~= "" and arg or 10) end, "break timer in minutes (/srt break 5, /srt break 0 ends it)")
SRT:AddSlashCommand("rc", Timers.ReadyCheck, "start a ready check")
