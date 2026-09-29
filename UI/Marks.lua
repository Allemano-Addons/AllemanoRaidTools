-- Marks page: mouseover marking. Top: Ctrl + mouse wheel, lock, the general icon order.
-- Below: icon lists per mob, grouped by zone (like the TBC marking addons).
local _, ART = ...

local Theme, W = ART.Theme, ART.Widgets
local Main, Marks = ART.Main, ART.Marks

local PAD, ROW_H, SLOT = 26, 30, 24
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

local function iconText(i) return ("|T%s%d:14|t %s"):format(ICON, i, Marks.ICON_NAME[i]) end

Main.RegisterPage("marks", function(page)
    local refresh

    local help = W.Text(page, -1, "textDim")
    help:SetPoint("TOPLEFT", PAD, -18)
    help:SetPoint("RIGHT", -PAD, 0)
    help:SetWordWrap(true)
    help:SetJustifyH("LEFT")
    help:SetText("Hold Ctrl, point at a unit and scroll the mouse wheel one notch: it gets an icon. A mob with a list "
        .. "below gets the next free icon of its list (before the pull); anything else gets the next icon of the order. "
        .. "One notch per unit: the game never lets addons mark by themselves. Key: Key Bindings > AddOns > Allemano Raid Tools.")

    local function toggleRow(anchor, x, label, get, set)
        local t = W.Toggle(page, function(on) set(on) end)
        t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -14)
        local fs = W.Text(page, 0, "text")
        fs:SetPoint("LEFT", t, "RIGHT", 10, 0)
        fs:SetText(label)
        t.refresh = function() t:Set(get()) end
        return t
    end
    local wheel = toggleRow(help, 0, "Ctrl + mouse wheel marks", function() return ART.db.marks.wheel end,
        function(on) ART.db.marks.wheel = on Marks.Apply() end)
    local lock = toggleRow(help, 260, "Lock marks (a marked mob keeps its icon)", function() return ART.db.marks.lock end,
        function(on) ART.db.marks.lock = on Marks.Prepare() end)

    -- General order.
    local orderLabel = W.Text(page, -2, "textDim")
    orderLabel:SetPoint("TOPLEFT", wheel, "BOTTOMLEFT", 0, -16)
    orderLabel:SetText("ORDER (players and mobs without a list) \194\183 click: leave out \194\183 right-click: earlier")
    local icons = {}
    for pos = 1, 8 do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(28, 28)
        b:SetPoint("TOPLEFT", orderLabel, "BOTTOMLEFT", (pos - 1) * 32, -8)
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        W.Round(b.bg, Theme.radius.small)
        b.border = W.Border(b, "line")
        W.Round(b.bg, Theme.radius.small)
        W.RoundBorder(b.border, Theme.radius.small)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 4, -4)
        b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, which)
            if which == "RightButton" then Marks.MoveUp(pos) else Marks.Toggle(self.iconIndex) end
        end)
        b:SetScript("OnEnter", function(self) W.ShowTooltip(self, Marks.ICON_NAME[self.iconIndex]) end)
        b:SetScript("OnLeave", function() W.HideTooltip() end)
        icons[pos] = b
    end
    local startOver = W.Button(page, "Start over", nil, function() Marks.StartOver() end, 24)
    startOver:SetPoint("LEFT", icons[8], "RIGHT", 16, 0)
    startOver.tooltip = "Every list and the order start from their first icon again (also after each fight)."
    local reset = W.Button(page, "Reset order", nil, function() Marks.Reset() end, 24)
    reset:SetPoint("LEFT", startOver, "RIGHT", 6, 0)

    -- Mob lists.
    local mobHead = W.Text(page, -2, "text")
    mobHead:SetPoint("TOPLEFT", icons[1], "BOTTOMLEFT", 0, -20)
    mobHead:SetText("MOB LISTS")
    W.OnAccent(function(r, g, b) mobHead:SetTextColor(r, g, b) end)
    local addTarget = W.Button(page, "Add target", "accent", function() Marks.AddTarget() end, 24)
    addTarget:SetPoint("LEFT", mobHead, "RIGHT", 16, 0)
    addTarget.tooltip = "Target a mob and click: it gets a list in this zone. Then pick its icons."
    local empty = W.Text(page, 0, "textDim")
    empty:SetPoint("TOPLEFT", mobHead, "BOTTOMLEFT", 0, -14)
    empty:SetText("No mobs yet. Target one and click \"Add target\".")

    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", mobHead, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, 16)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(10, 10)
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, body:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * ROW_H * 2)))
    end)

    local zoneHeads, rows = {}, {}
    local function zoneHead(i)
        if zoneHeads[i] then return zoneHeads[i] end
        local fs = W.Text(body, 0, "text")
        zoneHeads[i] = fs
        return fs
    end

    -- Menu of icons for one slot.
    local function pick(zone, name, slot, anchor)
        local items = {}
        for i = 8, 1, -1 do
            items[#items + 1] = { text = iconText(i), onClick = function() Marks.SetSlot(zone, name, slot, i) end }
        end
        items[#items + 1] = { text = "No icon", onClick = function() Marks.SetSlot(zone, name, slot, nil) end }
        W.OpenMenu(items, anchor)
    end

    local function row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, body)
        r:SetHeight(ROW_H)
        r.bg = W.Fill(r, "field", 1)
        r.bg:SetAllPoints()
        W.Round(r.bg, Theme.radius.small)
        r.name = W.Text(r, 0, "text")
        r.name:SetPoint("LEFT", 10, 0)
        r.name:SetWidth(200)
        r.slots = {}
        for s = 1, 8 do
            local b = CreateFrame("Button", nil, r)
            b:SetSize(SLOT, SLOT)
            b:SetPoint("LEFT", 220 + (s - 1) * (SLOT + 4), 0)
            b.bg = W.Fill(b, "window", 1)
            b.bg:SetAllPoints()
            W.Round(b.bg, Theme.radius.small)
            W.RoundBorder(W.Border(b, "line"), Theme.radius.small)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 3, -3)
            b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            b.plus = W.Text(b, 0, "textFaint")
            b.plus:SetPoint("CENTER")
            b.plus:SetText("+")
            b:SetScript("OnClick", function(self) pick(r.zone, r.mob, self.slot, self) end)
            b.slot = s
            r.slots[s] = b
        end
        r.del = W.CloseButton(r, function()
            local zone, name = r.zone, r.mob
            W.Confirm(("Remove the list for %s?"):format(name), "Remove", function() Marks.RemoveMob(zone, name) end)
        end)
        r.del:SetPoint("RIGHT", -4, 0)
        rows[i] = r
        return r
    end

    local function refreshMobs()
        local mobs = ART.db.marks.mobs
        local zones = {}
        for zone in pairs(mobs) do zones[#zones + 1] = zone end
        sort(zones)
        local here = Marks.ZoneKey()
        -- The zone you are in first.
        sort(zones, function(a, b)
            if (a == here) ~= (b == here) then return a == here end
            return a < b
        end)
        local y, nz, nr = 0, 0, 0
        local width = scroll:GetWidth()
        for _, zone in ipairs(zones) do
            nz = nz + 1
            local zh = zoneHead(nz)
            zh:ClearAllPoints()
            zh:SetPoint("TOPLEFT", 0, -(y + 6))
            zh:SetText(zone .. (zone == here and "  |cff7c858f(you are here)|r" or ""))
            zh:Show()
            y = y + 28
            local names = {}
            for name in pairs(mobs[zone]) do names[#names + 1] = name end
            sort(names)
            for _, name in ipairs(names) do
                nr = nr + 1
                local r = row(nr)
                r.zone, r.mob = zone, name
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 0, -y)
                r:SetWidth(width)
                r.bg:SetAlpha(nr % 2 == 0 and 0.6 or 0.3)
                r.name:SetText(name)
                local list = mobs[zone][name]
                for s, b in ipairs(r.slots) do
                    local icon = list[s]
                    -- Filled slots, plus one empty slot to add the next icon.
                    b:SetShown(s <= #list + 1)
                    b.icon:SetShown(icon ~= nil)
                    b.plus:SetShown(icon == nil)
                    if icon then b.icon:SetTexture(ICON .. icon) end
                end
                r:Show()
                y = y + ROW_H + 2
            end
        end
        for i = nz + 1, #zoneHeads do zoneHeads[i]:Hide() end
        for i = nr + 1, #rows do rows[i]:Hide() end
        body:SetSize(width, max(1, y))
        empty:SetShown(nr == 0)
    end

    function refresh()
        wheel.refresh()
        lock.refresh()
        for pos, b in ipairs(icons) do
            local i = ART.db.marks.order[pos]
            b.iconIndex = i
            b.icon:SetTexture(ICON .. i)
            local on = not ART.db.marks.off[i]
            b.icon:SetAlpha(on and 1 or 0.25)
            local r, g, bl
            if on then r, g, bl = Theme:Accent() else r, g, bl = Theme:Color("line") end
            b.border:SetColor(r, g, bl, 1)
        end
        refreshMobs()
    end

    page:SetScript("OnSizeChanged", function() if page:IsShown() then refresh() end end)
    return refresh
end)
