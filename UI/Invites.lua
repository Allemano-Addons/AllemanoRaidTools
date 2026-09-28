-- Invites & groups page: Invite (guild ranks, keyword whispers, raid options) and Groups
-- (paste the OXM roster, drag names between groups, invite the roster, apply the groups).
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets
local Main, Invites = SRT.Main, SRT.Invites

local PAD, GAP, LINE_H = 26, 10, 18

-- Roster slot stripe colors (see Invites.MatchRoster); names are in class color.
local STATE_COLOR = { guild = "accent", offline = "textFaint", unknown = "bad", ambiguous = "warn" }
local LEGEND = "Stripe:  |cff3fc77fin their group|r  \194\183  |cffe6e8ebin the group, other group (gN)|r  \194\183  "
    .. "|c%scan be invited|r  \194\183  |cff7c858foffline|r  \194\183  |cffe8a33dsame first name twice|r  \194\183  |cffe0564fnot found|r"

local function label(parent, text, delta, color)
    local fs = W.Text(parent, delta or 0, color or "text")
    fs:SetText(text)
    return fs
end

local function heading(parent, text)
    local fs = W.Text(parent, -2, "text")
    fs:SetText(strupper(text))
    W.OnAccent(function(r, g, b) fs:SetTextColor(r, g, b) end)
    return fs
end

