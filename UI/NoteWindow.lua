-- Note window: the raid note (and the personal note below it) for everyone. A HUD-like
-- window: it stays open through ESC, can be moved, resized and locked in place.
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets

local NoteWindow = {}
SRT.NoteWindow = NoteWindow

local TITLE_H, PAD = 24, 10
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 80, 900, 900
local frame

local function saved() return SRT.db.noteWindow end

local function savePosition()
    local point, _, rel, x, y = frame:GetPoint(1)
    local s = saved()
    s.point, s.rel, s.x, s.y = point, rel, x, y
    s.w, s.h = floor(frame:GetWidth() + 0.5), floor(frame:GetHeight() + 0.5)
end

local function layout()
    if not frame then return end
    local width = max(40, frame.scroll:GetWidth() - 4)
    local raid, personal = frame.raidText, frame.personalText
    raid:SetWidth(width)
    personal:SetWidth(width)
    local h = raid:GetStringHeight()
    personal:ClearAllPoints()
    if personal:IsShown() then
        frame.divider:ClearAllPoints()
        frame.divider:SetPoint("TOPLEFT", raid, "BOTTOMLEFT", 0, -8)
        frame.divider:SetWidth(width)
        frame.divider:Show()
        personal:SetPoint("TOPLEFT", frame.divider, "BOTTOMLEFT", 0, -8)
        h = h + 17 + personal:GetStringHeight()
    else
        frame.divider:Hide()
    end
    frame.child:SetSize(width, max(1, h))
end

function NoteWindow.Refresh()
    if not frame then return end
    local a = SRT.Notes.Active()
    if a then
        frame.title:SetText(a.title ~= "" and a.title or "Note")
        frame.raidText:SetText(SRT.Notes.Render(a.text))
        frame.from = ("From %s, %s"):format(a.sender or "?", date("%H:%M", a.at or time()))
    else
        frame.title:SetText("Note")
        frame.raidText:SetText("|cff7c858fNo raid note yet. The raid leader sends it from SRT.|r")
        frame.from = nil
    end
    local personal = SRT.db.settings.notePersonal and SRT.Notes.Personal() or ""
    frame.personalText:SetShown(personal ~= "")
    frame.personalText:SetText(personal ~= "" and SRT.Notes.Render(personal) or "")
    layout()
end

-- Background opacity (settings.noteAlpha, 0 = fully see-through). The border and title
-- line fade with it; the text always stays readable.
local function applyAlpha()
    local a = SRT.db.settings.noteAlpha or 0.85
    frame.bg:SetAlpha(a)
    for _, line in ipairs(frame.lines) do line:SetAlpha(a) end
end

local function applyLock()
    local locked = saved().locked
    frame.grip:SetShown(not locked)
    frame.lock.text:SetText(locked and "unlock" or "lock")
end

local function smallButton(parent, label, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(TITLE_H)
    b.text = W.Text(b, -2, "textDim")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(max(18, b.text:GetStringWidth() + 10))
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(Theme:Color("text"))
        W.ShowTooltip(self, tooltip)
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(Theme:Color("textDim"))
        W.HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function build()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_W, MIN_H)
        frame:SetMaxResize(MAX_W, MAX_H)
    end
    local s = saved()
    frame:SetSize(s.w or 300, s.h or 240)
    if s.point then
        frame:SetPoint(s.point, UIParent, s.rel or s.point, s.x or 0, s.y or 0)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    end
    frame.bg = W.Fill(frame, "window", 1)
    frame.bg:SetAllPoints()
    frame.lines = {}
    for _, side in pairs(W.Border(frame, "line")) do frame.lines[#frame.lines + 1] = side end

    -- Title bar: drag to move (unless locked), lock and close.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(TITLE_H)
    frame.lines[#frame.lines + 1] = W.Line(bar, "bottom", "line")
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() if not saved().locked then frame:StartMoving() end end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    bar:SetScript("OnEnter", function(self) if frame.from then W.ShowTooltip(self, frame.from) end end)
    bar:SetScript("OnLeave", function() W.HideTooltip() end)
    local square = bar:CreateTexture(nil, "ARTWORK")
    square:SetSize(6, 6)
    square:SetPoint("LEFT", PAD, 0)
    W.OnAccent(function(r, g, b) square:SetColorTexture(r, g, b, 1) end)
    frame.title = W.Text(bar, -1, "text")
    frame.title:SetPoint("LEFT", square, "RIGHT", 6, 0)
    frame.title:SetPoint("RIGHT", -70, 0)
    local close = smallButton(bar, "x", "Hide the note (/srt note shows it again)", function() NoteWindow.Hide() end)
    close:SetPoint("RIGHT", -4, 0)
    frame.lock = smallButton(bar, "lock", "Lock or unlock position and size", function()
        saved().locked = not saved().locked or nil
        applyLock()
    end)
    frame.lock:SetPoint("RIGHT", close, "LEFT", -2, 0)
    frame.lock:SetWidth(46)

    -- Scrolling body.
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", PAD, -(TITLE_H + 8))
    scroll:SetPoint("BOTTOMRIGHT", -PAD, 8)
    frame.scroll = scroll
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    frame.child = child
    frame.raidText = W.Text(child, 0, "text")
    frame.raidText:SetWordWrap(true)
    frame.raidText:SetJustifyV("TOP")
    frame.raidText:SetSpacing(3)
    frame.raidText:SetPoint("TOPLEFT")
    frame.divider = W.Fill(child, "line", 1, "ARTWORK")
    frame.divider:SetHeight(1)
    frame.personalText = W.Text(child, 0, "text")
    frame.personalText:SetWordWrap(true)
    frame.personalText:SetJustifyV("TOP")
    frame.personalText:SetSpacing(3)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * 30)))
    end)

    -- Resize grip.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    for _, d in ipairs({ { 9, 1 }, { 5, 5 }, { 9, 5 }, { 1, 9 }, { 5, 9 }, { 9, 9 } }) do
        local t = grip:CreateTexture(nil, "OVERLAY")
        t:SetSize(2, 2)
        t:SetPoint("TOPLEFT", d[1], -d[2])
        t:SetColorTexture(Theme:Color("textFaint"))
    end
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePosition()
        layout()
    end)
    frame.grip = grip
    frame:SetScript("OnSizeChanged", function() SRT:Call("note layout", layout) end)
    applyLock()
    applyAlpha()
    frame:Hide()
end

local function ensure()
    if not frame then build() end
    return frame
end

function NoteWindow.Show()
    ensure()
    saved().shown = true
    frame:Show()
    NoteWindow.Refresh()
    if SRT.Toolbar then SRT.Toolbar.Refresh() end
end

function NoteWindow.Hide()
    saved().shown = nil
    if frame then frame:Hide() end
    if SRT.Toolbar then SRT.Toolbar.Refresh() end
end

function NoteWindow.Toggle()
    if frame and frame:IsShown() then NoteWindow.Hide() else NoteWindow.Show() end
end

function NoteWindow.IsShown() return frame ~= nil and frame:IsShown() end

SRT.Notes.OnChange(function() if frame and frame:IsShown() then NoteWindow.Refresh() end end)
SRT:OnSettingChanged(function(key)
    if key == "notePersonal" or key == "accent" or key == "useClassColor" then NoteWindow.Refresh() end
    if key == "noteAlpha" and frame then applyAlpha() end
end)
SRT:OnReady(function() if saved().shown then NoteWindow.Show() end end)

SRT:AddSlashCommand("note", function() NoteWindow.Toggle() end, "show or hide the note window")
