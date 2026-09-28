-- Raid check page: Check (a table of the group: one column per category) and Categories
-- (what counts: editable, because the WoW Forever consumable meta is not known yet).
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets
local Main, RaidCheck = SRT.Main, SRT.RaidCheck

local PAD, ROW_H, NAME_W, HEAD_H = 26, 20, 150, 36
local CELL_COLOR = { yes = "good", low = "warn", no = "bad", optional = "textFaint", unknown = "textFaint" }

local function label(parent, text, delta, color)
    local fs = W.Text(parent, delta or 0, color or "text")
    fs:SetText(text or "")
    return fs
end

-- Mouse wheel scrolling for a scroll frame whose child is `child`.
local function wheel(scroll, child, step)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * step)))
    end)
end

Main.RegisterPage("raidcheck", function(page)
    local db = SRT.db.raidcheck
    local mode = "check"
    local refresh

    local tabs = W.Segment(page, { { value = "check", label = "Check" }, { value = "categories", label = "Categories" } },
        function(v)
            mode = v
            refresh()
        end)
    tabs:SetPoint("TOPLEFT", PAD, -20)

    local checkView = CreateFrame("Frame", nil, page)
    local catView = CreateFrame("Frame", nil, page)
    for _, v in ipairs({ checkView, catView }) do
        v:SetPoint("TOPLEFT", 0, -56)
        v:SetPoint("BOTTOMRIGHT")
    end

    -- Check -------------------------------------------------------------------------
    local scanBtn = W.Button(page, "Scan", "accent", function() RaidCheck.Refresh() end, 26)
    scanBtn:SetPoint("TOPRIGHT", -PAD, -20)
    scanBtn.tooltip = "Reads everyone's buffs and asks SRT users for their weapon oil and durability."
    local postBtn = W.Button(page, "Post missing", nil, function() RaidCheck.PostMissing() end, 26)
    postBtn:SetPoint("RIGHT", scanBtn, "LEFT", -10, 0)
    postBtn.tooltip = "Posts who is missing what in raid chat (optional categories are left out)."
    local onlyToggle = W.Toggle(page, function(on)
        db.onlyMissing = on
        refresh()
    end)
    onlyToggle:SetPoint("RIGHT", postBtn, "LEFT", -110, 0)
    local onlyLabel = label(page, "Only missing", -1, "textDim")
    onlyLabel:SetPoint("LEFT", onlyToggle, "RIGHT", 8, 0)

    local summary = label(checkView, "", -1, "textDim")
    summary:SetPoint("TOPLEFT", PAD, 0)

    local header = CreateFrame("Frame", nil, checkView)
    header:SetPoint("TOPLEFT", PAD, -22)
    header:SetPoint("RIGHT", -PAD, 0)
    header:SetHeight(HEAD_H)
    W.Line(header, "bottom", "line")
    local headCells = {}

    local scroll = CreateFrame("ScrollFrame", nil, checkView)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, 16)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(10, 10)
    scroll:SetScrollChild(body)
    wheel(scroll, body, ROW_H * 3)
    local rows = {}

    local emptyText = label(checkView, "", 0, "textDim")
    emptyText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -12)

    local function headCell(i)
        if headCells[i] then return headCells[i] end
        local h = CreateFrame("Button", nil, header)
        h.label = label(h, "", -2, "textDim")
        h.label:SetPoint("TOP", 0, -4)
        h.count = label(h, "", -2, "text")
        h.count:SetPoint("TOP", h.label, "BOTTOM", 0, -3)
        h:SetScript("OnEnter", function(self) if self.tip then W.ShowTooltip(self, self.tip) end end)
        h:SetScript("OnLeave", function() W.HideTooltip() end)
        headCells[i] = h
        return h
    end

    local function row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, body)
        r:SetHeight(ROW_H)
        r.bg = W.Fill(r, "field", 1)
        r.bg:SetAllPoints()
        r.name = label(r, "", -1, "text")
        r.name:SetPoint("LEFT", 6, 0)
        r.name:SetWidth(NAME_W - 10)
        r.cells = {}
        rows[i] = r
        return r
    end

    local function refreshCheck()
        onlyToggle:Set(db.onlyMissing)
        local result = RaidCheck.Last()
        local cats = result and result.cats or RaidCheck.Enabled()
        local width = header:GetWidth()
        local colW = max(40, floor((width - NAME_W) / max(1, #cats)))
        -- Header: short name + have/total per column.
        local nameHead = headCell(0)
        nameHead:ClearAllPoints()
        nameHead:SetPoint("TOPLEFT")
        nameHead:SetSize(NAME_W, HEAD_H)
        nameHead.label:ClearAllPoints()
        nameHead.label:SetPoint("TOPLEFT", 6, -4)
        nameHead.label:SetText("PLAYER")
        nameHead.count:SetText("")
        for i, c in ipairs(cats) do
            local h = headCell(i)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", NAME_W + (i - 1) * colW, 0)
            h:SetSize(colW, HEAD_H)
            h.label:SetText(strupper(c.short or c.id))
            local t = result and result.totals[c.id]
            h.count:SetText(t and t.total > 0 and ("%d/%d"):format(t.have, t.total) or "")
            h.count:SetTextColor(Theme:Color(t and t.have < t.total and not c.optional and "warn" or "text"))
            h.tip = { c.name .. (c.optional and " (optional)" or ""),
                (c.kind == "weapon" or c.kind == "durability") and "Reported by SRT users only (? = no SRT)." or nil }
            h:Show()
        end
        for i = #cats + 1, #headCells do headCells[i]:Hide() end

        if not result then
            summary:SetText("Not scanned yet. Scan, or start a ready check.")
            emptyText:SetText(IsInGroup() and "" or "Join a group to see everyone; solo only you are checked.")
            for _, r in ipairs(rows) do r:Hide() end
            return
        end
        emptyText:SetText("")
        local missingCount = 0
        for _, m in ipairs(RaidCheck.Missing(result)) do missingCount = missingCount + #m.names end
        summary:SetText(("Scanned %s \194\183 %d players \194\183 %d missing items \194\183 ? = out of range or no SRT"):format(
            date("%H:%M:%S", result.at), #result.rows, missingCount))

        local y, n, lastGroup = 0, 0, nil
        for _, data in ipairs(result.rows) do
            local show = true
            if db.onlyMissing then
                show = false
                for _, c in ipairs(cats) do
                    local cell = data.cells[c.id]
                    if cell and cell.state == "no" then show = true end
                end
            end
            if show then
                n = n + 1
                if lastGroup and data.group ~= lastGroup then y = y + 6 end
                lastGroup = data.group
                local r = row(n)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 0, -y)
                r:SetSize(NAME_W + #cats * colW, ROW_H)
                r.bg:SetAlpha(n % 2 == 0 and 0.6 or 0.25)
                r.name:SetText(data.name)
                local cr, cg, cb = Theme.ClassColor(data.classFile)
                if cr then r.name:SetTextColor(cr, cg, cb) else r.name:SetTextColor(Theme:Color("text")) end
                for i, c in ipairs(cats) do
                    local btn = r.cells[i]
                    if not btn then
                        btn = CreateFrame("Button", nil, r)
                        btn.fs = label(btn, "", -2, "text")
                        btn.fs:SetAllPoints()
                        btn.fs:SetJustifyH("CENTER")
                        btn:SetScript("OnEnter", function(self) RaidCheck.ShowCellTooltip(self, self.row, self.cat, self.cell) end)
                        btn:SetScript("OnLeave", function() RaidCheck.HideCellTooltip() end)
                        r.cells[i] = btn
                    end
                    btn:ClearAllPoints()
                    btn:SetPoint("LEFT", NAME_W + (i - 1) * colW, 0)
                    btn:SetSize(colW, ROW_H)
                    local cell = data.cells[c.id] or { state = "unknown", text = "" }
                    btn.row, btn.cat, btn.cell = data, c, cell
                    btn.fs:SetText(cell.text)
                    btn.fs:SetTextColor(Theme:Color(CELL_COLOR[cell.state] or "text"))
                    btn:Show()
                end
                for i = #cats + 1, #r.cells do r.cells[i]:Hide() end
                r:Show()
                y = y + ROW_H
            end
        end
        for i = n + 1, #rows do rows[i]:Hide() end
        body:SetSize(NAME_W + #cats * colW, max(1, y))
        if n == 0 then emptyText:SetText("Nobody is missing anything.") end
    end

    -- Categories --------------------------------------------------------------------
    local catHelp = label(catView, "What counts in each column: buff names (a part of the name is enough) or spell IDs, "
        .. "separated by commas. Optional columns are shown but not counted as missing.", -2, "textFaint")
    catHelp:SetPoint("TOPLEFT", PAD, 0)
    catHelp:SetPoint("RIGHT", -PAD, 0)
    catHelp:SetWordWrap(true)

    local catScroll = CreateFrame("ScrollFrame", nil, catView)
    catScroll:SetPoint("TOPLEFT", PAD, -40)
    catScroll:SetPoint("BOTTOMRIGHT", -PAD, 92)
    local catBody = CreateFrame("Frame", nil, catScroll)
    catBody:SetSize(10, 10)
    catScroll:SetScrollChild(catBody)
    wheel(catScroll, catBody, 34 * 2)
    local catRows = {}
    local CAT_H = 34

    local function catRow(i)
        if catRows[i] then return catRows[i] end
        local r = CreateFrame("Frame", nil, catBody)
        r:SetHeight(CAT_H)
        r.on = W.Toggle(r, function(on)
            if r.cat then r.cat.on = on end
            RaidCheck.Changed()
        end)
        r.on:SetPoint("LEFT", 0, 0)
        r.short = W.EditBox(r, "Short", 26)
        r.short:SetWidth(76)
        r.short:SetMaxLetters(10)
        r.short:SetPoint("LEFT", r.on, "RIGHT", 10, 0)
        r.short:HookScript("OnTextChanged", function(self, user) if user and r.cat then r.cat.short = self:GetText() end end)
        r.name = W.EditBox(r, "Name", 26)
        r.name:SetWidth(150)
        r.name:SetMaxLetters(40)
        r.name:SetPoint("LEFT", r.short, "RIGHT", 6, 0)
        r.name:HookScript("OnTextChanged", function(self, user) if user and r.cat then r.cat.name = self:GetText() end end)
        r.opt = W.Toggle(r, function(on) if r.cat then r.cat.optional = on or nil end end)
        r.optLabel = label(r, "Optional", -2, "textDim")
        r.del = W.CloseButton(r, function()
            if r.cat then
                local id = r.cat.id
                W.Confirm(("Remove the category \"%s\"?"):format(r.cat.name or id), "Remove", function() RaidCheck.RemoveCategory(id) end)
            end
        end)
        r.del:SetPoint("RIGHT", 0, 0)
        r.optLabel:SetPoint("RIGHT", r.del, "LEFT", -8, 0)
        r.opt:SetPoint("RIGHT", r.optLabel, "LEFT", -6, 0)
        r.match = W.EditBox(r, "Buff names or spell IDs, separated by commas", 26)
        r.match:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
        r.match:SetPoint("RIGHT", r.opt, "LEFT", -12, 0)
        r.match:SetMaxLetters(500)
        r.match:HookScript("OnTextChanged", function(self, user) if user and r.cat then r.cat.match = self:GetText() end end)
        r.builtin = label(r, "", -2, "textFaint")
        r.builtin:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
        catRows[i] = r
        return r
    end

    local BUILTIN = {
        ready = "Built in: the ready check answers.",
        weapon = "Built in: temporary weapon enchant (oil, stone), reported by SRT users.",
        durability = "Built in: the lowest item durability, reported by SRT users.",
    }

    local function setEdit(e, text)
        if not e:HasFocus() then e:SetText(text or "") end
        e.placeholder:SetShown(e:GetText() == "" and not e:HasFocus())
    end

    local function refreshCategories()
        local cats = RaidCheck.Categories()
        local width = catScroll:GetWidth()
        for i, c in ipairs(cats) do
            local r = catRow(i)
            r.cat = c
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * CAT_H)
            r:SetWidth(width)
            r.on:Set(c.on)
            setEdit(r.short, c.short)
            setEdit(r.name, c.name)
            local builtin = BUILTIN[c.kind or ""]
            r.match:SetShown(not builtin)
            r.builtin:SetShown(builtin ~= nil)
            r.builtin:SetText(builtin or "")
            if not builtin then setEdit(r.match, c.match) end
            r.opt:Set(c.optional)
            r.del:SetShown(c.custom and true or false)
            r:Show()
        end
        for i = #cats + 1, #catRows do catRows[i]:Hide() end
        catBody:SetSize(width, #cats * CAT_H)
    end

    local addBtn = W.Button(catView, "Add category", nil, function() RaidCheck.AddCategory() end, 26)
    addBtn:SetPoint("BOTTOMLEFT", PAD, 16)
    local resetBtn = W.Button(catView, "Reset to defaults", nil, function()
        W.Confirm("Replace all categories with the defaults?", "Reset", function() RaidCheck.ResetCategories() end)
    end, 26)
    resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
    local popupLabel = label(catView, "Ready check window", -1, "textDim")
    popupLabel:SetPoint("BOTTOMLEFT", PAD, 58)
    local popupSeg = W.Segment(catView, { { value = "all", label = "Everyone" }, { value = "lead", label = "Leader/assist" },
        { value = "off", label = "Off" } }, function(v) db.popup = v end)
    popupSeg:SetPoint("LEFT", popupLabel, "RIGHT", 10, 0)
    local durLabel = label(catView, "Durability", -1, "textDim")
    durLabel:SetPoint("LEFT", popupSeg, "RIGHT", 24, 0)
    local durSlider = W.Slider(catView, 10, 90, 5, 100, function(v) return ("below %d%% = missing"):format(v) end,
        function(v) db.minDurability = v end)
    durSlider:SetPoint("LEFT", durLabel, "RIGHT", 10, 0)

    function refresh()
        tabs:Set(mode)
        checkView:SetShown(mode == "check")
        catView:SetShown(mode == "categories")
        scanBtn:SetShown(mode == "check")
        postBtn:SetShown(mode == "check")
        onlyToggle:SetShown(mode == "check")
        onlyLabel:SetShown(mode == "check")
        postBtn:SetDisabled(not IsInGroup() and "Join a group first." or (not RaidCheck.Last() and "Scan first.") or nil)
        if mode == "check" then
            refreshCheck()
        else
            refreshCategories()
            popupSeg:Set(db.popup or "all")
            durSlider:Set(db.minDurability or 50)
        end
    end

    RaidCheck.OnChange(function() if page:IsShown() then refresh() end end)
    page:SetScript("OnSizeChanged", function() if page:IsShown() then refresh() end end)
    return refresh
end)
