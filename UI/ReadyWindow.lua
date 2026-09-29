-- Ready check window: opens with a ready check (instead of the main window) and shows the
-- group's consumables as the buffs' own icons, with the ready check timer in the title.
-- It closes itself after the check (8 s when everyone was ready, adjustable; 15 s otherwise),
-- never while the mouse is over it.
local _, ART = ...

local Theme, W = ART.Theme, ART.Widgets
local RaidCheck = ART.RaidCheck

local ReadyWindow = {}
ART.ReadyWindow = ReadyWindow

local TITLE_H, HEAD_H, ROW_H, NAME_W, PAD = 24, 30, 20, 120, 8
local MAX_ROWS = 25
local CLOSE_ALL_READY, CLOSE_NOT_READY = 8, 15 -- seconds (all ready: settings.closeAfter)
local COL_W = { aura = 26, weapon = 34, durability = 38, blessings = 56 }
local READY_ICON = {
    yes = "Interface\\RaidFrame\\ReadyCheck-Ready",
    no = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    unknown = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

local frame, ticker
local endsAt, finished, closeToken = 0, nil, 0
local rows, heads = {}, {}

local function saved() return ART.db.raidcheck.window end

local function columns()
    local out = {}
    for _, c in ipairs(RaidCheck.Enabled()) do
        if c.kind ~= "ready" then out[#out + 1] = c end
    end
    return out
end

local function colWidth(c) return COL_W[c.kind or "aura"] or COL_W.aura end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function build()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame.bg = W.Fill(frame, "window", 0.95)
    frame.bg:SetAllPoints()
    W.Panel(frame, frame.bg, W.Border(frame, "line"))
    local s = saved()
    frame:SetPoint(s.point or "CENTER", UIParent, s.rel or s.point or "CENTER", s.x or 0, s.y or 120)

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(TITLE_H)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    W.OnAccent(function(r, g, b) bar.bg:SetColorTexture(r, g, b, 0.9) end)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, rel, x, y = frame:GetPoint(1)
        s.point, s.rel, s.x, s.y = point, rel, x, y
    end)
    frame.title = W.Text(bar, 0, "text")
    frame.title:SetPoint("CENTER")
    frame.title:SetTextColor(Theme:Color("sidebar"))
    local close = W.CloseButton(bar, function() ReadyWindow.Hide() end)
    close:SetPoint("RIGHT", -2, 0)
    close.text:SetTextColor(Theme:Color("sidebar"))
    local details = CreateFrame("Button", nil, bar)
    details:SetSize(52, TITLE_H)
    details:SetPoint("LEFT", 6, 0)
    details.text = W.Text(details, -2, "text")
    details.text:SetPoint("LEFT")
    details.text:SetText("Details")
    details.text:SetTextColor(Theme:Color("sidebar"))
    details:SetScript("OnClick", function() ART.Main.Toggle("raidcheck") end)
    details:SetScript("OnEnter", function(self) W.ShowTooltip(self, "Open the raid check page (post missing, categories)") end)
    details:SetScript("OnLeave", function() W.HideTooltip() end)

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", PAD, -TITLE_H)
    frame.header:SetHeight(HEAD_H)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", PAD, -(TITLE_H + HEAD_H))
    scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    frame.body = CreateFrame("Frame", nil, scroll)
    frame.body:SetSize(10, 10)
    scroll:SetScrollChild(frame.body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, frame.body:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * ROW_H * 3)))
    end)
    frame.scroll = scroll
    frame:Hide()
end

local function head(i)
    if heads[i] then return heads[i] end
    local fs = W.Text(frame.header, -3, "textDim")
    fs:SetJustifyH("CENTER")
    heads[i] = fs
    return fs
end

local function cellFrame(r, i)
    if r.cells[i] then return r.cells[i] end
    local c = CreateFrame("Button", nil, r)
    c:SetHeight(ROW_H)
    c.icons = {}
    for k = 1, 3 do
        local t = c:CreateTexture(nil, "ARTWORK")
        t:SetSize(16, 16)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.icons[k] = t
    end
    c.text = W.Text(c, -2, "text")
    c.text:SetPoint("CENTER")
    c.strip = c:CreateTexture(nil, "OVERLAY")
    c.strip:SetPoint("BOTTOMLEFT", 4, 0)
    c.strip:SetPoint("BOTTOMRIGHT", -4, 0)
    c.strip:SetHeight(2)
    c.strip:SetColorTexture(Theme:Color("warn"))
    c:SetScript("OnEnter", function(self) RaidCheck.ShowCellTooltip(self, self.row, self.cat, self.cell) end)
    c:SetScript("OnLeave", function() RaidCheck.HideCellTooltip() end)
    r.cells[i] = c
    return c
end

local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, frame.body)
    r:SetHeight(ROW_H)
    r.bg = W.Fill(r, "field", 1)
    r.bg:SetAllPoints()
    W.Round(r.bg, Theme.radius.small)
    r.ready = r:CreateTexture(nil, "ARTWORK")
    r.ready:SetSize(14, 14)
    r.ready:SetPoint("LEFT", 2, 0)
    r.name = W.Text(r, -1, "text")
    r.name:SetPoint("LEFT", 20, 0)
    r.name:SetWidth(NAME_W - 22)
    r.cells = {}
    rows[i] = r
    return r
end

