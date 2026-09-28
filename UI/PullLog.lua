-- Pull log page: one raid night at a time. A summary per boss (pulls, kills, best wipe, kill
-- time, time in combat) and every pull with its time, combat time and result.
local _, SRT = ...

local W = SRT.Widgets
local Main, PullLog = SRT.Main, SRT.PullLog

local PAD, ROW_H = 26, 20

local function label(parent, text, delta, color)
    local fs = W.Text(parent, delta or 0, color or "text")
    fs:SetText(text or "")
    return fs
end

-- "2026-09-28" -> "Mon 28 Sep"
local function nightLabel(night)
    local y, m, d = (night or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return night or "" end
    return date("%a %d %b", time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
end
PullLog.NightLabel = nightLabel

local function resultText(p)
    if p.kill then return "|cff3fc77fKill|r" end
    return "|cffe0564fWipe|r" .. (p.pct and ("  |cffe6e8eb%.1f%%|r"):format(p.pct) or "  |cff7c858f?|r")
end
PullLog.ResultText = resultText

-- A simple table: columns = { { title, width, justify } }, rows filled by `fill`.
local function makeTable(parent, columns)
    local t = CreateFrame("Frame", nil, parent)
    t.head = CreateFrame("Frame", nil, t)
    t.head:SetPoint("TOPLEFT")
    t.head:SetPoint("TOPRIGHT")
    t.head:SetHeight(ROW_H)
    W.Line(t.head, "bottom", "line")
    local x = 0
    for _, c in ipairs(columns) do
        local fs = label(t.head, strupper(c[1]), -3, "textDim")
        fs:SetPoint("LEFT", x + 6, 0)
        fs:SetWidth(c[2] - 8)
        fs:SetJustifyH(c[3] or "LEFT")
        x = x + c[2]
    end
    t.width = x
    t.rows = {}
    function t:Row(i)
        if self.rows[i] then return self.rows[i] end
        local r = CreateFrame("Frame", nil, self.body or self)
        r:SetHeight(ROW_H)
        r.bg = W.Fill(r, "field", 1)
        r.bg:SetAllPoints()
        r.cells = {}
        local cx = 0
        for k, c in ipairs(columns) do
            local fs = label(r, "", -1, "text")
            fs:SetPoint("LEFT", cx + 6, 0)
            fs:SetWidth(c[2] - 8)
            fs:SetJustifyH(c[3] or "LEFT")
            r.cells[k] = fs
            cx = cx + c[2]
        end
        self.rows[i] = r
        return r
    end
    return t
end

Main.RegisterPage("pulllog", function(page)
    local night -- shown night; nil = the newest
    local refresh

    local nightDrop = W.Dropdown(page, 180, function()
        local opts = {}
        for _, n in ipairs(PullLog.Nights()) do opts[#opts + 1] = { value = n, label = nightLabel(n) } end
        return opts
    end, function(v)
        night = v
        refresh()
    end)
    nightDrop:SetPoint("TOPLEFT", PAD, -20)
    local delete = W.Button(page, "Delete night", nil, function()
        local _, n = PullLog.Pulls(night)
        if not n then return end
        W.Confirm(("Delete every pull of %s?"):format(nightLabel(n)), "Delete", function()
            PullLog.DeleteNight(n)
            night = nil
        end)
    end, 26)
    delete:SetPoint("TOPRIGHT", -PAD, -20)
    local live = label(page, "", 0, "warn")
    live:SetPoint("LEFT", nightDrop, "RIGHT", 16, 0)

    local empty = label(page, "No boss pulls yet. Every boss pull is logged here by itself: the boss, the time in combat, "
        .. "kill or wipe and the boss's health at a wipe.", 0, "textDim")
    empty:SetPoint("TOPLEFT", PAD, -60)
    empty:SetPoint("RIGHT", -PAD, 0)
    empty:SetWordWrap(true)

    -- Per boss.
    local sumHead = label(page, "BOSSES", -2, "text")
    sumHead:SetPoint("TOPLEFT", PAD, -62)
    W.OnAccent(function(r, g, b) sumHead:SetTextColor(r, g, b) end)
    local summary = makeTable(page, {
        { "Boss", 200 }, { "Pulls", 60, "CENTER" }, { "Kills", 60, "CENTER" }, { "Best wipe", 90, "CENTER" },
        { "Kill time", 80, "CENTER" }, { "In combat", 90, "CENTER" },
    })
    summary:SetPoint("TOPLEFT", sumHead, "BOTTOMLEFT", 0, -6)
    summary:SetPoint("RIGHT", -PAD, 0)

    -- Every pull.
    local pullHead = label(page, "PULLS", -2, "text")
    W.OnAccent(function(r, g, b) pullHead:SetTextColor(r, g, b) end)
    local pulls = makeTable(page, {
        { "#", 40, "CENTER" }, { "Time", 60, "CENTER" }, { "Boss", 220 }, { "Combat", 70, "CENTER" }, { "Result", 160 },
    })
    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", pulls, "TOPLEFT", 0, -ROW_H - 2)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, 40)
    pulls.body = CreateFrame("Frame", nil, scroll)
    pulls.body:SetSize(10, 10)
    scroll:SetScrollChild(pulls.body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, pulls.body:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * ROW_H * 3)))
    end)
    local totals = label(page, "", -1, "textDim")
    totals:SetPoint("BOTTOMLEFT", PAD, 16)

    local liveTicker
    local function refreshLive()
        local cur = PullLog.Current()
        if cur then
            live:SetText(("Pulling %s  %s%s"):format(cur.name, PullLog.FormatTime(floor(GetTime() - cur.startTime)),
                cur.pct and ("  %.1f%%"):format(cur.pct) or ""))
        else
            live:SetText("")
        end
    end

    function refresh()
        refreshLive()
        local list, n = PullLog.Pulls(night)
        nightDrop:Set(n)
        if not n then nightDrop.text:SetText("No pulls yet") end
        delete:SetDisabled(not n and "Nothing to delete." or nil)
        local has = #list > 0
        empty:SetShown(not has)
        sumHead:SetShown(has)
        summary:SetShown(has)
        pullHead:SetShown(has)
        pulls:SetShown(has)
        scroll:SetShown(has)
        totals:SetShown(has)
        if not has then return end

        local bosses, total = PullLog.Summary(n)
        for i, s in ipairs(bosses) do
            local r = summary:Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", summary, "TOPLEFT", 0, -(i * ROW_H))
            r:SetSize(summary.width, ROW_H)
            r.bg:SetAlpha(i % 2 == 0 and 0.6 or 0.25)
            r.cells[1]:SetText(s.boss)
            r.cells[2]:SetText(s.pulls)
            r.cells[3]:SetText(s.kills > 0 and ("|cff3fc77f%d|r"):format(s.kills) or "0")
            r.cells[4]:SetText(s.best and ("%.1f%%"):format(s.best) or "-")
            r.cells[5]:SetText(s.killTime and PullLog.FormatTime(s.killTime) or "-")
            r.cells[6]:SetText(PullLog.FormatTime(s.combat))
            r:Show()
        end
        for i = #bosses + 1, #summary.rows do summary.rows[i]:Hide() end
        summary:SetHeight((#bosses + 1) * ROW_H)

        pullHead:ClearAllPoints()
        pullHead:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -18)
        pulls:ClearAllPoints()
        pulls:SetPoint("TOPLEFT", pullHead, "BOTTOMLEFT", 0, -6)
        pulls:SetPoint("RIGHT", -PAD, 0)
        pulls:SetHeight(ROW_H)
        -- Newest first.
        local count = #list
        for i = 1, count do
            local p = list[count - i + 1]
            local r = pulls:Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetSize(pulls.width, ROW_H)
            r.bg:SetAlpha(i % 2 == 0 and 0.6 or 0.25)
            r.cells[1]:SetText(count - i + 1)
            r.cells[2]:SetText(date("%H:%M", p.t))
            r.cells[3]:SetText(("%s  |cff7c858f#%d|r"):format(p.boss, PullLog.PullNumber(p)))
            r.cells[4]:SetText(PullLog.FormatTime(p.duration))
            r.cells[5]:SetText(resultText(p))
            r:Show()
        end
        for i = count + 1, #pulls.rows do pulls.rows[i]:Hide() end
        pulls.body:SetSize(pulls.width, count * ROW_H)
        totals:SetText(("%d pull%s \194\183 %d kill%s \194\183 %s in combat"):format(
            total.pulls, total.pulls == 1 and "" or "s", total.kills, total.kills == 1 and "" or "s", PullLog.FormatTime(total.combat)))
    end

    PullLog.OnChange(function() if page:IsShown() then refresh() end end)
    page:SetScript("OnShow", function()
        liveTicker = liveTicker or C_Timer.NewTicker(1, function() SRT:Call("pull log live", refreshLive) end)
    end)
    page:SetScript("OnHide", function()
        if liveTicker then liveTicker:Cancel() liveTicker = nil end
    end)
    return refresh
end)
