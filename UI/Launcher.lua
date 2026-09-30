-- Launcher: a small square button on the screen (like Hush's and AltBoard's) with the ART
-- mark. Left-click opens ART, right-click shows or hides the note window, drag to move.
local _, ART = ...

local Theme, W = ART.Theme, ART.Widgets

local Launcher = {}
ART.Launcher = Launcher

local SIZE = 30 -- same as the Hush and AltBoard buttons
local button

local function db() return ART.db.launcher end

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
    W.Panel(button, button.bg, button.border, Theme.radius.control)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    -- The ART mark in its own colors (an accent square if the file does not load).
    if button.icon:SetTexture(ART.MARK) == false then
        W.OnAccent(function(r, g, b) button.icon:SetColorTexture(r, g, b, 1) end)
    end
    button:SetScript("OnDragStart", function(self) if not db().locked then self:StartMoving() end end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint(1)
        d.point, d.rel, d.x, d.y = point, rel, x, y
    end)
    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then ART.NoteWindow.Toggle() else ART.Main.Toggle() end
    end)
    button:SetScript("OnEnter", function(self)
        self.border:SetColor(Theme:Accent())
        W.ShowTooltip(self, { "Allemano Raid Tools", "Left-click: open / close", "Right-click: note window",
            db().locked and "/art button hides it" or "Drag to move, /art button hides it" })
    end)
    button:SetScript("OnLeave", function(self)
        self.border:SetColor(Theme:Color("line"))
        W.HideTooltip()
    end)
end

function Launcher.Refresh()
    if not ART.db then return end
    if db().hidden then
        if button then button:Hide() end
        return
    end
    if not button then build() end
    button:Show()
end

function Launcher.IsShown() return button ~= nil and button:IsShown() end

ART:OnReady(Launcher.Refresh)
ART:AddSlashCommand("button", function()
    db().hidden = not db().hidden or nil
    Launcher.Refresh()
    ART:Print(db().hidden and "Launcher button hidden (/art button shows it)." or "Launcher button shown.")
end, "show or hide the launcher button")
