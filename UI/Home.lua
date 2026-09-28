-- Home: one card per tool with tonight's summary. Cards fill in as the tools are built;
-- until then they say what they will show.
local _, ART = ...

local Theme, W = ART.Theme, ART.Widgets
local Main = ART.Main

local PAD, GAP = 26, 16

Main.RegisterPage("home", function(page)
    local function go(id) return function() Main.Show(id) end end

    local readiness = W.Card(page, "Raid readiness", "Open raid check", go("raidcheck"))
    readiness:SetPoint("TOPLEFT", PAD, -24)
    readiness:SetPoint("RIGHT", page, "CENTER", -GAP / 2, 0)
    readiness:SetHeight(190)
    -- Four bars: the first required columns of the last raid check.
    local bars = {}
    for i = 1, 4 do
        local b = CreateFrame("Frame", nil, readiness)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", 18, -40 - (i - 1) * 26)
        b:SetPoint("RIGHT", -18, 0)
        b.label = W.Text(b, 0, "text")
        b.label:SetPoint("LEFT")
        b.label:SetWidth(110)
        b.track = W.Fill(b, "line", 1, "ARTWORK")
        b.track:SetPoint("LEFT", 120, 0)
        b.track:SetPoint("RIGHT", -60, 0)
        b.track:SetHeight(4)
        b.fill = b:CreateTexture(nil, "OVERLAY")
        b.fill:SetPoint("LEFT", b.track, "LEFT")
        b.fill:SetHeight(4)
        b.count = W.Text(b, 0, "text")
        b.count:SetPoint("RIGHT")
        bars[i] = b
    end
    local readyMissing = W.Text(readiness, -2, "textDim")
    readyMissing:SetPoint("BOTTOMLEFT", 18, 16)
    readyMissing:SetPoint("RIGHT", -18, 0)

    local function refreshReadiness()
        local result = ART.RaidCheck.Last()
        readiness.body:SetShown(not result)
        if not result then
            readiness.body:SetText("Flasks, food, buffs and durability for everyone, with who is missing what. "
                .. "Fills in at the next ready check (or Scan under Raid check).")
            for _, b in ipairs(bars) do b:Hide() end
            readyMissing:SetText("")
            return
        end
        local shown = {}
        for _, c in ipairs(result.cats) do
            if #shown < 4 and not c.optional and c.kind ~= "ready" and c.kind ~= "blessings" then shown[#shown + 1] = c end
        end
        for i, b in ipairs(bars) do
            local c = shown[i]
            b:SetShown(c ~= nil)
            if c then
                local t = result.totals[c.id]
                b.label:SetText(c.name)
                local frac = t.total > 0 and t.have / t.total or 0
                local full = t.total > 0 and t.have == t.total
                b.count:SetText(("%d/%d"):format(t.have, t.total))
                b.count:SetTextColor(Theme:Color(full and "text" or "warn"))
                if full then b.fill:SetColorTexture(Theme:Accent()) else b.fill:SetColorTexture(Theme:Color("warn")) end
                b.fill:SetWidth(max(1, b.track:GetWidth() * frac))
                b.fill:SetShown(frac > 0)
            end
        end
        local missing = ART.RaidCheck.Missing(result)
        readyMissing:SetText(missing[1] and ("Missing %s: %s"):format(missing[1].cat.name, table.concat(missing[1].names, ", ")) or "")
    end
    ART.RaidCheck.OnChange(function() if page:IsShown() then refreshReadiness() end end)

    local note = W.Card(page, "Note", "Edit note", go("notes"))
    note:SetPoint("TOPLEFT", page, "TOP", GAP / 2, -24)
    note:SetPoint("RIGHT", -PAD, 0)
    note:SetHeight(190)
    local resend = W.Button(note, "Resend", nil, function() ART.Notes.Resend() end, 26)
    resend:SetPoint("BOTTOMLEFT", 18, 16)
    local postNote = W.Button(note, "Post in raid chat", nil, function()
        local a = ART.Notes.Active()
        if a then ART.Notes.PostToChat(a.text) end
    end, 26)
    postNote:SetPoint("LEFT", resend, "RIGHT", 8, 0)

    -- "Name, Name (no ART)" for the missing list, at most `limit` names.
    local function missingText(missing, limit)
        local parts = {}
        for i, m in ipairs(missing) do
            if i > limit then
                parts[#parts + 1] = ("and %d more"):format(#missing - limit)
                break
            end
            local color = m.offline and "|cff7c858f" or "|cffe8a33d"
            parts[#parts + 1] = color .. m.name .. "|r" .. (m.offline and " (offline)" or m.noART and " (no ART)" or "")
        end
        return table.concat(parts, ", ")
    end

    local function refreshNote()
        local a, s = ART.Notes.Active(), ART.Notes.Status()
        local lines = {}
        if not a then
            lines[1] = "No note yet. Write one under Notes and send it to the raid."
        else
            lines[1] = "|cffe6e8eb" .. (a.title ~= "" and a.title or "Note") .. "|r"
            if s and a.hash == ART.db.lastSent.hash then
                lines[2] = ("Sent %s \194\183 %d of %d have it"):format(date("%H:%M", s.at), s.have, s.total)
                if #s.missing > 0 then lines[3] = "Missing: " .. missingText(s.missing, 6) end
            else
                lines[2] = ("From %s, %s"):format(a.sender or "?", date("%H:%M", a.at or time()))
            end
        end
        note.body:SetText(table.concat(lines, "\n"))
        local canSend = ART.Notes.CanSend()
        resend:SetShown(a ~= nil and canSend)
        postNote:SetShown(a ~= nil and IsInGroup())
        if not resend:IsShown() then
            postNote:ClearAllPoints()
            postNote:SetPoint("BOTTOMLEFT", 18, 16)
        else
            postNote:ClearAllPoints()
            postNote:SetPoint("LEFT", resend, "RIGHT", 8, 0)
        end
    end
    ART.Notes.OnChange(function() if page:IsShown() then refreshNote() end end)

    local pulls = W.Card(page, "Pulls tonight", "Pull log", go("pulllog"))
    pulls:SetPoint("TOPLEFT", readiness, "BOTTOMLEFT", 0, -GAP)
    pulls:SetPoint("TOPRIGHT", readiness, "BOTTOMRIGHT", 0, -GAP)
    pulls:SetHeight(160)
    -- The last three pulls of tonight: #, boss, combat time, result.
    local pullRows = {}
    for i = 1, 3 do
        local r = CreateFrame("Frame", nil, pulls)
        r:SetHeight(24)
        r:SetPoint("TOPLEFT", 18, -40 - (i - 1) * 30)
        r:SetPoint("RIGHT", -18, 0)
        W.Line(r, "bottom", "line")
        r.num = W.Text(r, 0, "textDim")
        r.num:SetPoint("LEFT")
        r.boss = W.Text(r, 0, "text")
        r.boss:SetPoint("LEFT", 34, 0)
        r.result = W.Text(r, 0, "text")
        r.result:SetPoint("RIGHT")
        r.time = W.Text(r, 0, "textDim")
        r.time:SetPoint("RIGHT", -110, 0)
        pullRows[i] = r
    end
    local function refreshPulls()
        local list, night = ART.PullLog.Pulls()
        if night ~= ART.PullLog.NightOf() then list = {} end
        pulls.body:SetShown(#list == 0)
        pulls.body:SetText("No boss pulled tonight. Every pull is logged by itself: boss, time in combat, kill or wipe with the boss's health.")
        for i, r in ipairs(pullRows) do
            local p = list[#list - i + 1]
            r:SetShown(p ~= nil)
            if p then
                r.num:SetText("#" .. (#list - i + 1))
                r.boss:SetText(p.boss)
                r.time:SetText(ART.PullLog.FormatTime(p.duration))
                r.result:SetText(ART.PullLog.ResultText(p))
            end
        end
    end
    ART.PullLog.OnChange(function() if page:IsShown() then refreshPulls() end end)

    local attendance = W.Card(page, "Attendance", "Export", go("attendance"))
    attendance:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -GAP)
    attendance:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -GAP)
    attendance:SetHeight(160)
    attendance.body:SetText("In raid, bench and late arrivals, with an export.\n\n|cff7c858fArrives with Attendance.|r")

    local cds = W.Card(page, "Cooldowns & battle res", nil, nil, true)
    cds:SetPoint("TOPLEFT", pulls, "BOTTOMLEFT", 0, -GAP)
    cds:SetPoint("RIGHT", -PAD, 0)
    cds:SetHeight(76)
    cds.body:ClearAllPoints()
    cds.body:SetPoint("TOPLEFT", 18, -40)
    cds.body:SetPoint("RIGHT", -150, 0)
    cds.body:SetTextColor(ART.Theme:Color("text"))
    local probeBtn = W.Button(cds, "Run probe", nil, function()
        ART.Probe.ArmCombat()
        Main.Refresh()
    end)
    probeBtn:SetPoint("RIGHT", -18, 0)

    return function()
        refreshNote()
        refreshReadiness()
        refreshPulls()
        local state = ART.Probe.CombatState()
        if state == "armed" then
            cds.body:SetText("Combat probe is armed: fight something in a dungeon, then /reload and send the SavedVariables file.")
        elseif state == "done" then
            cds.body:SetText("Combat probe recorded. /reload and send the SavedVariables file to see what Forever allows.")
        else
            cds.body:SetText("Waiting for probe results. Run the probe, then fight something in a dungeon.")
        end
        probeBtn:SetDisabled(state == "armed" and "The probe is already waiting for combat." or nil)
    end
end)