Main.RegisterPage("invites", function(page)
    local s = SRT.db.invite
    local mode = "invite"
    local refresh

    local tabs = W.Segment(page, { { value = "invite", label = "Invite" }, { value = "groups", label = "Groups" } },
        function(v)
            mode = v
            refresh()
        end)
    tabs:SetPoint("TOPLEFT", PAD, -20)
    local pending = label(page, "", -1, "textDim")
    pending:SetPoint("TOPRIGHT", -PAD, -26)

    local inviteView = CreateFrame("Frame", nil, page)
    local groupsView = CreateFrame("Frame", nil, page)
    for _, v in ipairs({ inviteView, groupsView }) do
        v:SetPoint("TOPLEFT", 0, -60)
        v:SetPoint("BOTTOMRIGHT")
    end

    -- Invite ------------------------------------------------------------------------
    local ranksHead = heading(inviteView, "Guild ranks")
    ranksHead:SetPoint("TOPLEFT", PAD, -4)
    local ranksHelp = label(inviteView, "Online members of the ticked ranks are invited (party first, then raid).", -2, "textFaint")
    ranksHelp:SetPoint("TOPLEFT", ranksHead, "BOTTOMLEFT", 0, -6)
    local rankBox = CreateFrame("Frame", nil, inviteView)
    rankBox:SetPoint("TOPLEFT", ranksHelp, "BOTTOMLEFT", 0, -10)
    rankBox:SetSize(420, 1)
    local rankRows = {}
    local inviteRanks = W.Button(inviteView, "Invite online", "accent", function() Invites.InviteRanks() end, 28)

    local kwHead = heading(inviteView, "Keyword invite")
    local kwToggle = W.Toggle(inviteView, function(on) s.keywordOn = on end)
    local kwLabel = label(inviteView, "Invite players who whisper")
    local kwEdit = W.EditBox(inviteView, "inv", 26)
    kwEdit:SetWidth(110)
    kwEdit:SetMaxLetters(20)
    kwEdit:HookScript("OnTextChanged", function(self, user) if user then s.keyword = strtrim(self:GetText()) end end)
    local guildToggle = W.Toggle(inviteView, function(on) s.guildOnly = on end)
    local guildLabel = label(inviteView, "Only guild members")

    local raidHead = heading(inviteView, "Raid")
    local convToggle = W.Toggle(inviteView, function(on) s.autoConvert = on end)
    local convLabel = label(inviteView, "Convert to raid when the party is full")
    local assistLabel = label(inviteView, "Give assist to")
    local assistEdit = W.EditBox(inviteView, "Names, separated by commas", 26)
    assistEdit:SetWidth(320)
    assistEdit:HookScript("OnTextChanged", function(self, user) if user then s.assists = self:GetText() end end)
    local assistHelp = label(inviteView, "Promoted when they join (you must be the raid leader).", -2, "textFaint")

    local annHead = heading(inviteView, "Roster invite")
    local annLabel = label(inviteView, "Announce in")
    local annSeg = W.Segment(inviteView, { { value = "GUILD", label = "Guild" }, { value = "OFFICER", label = "Officer" },
        { value = "OFF", label = "Off" } }, function(v) s.announce = v end)
    local annEdit = W.EditBox(inviteView, "Message when \"Invite roster\" is clicked", 26)
    annEdit:SetWidth(420)
    annEdit:SetMaxLetters(250)
    annEdit:HookScript("OnTextChanged", function(self, user) if user then s.announceText = self:GetText() end end)

    local function layoutInvite(rankHeight)
        inviteRanks:ClearAllPoints()
        inviteRanks:SetPoint("TOPLEFT", rankBox, "TOPLEFT", 0, -(rankHeight + 8))
        kwHead:ClearAllPoints()
        kwHead:SetPoint("TOPLEFT", inviteRanks, "BOTTOMLEFT", 0, -26)
        kwToggle:SetPoint("TOPLEFT", kwHead, "BOTTOMLEFT", 0, -14)
        kwLabel:SetPoint("LEFT", kwToggle, "RIGHT", 10, 0)
        kwEdit:SetPoint("LEFT", kwLabel, "RIGHT", 10, 0)
        guildToggle:SetPoint("TOPLEFT", kwToggle, "BOTTOMLEFT", 0, -16)
        guildLabel:SetPoint("LEFT", guildToggle, "RIGHT", 10, 0)
        raidHead:SetPoint("TOPLEFT", guildToggle, "BOTTOMLEFT", 0, -26)
        convToggle:SetPoint("TOPLEFT", raidHead, "BOTTOMLEFT", 0, -14)
        convLabel:SetPoint("LEFT", convToggle, "RIGHT", 10, 0)
        assistLabel:SetPoint("TOPLEFT", convToggle, "BOTTOMLEFT", 0, -22)
        assistEdit:SetPoint("LEFT", assistLabel, "RIGHT", 10, 0)
        assistHelp:SetPoint("TOPLEFT", assistLabel, "BOTTOMLEFT", 0, -12)
        annHead:SetPoint("TOPLEFT", assistHelp, "BOTTOMLEFT", 0, -24)
        annLabel:SetPoint("TOPLEFT", annHead, "BOTTOMLEFT", 0, -18)
        annSeg:SetPoint("LEFT", annLabel, "RIGHT", 10, 0)
        annEdit:SetPoint("TOPLEFT", annLabel, "BOTTOMLEFT", 0, -14)
    end

    local function rankRow(i)
        if rankRows[i] then return rankRows[i] end
        local r = CreateFrame("Frame", nil, rankBox)
        r:SetSize(200, 24)
        r.toggle = W.Toggle(r, function(on) s.ranks[r.rankIndex] = on or nil refresh() end)
        r.toggle:SetPoint("LEFT")
        r.label = label(r, "")
        r.label:SetPoint("LEFT", r.toggle, "RIGHT", 10, 0)
        rankRows[i] = r
        return r
    end

    local function refreshInvite()
        local ranks = Invites.GuildRanks()
        for i, rank in ipairs(ranks) do
            local r = rankRow(i)
            r.rankIndex = rank.index
            r.label:SetText(rank.name or ("Rank " .. rank.index))
            r.toggle:Set(s.ranks[rank.index])
            r:ClearAllPoints()
            local col, row = (i - 1) % 2, floor((i - 1) / 2)
            r:SetPoint("TOPLEFT", col * 210, -row * 28)
            r:Show()
        end
        for i = #ranks + 1, #rankRows do rankRows[i]:Hide() end
        local rankHeight = #ranks == 0 and 20 or ceil(#ranks / 2) * 28
        if #ranks == 0 then
            ranksHelp:SetText(IsInGuild() and "Loading the guild list..." or "You are not in a guild.")
        else
            ranksHelp:SetText("Online members of the ticked ranks are invited (party first, then raid).")
        end
        layoutInvite(rankHeight)
        local n = #Invites.RankCandidates()
        inviteRanks:SetLabel(("Invite online (%d)"):format(n))
        inviteRanks:SetDisabled((not Invites.CanInvite() and "Only the raid leader or an assistant can invite.")
            or (n == 0 and "Nobody online in the ticked ranks (or they are already in the group).") or nil)
        kwToggle:Set(s.keywordOn)
        guildToggle:Set(s.guildOnly)
        convToggle:Set(s.autoConvert)
        if not kwEdit:HasFocus() then kwEdit:SetText(s.keyword or "") end
        if not assistEdit:HasFocus() then assistEdit:SetText(s.assists or "") end
        kwEdit.placeholder:SetShown(kwEdit:GetText() == "")
        assistEdit.placeholder:SetShown(assistEdit:GetText() == "")
        annSeg:Set(s.announce or "GUILD")
        if not annEdit:HasFocus() then annEdit:SetText(s.announceText or "") end
        annEdit.placeholder:SetShown(annEdit:GetText() == "")
    end

    -- Groups ------------------------------------------------------------------------
    local pasteLabel = label(groupsView, "Paste the OXM roster", -1, "textDim")
    pasteLabel:SetPoint("TOPLEFT", PAD, -4)
    local paste = W.MultiEdit(groupsView, function(text)
        SRT.db.roster.text = text
        refresh()
    end, 2000)
    paste:SetPoint("TOPLEFT", PAD, -24)
    paste:SetPoint("BOTTOMLEFT", PAD, 20)
    paste:SetWidth(170)

    local grid = CreateFrame("Frame", nil, groupsView)
    grid:SetPoint("TOPLEFT", paste, "TOPRIGHT", 16, 0)
    grid:SetPoint("BOTTOMRIGHT", -PAD, 20)
    local boxes = {}

    -- Drag and drop (changes the plan only; "Apply groups" moves the raid):
    --   a roster name dropped on a name or empty place: the two swap
    --   a roster name dropped elsewhere in a group box: that group's first free place
    --   a roster name dropped on "not on the roster": taken off the roster
    --   a group member from "not on the roster" dropped in a group: added there
    local ghost, drag
    local bench
    local function getGhost()
        if ghost then return ghost end
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetSize(140, LINE_H + 6)
        ghost.bg = W.Fill(ghost, "selected", 0.95)
        ghost.bg:SetAllPoints()
        W.Border(ghost, "line")
        ghost.text = label(ghost, "", -1, "text")
        ghost.text:SetPoint("LEFT", 8, 0)
        ghost:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)
        end)
        return ghost
    end

    local function startDrag(what, text)
        drag = what
        local gh = getGhost()
        gh.text:SetText(text)
        gh:Show()
    end

    local function drop()
        local d = drag
        drag = nil
        if ghost then ghost:Hide() end
        if not d then return end
        if bench and bench:IsShown() and bench:IsMouseOver() then
            if d.pos then Invites.RemovePlace(d.pos) end
            return
        end
        for g, b in pairs(boxes) do
            if b:IsShown() and b:IsMouseOver() then
                local target
                for _, line in ipairs(b.lines) do
                    if line:IsMouseOver() then target = line.pos end
                end
                local ok, why
                if d.pos and target then
                    ok = Invites.SwapPlaces(d.pos, target)
                elseif d.pos then
                    ok, why = Invites.MoveToGroup(d.pos, g)
                else
                    ok, why = Invites.AddToGroup(d.name, g, target)
                end
                if not ok and why then SRT:Print(why) end
                return
            end
        end
    end

    -- A name line: state stripe on the left, name in class color.
    local function nameLine(parent)
        local line = CreateFrame("Button", nil, parent)
        line:SetHeight(LINE_H)
        line.hl = W.Fill(line, "selected", 1)
        line.hl:SetAllPoints()
        line.hl:Hide()
        line.stripe = line:CreateTexture(nil, "ARTWORK")
        line.stripe:SetPoint("TOPLEFT", 2, -3)
        line.stripe:SetPoint("BOTTOMLEFT", 2, 3)
        line.stripe:SetWidth(3)
        line.fs = label(line, "", -1, "text")
        line.fs:SetPoint("LEFT", 10, 0)
        line.fs:SetPoint("RIGHT", -4, 0)
        line:RegisterForDrag("LeftButton")
        line:SetScript("OnEnter", function(self) if self.filled or drag then self.hl:Show() end end)
        line:SetScript("OnLeave", function(self) self.hl:Hide() end)
        line:SetScript("OnDragStop", function() SRT:Call("roster drop", drop) end)
        return line
    end

    local function paintLine(line, text, classFile, stateKey)
        line.fs:SetText(text)
        local r, g, b = Theme.ClassColor(classFile)
        if r then line.fs:SetTextColor(r, g, b) else line.fs:SetTextColor(Theme:Color(stateKey == "warn" and "warn" or "textDim")) end
        if stateKey == "accent" then
            line.stripe:SetColorTexture(Theme:Accent())
        elseif stateKey then
            line.stripe:SetColorTexture(Theme:Color(stateKey))
        end
        line.stripe:SetShown(stateKey ~= nil)
    end

    local function box(g)
        if boxes[g] then return boxes[g] end
        local b = CreateFrame("Frame", nil, grid)
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        W.Border(b, "line")
        b.title = label(b, "GROUP " .. g, -2, "textDim")
        b.title:SetPoint("TOPLEFT", 10, -8)
        b:EnableMouse(true)
        b.lines = {}
        for i = 1, 5 do
            local line = nameLine(b)
            line.pos = (g - 1) * 5 + i
            line.box = b
            line:SetPoint("TOPLEFT", 4, -(24 + (i - 1) * LINE_H))
            line:SetPoint("RIGHT", -4, 0)
            line:SetScript("OnDragStart", function(self)
                if self.filled then startDrag({ pos = self.pos }, self.plain) end
            end)
            b.lines[i] = line
        end
        boxes[g] = b
        return b
    end

    -- Group members who are not on the roster (drag them into a group).
    bench = CreateFrame("Frame", nil, grid)
    bench.bg = W.Fill(bench, "window", 1)
    bench.bg:SetAllPoints()
    bench.border = W.Border(bench, "line")
    bench:EnableMouse(true)
    bench.title = label(bench, "IN THE GROUP, NOT ON THE ROSTER", -2, "textDim")
    bench.title:SetPoint("TOPLEFT", 10, -8)
    bench.hint = label(bench, "", -2, "textFaint")
    bench.hint:SetPoint("TOPLEFT", 10, -26)
    bench.chips = {}
    local function chip(i)
        if bench.chips[i] then return bench.chips[i] end
        local c = nameLine(bench)
        c:SetScript("OnDragStart", function(self) startDrag({ name = self.name }, self.name) end)
        bench.chips[i] = c
        return c
    end

    local legend = label(grid, LEGEND, -2, "textDim")
    local summary = label(grid, "", -1, "textDim")
    summary:SetPoint("BOTTOMLEFT", 0, 6)
    local applyBtn = W.Button(grid, "Apply groups", "accent", function() Invites.Sort() end)
    applyBtn:SetPoint("BOTTOMRIGHT")
    applyBtn.tooltip = "Moves the raid's players into the groups shown here."
    local inviteRoster = W.Button(grid, "Invite roster", nil, function() Invites.InviteRoster() end)
    inviteRoster:SetPoint("RIGHT", applyBtn, "LEFT", -10, 0)
    summary:SetPoint("RIGHT", inviteRoster, "LEFT", -10, 0)

    local empty = label(grid, "Paste the roster on the left: names top to bottom, five per group\n"
        .. "(blank lines are ignored). \"Name/Other\" means either of them, \"-\" an empty place.\n"
        .. "Drag names between the groups, then \"Apply groups\" moves the raid.", 0, "textDim")
    empty:SetPoint("TOPLEFT", 0, -4)
    empty:SetPoint("RIGHT")
    empty:SetJustifyV("TOP")
    empty:SetWordWrap(true)

    local function refreshGroups()
        if not paste.edit:HasFocus() then paste.edit:SetText(SRT.db.roster.text or "") end
        local slots, others = Invites.Roster()
        local groups = 0
        for _, slot in ipairs(slots) do
            if not slot.empty then groups = max(groups, slot.group) end
        end
        empty:SetShown(groups == 0)
        local used = groups
        if groups > 0 and groups < 8 then groups = groups + 1 end -- an empty group to drop into
        local width = grid:GetWidth()
        local cols = 4
        local boxW = floor((width - (cols - 1) * GAP) / cols)
        local boxH = 26 + 5 * LINE_H + 8
        for g = 1, max(groups, #boxes) do
            local b = (g <= groups or boxes[g]) and box(g)
            if b then
                b:SetShown(g <= groups)
                b:ClearAllPoints()
                b:SetSize(boxW, boxH)
                b:SetPoint("TOPLEFT", ((g - 1) % cols) * (boxW + GAP), -floor((g - 1) / cols) * (boxH + GAP))
                b.title:SetTextColor(Theme:Color(g > used and "textFaint" or "textDim"))
                for i = 1, 5 do
                    local line = b.lines[i]
                    paintLine(line, "", nil, nil)
                    line.filled = nil
                end
            end
        end
        local counts = { raid = 0, right = 0, guild = 0, offline = 0, unknown = 0, ambiguous = 0, filled = 0 }
        for i, slot in ipairs(slots) do
            local line = boxes[slot.group].lines[(i - 1) % 5 + 1]
            local text = table.concat(slot.names, "/")
            line.plain = text
            line.filled = not slot.empty
            if not slot.empty then counts.filled = counts.filled + 1 end
            if slot.state == "raid" then
                counts.raid = counts.raid + 1
                if slot.member.group == slot.group then
                    counts.right = counts.right + 1
                    paintLine(line, text, slot.classFile, "good")
                else
                    paintLine(line, text .. "  |cff7c858f(g" .. slot.member.group .. ")|r", slot.classFile, "text")
                end
            elseif slot.state ~= "empty" then
                counts[slot.state] = counts[slot.state] + 1
                local suffix = (slot.state == "guild" and "  |cff7c858f(invite)|r") or (slot.state == "offline" and "  |cff7c858f(offline)|r") or ""
                paintLine(line, text .. suffix, slot.classFile, STATE_COLOR[slot.state])
            end
        end

        local rows = ceil(groups / cols)
        local y = rows * (boxH + GAP)
        legend:ClearAllPoints()
        legend:SetPoint("TOPLEFT", 0, -(y + 2))
        legend:SetShown(groups > 0)
        local ar, ag, ab = Theme:Accent()
        legend:SetText(LEGEND:format(("ff%02x%02x%02x"):format(floor(ar * 255 + 0.5), floor(ag * 255 + 0.5), floor(ab * 255 + 0.5))))
        y = y + (groups > 0 and 24 or 0)

        -- Not on the roster: four per row.
        local chipW = floor((width - 20) / 4)
        for i, o in ipairs(others) do
            local c = chip(i)
            c.name = o.name
            c.filled = true
            c:ClearAllPoints()
            c:SetSize(chipW, LINE_H)
            c:SetPoint("TOPLEFT", 6 + ((i - 1) % 4) * chipW, -(26 + floor((i - 1) / 4) * LINE_H))
            paintLine(c, o.name, o.classFile, nil)
            c:Show()
        end
        for i = #others + 1, #bench.chips do bench.chips[i]:Hide() end
        bench.hint:SetShown(#others == 0)
        bench.hint:SetText(groups > 0 and "Drag a name here to take it off the roster." or "")
        bench:ClearAllPoints()
        bench:SetPoint("TOPLEFT", 0, -y)
        bench:SetPoint("RIGHT")
        bench:SetHeight(26 + max(1, ceil(#others / 4)) * LINE_H + 8)
        bench:SetShown(groups > 0 or #others > 0)

        if groups == 0 then
            summary:SetText("")
        else
            summary:SetText(("%d/%d in the group \194\183 %d in their group \194\183 %d can be invited"):format(
                counts.raid, counts.filled, counts.right, counts.guild))
        end
        local lead = not SRT.Compat.IsLeaderOrAssist() and "Only the raid leader or an assistant can do this." or nil
        local s2 = SRT.db.invite
        inviteRoster:SetLabel(("Invite roster (%d)"):format(counts.guild))
        inviteRoster.tooltip = (s2.announce ~= "OFF" and strtrim(s2.announceText or "") ~= "")
            and { "Invites everyone on the roster who is online in the guild.",
                ("Posts in %s chat: %s"):format(s2.announce == "OFFICER" and "officer" or "guild", s2.announceText) }
            or "Invites everyone on the roster who is online in the guild."
        inviteRoster:SetDisabled((not Invites.CanInvite() and "Only the raid leader or an assistant can invite.")
            or (counts.guild == 0 and "Nobody on the roster is online in the guild and missing from the group.") or nil)
        applyBtn:SetLabel(Invites.IsSorting() and "Applying..." or "Apply groups")
        applyBtn:SetDisabled((not IsInRaid() and "Needs a raid: convert the party first.") or lead
            or (Invites.IsSorting() and "Already applying.") or (counts.raid == 0 and "Nobody on the roster is in the raid.") or nil)
    end

    function refresh()
        tabs:Set(mode)
        inviteView:SetShown(mode == "invite")
        groupsView:SetShown(mode == "groups")
        local n = Invites.Pending()
        pending:SetText(n > 0 and ("%d invite%s waiting"):format(n, n == 1 and "" or "s") or "")
        if mode == "invite" then refreshInvite() else refreshGroups() end
    end

    Invites.OnChange(function() if page:IsShown() then refresh() end end)
    page:SetScript("OnShow", function() SRT.Compat.RequestGuildRoster() end)
    page:SetScript("OnSizeChanged", function() if page:IsShown() then refresh() end end)
    SRT.Compat.RequestGuildRoster()
    return refresh
end)