-- One cell: buff icon(s), text (durability, oil minutes) or a red x / ? when missing.
local function paintCell(c, cat, cell)
    for _, t in ipairs(c.icons) do t:Hide() end
    c.text:SetText("")
    c.strip:Hide()
    if not cell then return end
    local kind = cat.kind or "aura"
    if cell.state == "unknown" then
        c.text:SetText(cell.text == "off" and "" or "?")
        c.text:SetTextColor(Theme:Color("textFaint"))
    elseif cell.state == "no" or cell.state == "optional" then
        c.text:SetText(cell.state == "no" and "x" or "")
        c.text:SetTextColor(Theme:Color("bad"))
    elseif kind == "blessings" then
        local list = cell.auras or {}
        local w = min(#list, 3) * 17
        for k, a in ipairs(list) do
            local t = c.icons[k]
            if not t then break end
            t:ClearAllPoints()
            t:SetPoint("LEFT", c, "CENTER", -w / 2 + (k - 1) * 17, 0)
            t:SetTexture(a.icon)
            t:Show()
        end
    elseif cell.aura and cell.aura.icon then
        local t = c.icons[1]
        t:ClearAllPoints()
        t:SetPoint("CENTER")
        t:SetTexture(cell.aura.icon)
        t:Show()
        c.strip:SetShown(cell.state == "low")
    else
        c.text:SetText(cell.text)
        c.text:SetTextColor(Theme:Color(cell.state == "low" and "warn" or "text"))
    end
end

function ReadyWindow.Refresh()
    if not frame or not frame:IsShown() then return end
    local result = RaidCheck.Last()
    local cols = columns()
    local width = NAME_W
    for i, c in ipairs(cols) do
        local fs = head(i)
        local w = colWidth(c)
        fs:ClearAllPoints()
        -- Staggered on two lines so short names fit narrow columns.
        fs:SetPoint("TOP", frame.header, "TOPLEFT", width + w / 2, i % 2 == 1 and -2 or -15)
        fs:SetWidth(w + 30)
        fs:SetText(c.short or c.id)
        fs:Show()
        width = width + w
    end
    for i = #cols + 1, #heads do heads[i]:Hide() end
    frame.header:SetWidth(width)

    local list = result and result.rows or {}
    local readyCat
    for _, c in ipairs(RaidCheck.Enabled()) do if c.kind == "ready" then readyCat = c end end
    for i, data in ipairs(list) do
        local r = row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetSize(width, ROW_H)
        r.bg:SetAlpha(i % 2 == 0 and 0.7 or 0.3)
        r.name:SetText(data.name:match("^(%S+)") or data.name)
        local cr, cg, cb = Theme.ClassColor(data.classFile)
        if cr then r.name:SetTextColor(cr, cg, cb) else r.name:SetTextColor(Theme:Color("text")) end
        local rc = readyCat and data.cells[readyCat.id]
        local state = rc and rc.state or "unknown"
        r.ready:SetTexture(READY_ICON[state] or READY_ICON.unknown)
        r.ready:SetShown(readyCat ~= nil)
        local x = NAME_W
        for k, c in ipairs(cols) do
            local cell = cellFrame(r, k)
            local w = colWidth(c)
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", x, 0)
            cell:SetWidth(w)
            cell.row, cell.cat, cell.cell = data, c, data.cells[c.id]
            paintCell(cell, c, cell.cell)
            cell:Show()
            x = x + w
        end
        for k = #cols + 1, #r.cells do r.cells[k]:Hide() end
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    frame.body:SetSize(width, max(1, #list * ROW_H))
    local visible = min(#list, MAX_ROWS)
    frame:SetSize(width + PAD * 2, TITLE_H + HEAD_H + max(1, visible) * ROW_H + PAD)
end

local function updateTitle()
    local left = endsAt - GetTime()
    -- Opened without a real ready check (/art rcwindow): finish when the timer runs out.
    if finished == nil and left <= 0 and not RaidCheck.running then ReadyWindow.Finish(RaidCheck.AllReady()) end
    if finished ~= nil then
        frame.title:SetText(finished and "ART: Everyone is ready" or "ART: Ready check done")
    else
        frame.title:SetText(("ART: Ready Check (%d s)"):format(max(0, floor(left + 0.5))))
    end
end

function ReadyWindow.Start(seconds)
    if not frame then build() end
    closeToken = closeToken + 1
    endsAt = GetTime() + (seconds or 30)
    finished = nil
    frame:Show()
    ReadyWindow.Refresh()
    updateTitle()
    if not ticker then ticker = C_Timer.NewTicker(0.2, function() ART:Call("ready window", updateTitle) end) end
end

-- The check ended: close soon (sooner when everyone was ready), but never while the
-- mouse is over the window.
function ReadyWindow.Finish(allReady)
    if not frame or not frame:IsShown() then return end
    finished = allReady and true or false
    updateTitle()
    closeToken = closeToken + 1
    local token = closeToken
    local function tryClose()
        if token ~= closeToken then return end
        if frame:IsMouseOver() then
            C_Timer.After(1, tryClose)
        else
            ReadyWindow.Hide()
        end
    end
    C_Timer.After(allReady and (ART.db.raidcheck.closeAfter or CLOSE_ALL_READY) or CLOSE_NOT_READY, tryClose)
end

function ReadyWindow.Hide()
    closeToken = closeToken + 1
    if frame then frame:Hide() end
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    RaidCheck.HideCellTooltip()
end

function ReadyWindow.IsShown() return frame ~= nil and frame:IsShown() end
function ReadyWindow.Frame() return frame end

RaidCheck.OnChange(ReadyWindow.Refresh)

-- /art rcwindow: open the window without a ready check (to look at the layout).
ART:AddSlashCommand("rcwindow", function()
    RaidCheck.Refresh()
    ReadyWindow.Start(30)
end, "show the ready check window (test)")
