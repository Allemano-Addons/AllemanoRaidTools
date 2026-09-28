-- Launcher: a small square button on the screen (like Hush's and AltBoard's) with the SRT
-- mark. Left-click opens SRT, right-click shows or hides the note window, drag to move.
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets

local Launcher = {}
SRT.Launcher = Launcher

local SIZE = 30 -- same as the Hush and AltBoard buttons
local button

local function db() return SRT.db.launcher end

local function build()
    button = CreateFrame("Button", nil, UIParent)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local d = db()
    button:SetPoint(d.point or "RIGHT", UIParent, d.rel or d.point or "RIGHT", d.x or -20, d.y or -120)
    button.bg = W.Fill(button, "window", 0.9)
    button.bg:SetAllPoints()
    button.border = W.Border(button, "line")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 4, -4)
    button.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    if button.icon:SetTexture(SRT.MARK) ~= false then
        W.OnAccent(function(r, g, b) button.icon:SetVertexColor(r, g, b, 1) end)
    else
        W.OnAccent(function(r, g, b) button.icon:SetColorTexture(r, g, b, 1) end)
    end
    button:SetScript("OnDragStart", function(self) if not db().locked then self:StartMoving() end end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint(1)
        d.point, d.rel, d.x, d.y = point, rel, x, y
    end)
    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then SRT.NoteWindow.Toggle() else SRT.Main.Toggle() end
    end)
    button:SetScript("OnEnter", function(self)
        for _, side in pairs(self.border) do side:SetColorTexture(Theme:Accent()) end
        W.ShowTooltip(self, { "SlaughterRaidTools", "Left-click: open / close", "Right-click: note window",
            db().locked and "/srt button hides it" or "Drag to move, /srt button hides it" })
    end)
    button:SetScript("OnLeave", function(self)
        for _, side in pairs(self.border) do side:SetColorTexture(Theme:Color("line")) end
        W.HideTooltip()
    end)
end

function Launcher.Refresh()
    if not SRT.db then return end
    if db().hidden then
        if button then button:Hide() end
        return
    end
    if not button then build() end
    button:Show()
end

function Launcher.IsShown() return button ~= nil and button:IsShown() end

SRT:OnReady(Launcher.Refresh)
SRT:AddSlashCommand("button", function()
    db().hidden = not db().hidden or nil
    Launcher.Refresh()
    SRT:Print(db().hidden and "Launcher button hidden (/srt button shows it)." or "Launcher button shown.")
end, "show or hide the launcher button")
