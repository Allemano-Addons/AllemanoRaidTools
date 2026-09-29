-- Timers page: quick pull / break buttons, own timers saved as presets ("Buffs 5 min"),
-- and everything running with its time left and Stop.
local _, ART = ...

local Theme, W = ART.Theme, ART.Widgets
local Main, Timers = ART.Main, ART.Timers

local PAD, ROW_H = 26, 30

local function heading(parent, text)
    local fs = W.Text(parent, -2, "text")
    fs:SetText(strupper(text))
    W.OnAccent(function(r, g, b) fs:SetTextColor(r, g, b) end)
    return fs
end

Main.RegisterPage("timers", function(page)
    local refresh

    -- Quick buttons.
    local quickHead = heading(page, "Pull and break")
    quickHead:SetPoint("TOPLEFT", PAD, -22)
    local quick = {
        { "Pull 10", function() Timers.Pull(10) end }, { "Pull 15", function() Timers.Pull(15) end },
        { "Break 5", function() Timers.Break(5) end }, { "Break 10", function() Timers.Break(10) end },
        { "Break 15", function() Timers.Break(15) end },
    }
    local quickRow = CreateFrame("Frame", nil, page)
    quickRow:SetPoint("TOPLEFT", quickHead, "BOTTOMLEFT", 0, -10)
    quickRow:SetSize(1, 26)
    local prev
    for _, q in ipairs(quick) do
        local b = W.Button(page, q[1], nil, q[2], 26)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", quickRow, "TOPLEFT") end
        prev = b
    end

    -- Own timers.
    local ownHead = heading(page, "Own timers")
    ownHead:SetPoint("TOPLEFT", quickRow, "BOTTOMLEFT", 0, -24)
    local ownHelp = W.Text(page, -2, "textFaint")
    ownHelp:SetPoint("TOPLEFT", ownHead, "BOTTOMLEFT", 0, -6)
    ownHelp:SetText("Click one to start it. As raid leader or assistant it shows for everyone with ART; otherwise only for you.")
    local nameEdit = W.EditBox(page, "Name, e.g. Buffs", 26)
    nameEdit:SetWidth(170)
    nameEdit:SetMaxLetters(30)
    nameEdit:SetPoint("TOPLEFT", ownHelp, "BOTTOMLEFT", 0, -10)
    local minEdit = W.EditBox(page, "Minutes", 26)
    minEdit:SetWidth(80)
    minEdit:SetMaxLetters(5)
    minEdit:SetPoint("LEFT", nameEdit, "RIGHT", 6, 0)
    local add = W.Button(page, "Add", nil, function()
        if Timers.AddPreset(nameEdit:GetText(), minEdit:GetText()) then
            nameEdit:SetText("")
            minEdit:SetText("")
            nameEdit:ClearFocus()
            minEdit:ClearFocus()
            refresh()
        else
            ART:Print("Give the timer a name and the minutes (e.g. Buffs, 5).")
        end
    end, 26)
    add:SetPoint("LEFT", minEdit, "RIGHT", 6, 0)
    minEdit:SetScript("OnEnterPressed", function() add:Click() end)

    local presetBox = CreateFrame("Frame", nil, page)
    presetBox:SetPoint("TOPLEFT", nameEdit, "BOTTOMLEFT", 0, -10)
    presetBox:SetPoint("RIGHT", -PAD, 0)
    presetBox:SetHeight(1)
    local presetButtons = {}

    -- Running.
    local runHead = heading(page, "Running")
    local runEmpty = W.Text(page, 0, "textDim")
    runEmpty:SetText("Nothing running.")
    local runRows = {}
    local function runRow(i)
        if runRows[i] then return runRows[i] end
        local r = CreateFrame("Frame", nil, page)
        r:SetSize(420, ROW_H)
        r.bg = W.Fill(r, "field", 1)
        r.bg:SetAllPoints()
        W.Round(r.bg, Theme.radius.small)
        r.label = W.Text(r, 0, "text")
        r.label:SetPoint("LEFT", 10, 0)
        r.time = W.Text(r, 0, "text")
        r.time:SetPoint("RIGHT", -90, 0)
        r.stop = W.Button(r, "Stop", nil, function() Timers.StopKind(r.kind) end, 22)
        r.stop:SetPoint("RIGHT", -6, 0)
        runRows[i] = r
        return r
    end

    local function refreshRunning()
        local running = Timers.Running()
        for i, t in ipairs(running) do
            local r = runRow(i)
            r.kind = t.kind
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", runHead, "BOTTOMLEFT", 0, -10 - (i - 1) * (ROW_H + 2))
            r.label:SetText(t.label)
            r.time:SetText(Timers.Format(t.left))
            r:Show()
        end
        for i = #running + 1, #runRows do runRows[i]:Hide() end
        runEmpty:ClearAllPoints()
        runEmpty:SetPoint("TOPLEFT", runHead, "BOTTOMLEFT", 0, -10)
        runEmpty:SetShown(#running == 0)
    end

    function refresh()
        -- Presets as buttons, a few per row.
        local list = Timers.Presets()
        local x, y, width = 0, 0, presetBox:GetWidth()
        for i, p in ipairs(list) do
            local b = presetButtons[i]
            if not b then
                b = W.Button(presetBox, "", nil, function(self) Timers.Custom(self.preset.label, self.preset.seconds) end, 26)
                b.del = W.CloseButton(b, function() Timers.RemovePreset(b.index) refresh() end)
                b.del:SetSize(18, 18)
                b.del:SetPoint("TOPRIGHT", 8, 8)
                presetButtons[i] = b
            end
            b.preset, b.index = p, i
            b:SetLabel(("%s  %s"):format(p.label, Timers.Format(p.seconds)))
            if x > 0 and x + b:GetWidth() > width then x, y = 0, y + 34 end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -y)
            b:Show()
            x = x + b:GetWidth() + 14
        end
        for i = #list + 1, #presetButtons do presetButtons[i]:Hide() end
        presetBox:SetHeight(#list > 0 and y + 26 or 1)
        runHead:ClearAllPoints()
        runHead:SetPoint("TOPLEFT", presetBox, "BOTTOMLEFT", 0, -24)
        nameEdit.placeholder:SetShown(nameEdit:GetText() == "" and not nameEdit:HasFocus())
        minEdit.placeholder:SetShown(minEdit:GetText() == "" and not minEdit:HasFocus())
        refreshRunning()
    end

    -- The time left counts down while the page is open.
    local ticker
    page:SetScript("OnShow", function()
        ticker = ticker or C_Timer.NewTicker(1, function() ART:Call("timers page", refreshRunning) end)
    end)
    page:SetScript("OnHide", function()
        if ticker then ticker:Cancel() ticker = nil end
    end)
    page:SetScript("OnSizeChanged", function() if page:IsShown() then refresh() end end)
    return refresh
end)
