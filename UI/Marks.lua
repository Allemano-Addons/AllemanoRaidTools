-- Marks page: mouseover marking (the icon order and the Ctrl + mouse wheel key). Lists per
-- boss / mob come later.
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets
local Main, Marks = SRT.Main, SRT.Marks

local PAD = 26
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

Main.RegisterPage("marks", function(page)
    local head = W.Text(page, -2, "text")
    head:SetPoint("TOPLEFT", PAD, -24)
    head:SetText("MOUSEOVER MARKING")
    W.OnAccent(function(r, g, b) head:SetTextColor(r, g, b) end)
    local help = W.Text(page, 0, "textDim")
    help:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
    help:SetPoint("RIGHT", -PAD, 0)
    help:SetWordWrap(true)
    help:SetJustifyH("LEFT")
    help:SetText("Hold Ctrl, point at a unit (a mob, or a player in the world or in the raid frames) and scroll the "
        .. "mouse wheel one notch: it gets the next icon of the list. Works in combat. One notch per unit: the game "
        .. "never lets addons mark by themselves. You can also bind a key: Key Bindings > AddOns > SlaughterRaidTools.")

    local wheel = W.Toggle(page, function(on)
        SRT.db.marks.wheel = on
        Marks.Apply()
    end)
    wheel:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -18)
    local wheelLabel = W.Text(page, 0, "text")
    wheelLabel:SetPoint("LEFT", wheel, "RIGHT", 10, 0)
    wheelLabel:SetText("Ctrl + mouse wheel marks")

    local orderLabel = W.Text(page, -1, "textDim")
    orderLabel:SetPoint("TOPLEFT", wheel, "BOTTOMLEFT", 0, -22)
    orderLabel:SetText("Order: click an icon to leave it out or put it back, right-click to move it earlier.")
    local icons = {}
    for pos = 1, 8 do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(34, 34)
        b:SetPoint("TOPLEFT", orderLabel, "BOTTOMLEFT", (pos - 1) * 40, -10)
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        b.border = W.Border(b, "line")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 5, -5)
        b.icon:SetPoint("BOTTOMRIGHT", -5, 5)
        b.num = W.Text(b, -3, "textDim")
        b.num:SetPoint("BOTTOMRIGHT", -2, 2)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, which)
            if which == "RightButton" then Marks.MoveUp(pos) else Marks.Toggle(self.iconIndex) end
        end)
        b:SetScript("OnEnter", function(self)
            W.ShowTooltip(self, { Marks.ICON_NAME[self.iconIndex], "Click: use / leave out", "Right-click: earlier in the order" })
        end)
        b:SetScript("OnLeave", function() W.HideTooltip() end)
        icons[pos] = b
    end

    local startOver = W.Button(page, "Start over", nil, function() Marks.StartOver() end, 26)
    startOver:SetPoint("TOPLEFT", icons[1], "BOTTOMLEFT", 0, -16)
    startOver.tooltip = "The next mark is the first icon again."
    local reset = W.Button(page, "Reset order", nil, function() Marks.Reset() end, 26)
    reset:SetPoint("LEFT", startOver, "RIGHT", 8, 0)

    local later = W.Text(page, -1, "textFaint")
    later:SetPoint("TOPLEFT", startOver, "BOTTOMLEFT", 0, -24)
    later:SetText("Coming later: saved lists per boss and mob (\"Skull, Cross, Moon\"), switched with one click.")

    return function()
        wheel:Set(SRT.db.marks.wheel)
        local n = 0
        for pos, b in ipairs(icons) do
            local i = SRT.db.marks.order[pos]
            b.iconIndex = i
            b.icon:SetTexture(ICON .. i)
            local on = not SRT.db.marks.off[i]
            b.icon:SetAlpha(on and 1 or 0.25)
            if on then n = n + 1 end
            b.num:SetText(on and n or "")
            local r, g, bl
            if on then r, g, bl = Theme:Accent() else r, g, bl = Theme:Color("line") end
            for _, side in pairs(b.border) do side:SetColorTexture(r, g, bl, 1) end
        end
    end
end)
