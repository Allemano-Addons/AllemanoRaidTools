-- Invites & groups page: Invite (guild ranks, keyword whispers, raid options) and Groups
-- (paste the OXM roster, see who is where, invite the missing, sort the groups).
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets
local Main, Invites = SRT.Main, SRT.Invites

local PAD, GAP, LINE_H = 26, 10, 18

-- Roster slot colors (see Invites.MatchRoster).
local STATE_COLOR = { raid = "text", guild = "text", offline = "textFaint", unknown = "bad", ambiguous = "warn" }
local LEGEND = "|cff3fc77fin their group|r  \194\183  |cffe6e8ebin raid, other group (gN) / can be invited|r  \194\183  "
    .. "|cff7c858foffline|r  \194\183  |cffe8a33dsame first name twice|r  \194\183  |cffe0564fnot found|r"

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

    -- Drag and drop: a name follows the cursor; dropped on a name (or an empty place) the
    -- two swap, dropped elsewhere in a group box it moves to that group's first free place.
    local ghost, dragFrom
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

    local function drop()
        local from = dragFrom
        dragFrom = nil
        if ghost then ghost:Hide() end
        if not from then return end
        for g, b in pairs(boxes) do
            if b:IsShown() and b:IsMouseOver() then
                for _, line in ipairs(b.lines) do
                    if line:IsMouseOver() then
                        Invites.SwapPlaces(from, line.pos)
                        return
                    end
                end
                local ok, why = Invites.MoveToGroup(from, g)
                if not ok and why then SRT:Print(why) end
                return
            end
        end
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
            local line = CreateFrame("Button", nil, b)
            line.pos = (g - 1) * 5 + i
            line.box = b
            line:SetHeight(LINE_H)
            line:SetPoint("TOPLEFT", 4, -(24 + (i - 1) * LINE_H))
            line:SetPoint("RIGHT", -4, 0)
            line.hl = W.Fill(line, "selected", 1)
            line.hl:SetAllPoints()
            line.hl:Hide()
            line.fs = label(line, "", -1, "text")
            line.fs:SetPoint("LEFT", 6, 0)
            line.fs:SetPoint("RIGHT", -4, 0)
            line:RegisterForDrag("LeftButton")
            line:SetScript("OnEnter", function(self) if self.filled or dragFrom then self.hl:Show() end end)
            line:SetScript("OnLeave", function(self) self.hl:Hide() end)
            line:SetScript("OnDragStart", function(self)
                if not self.filled then return end
                dragFrom = self.pos
                local gh = getGhost()
                gh.text:SetText(self.plain)
                gh:Show()
            end)
            line:SetScript("OnDragStop", function() SRT:Call("roster drop", drop) end)
            b.lines[i] = line
        end
        boxes[g] = b
        return b
    end
    local legend = label(grid, LEGEND, -2, "textDim")
    local extra = label(grid, "", -2, "textDim")
    extra:SetWordWrap(true)
    local summary = label(grid, "", -1, "textDim")
    summary:SetPoint("BOTTOMLEFT", 0, 6)
    local sortBtn = W.Button(grid, "Sort groups", "accent", function() Invites.Sort() end)
    sortBtn:SetPoint("BOTTOMRIGHT")
    local inviteMissing = W.Button(grid, "Invite missing", nil, function() Invites.InviteRosterMissing() end)
    inviteMissing:SetPoint("RIGHT", sortBtn, "LEFT", -10, 0)
    summary:SetPoint("RIGHT", inviteMissing, "LEFT", -10, 0)

    local empty = label(grid, "Paste the roster on the left: names top to bottom, five per group\n"
        .. "(blank lines are ignored). \"Name/Other\" means either of them, \"-\" an empty place.\n"
        .. "Then drag names between the groups; in a raid the players move too.", 0, "textDim")
    empty:SetPoint("TOPLEFT", 0, -4)
    empty:SetPoint("RIGHT")
    empty:SetJustifyV("TOP")
    empty:SetWordWrap(true)

    local function refreshGroups()
        if not paste.edit:HasFocus() then paste.edit:SetText(SRT.db.roster.text or "") end
        local slots = Invites.Roster()
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
                    b.lines[i].fs:SetText("")
                    b.lines[i].filled = nil
                end
            end
        end
        local counts = { raid = 0, right = 0, guild = 0, offline = 0, unknown = 0, ambiguous = 0, self = 0, empty = 0 }
        local listed = {}
        for i, slot in ipairs(slots) do
            local b = boxes[slot.group]
            local line = b.lines[(i - 1) % 5 + 1]
            local fs = line.fs
            local text = table.concat(slot.names, "/")
            line.plain = text
            line.filled = not slot.empty
            if slot.state == "empty" then
                text = ""
            elseif slot.state == "self" then
                fs:SetTextColor(Theme:Color("text"))
                text = text .. "  |cff7c858f(you)|r"
            elseif slot.state == "raid" then
                listed[slot.member.index] = true
                counts.raid = counts.raid + 1
                if slot.member.group == slot.group then
                    counts.right = counts.right + 1
                    fs:SetTextColor(Theme:Color("good"))
                else
                    text = text .. "  |cff7c858f(g" .. slot.member.group .. ")|r"
                    fs:SetTextColor(Theme:Color("text"))
                end
            else
                counts[slot.state] = counts[slot.state] + 1
                fs:SetTextColor(Theme:Color(STATE_COLOR[slot.state]))
                if slot.state == "guild" then text = text .. "  |cff7c858f(invite)|r" end
            end
            fs:SetText(text)
        end
        -- Raid members who are not on the roster.
        local others = {}
        for _, m in ipairs(SRT.Compat.RaidRoster()) do
            if not listed[m.index] then others[#others + 1] = m.name end
        end
        local rows = ceil(groups / cols)
        legend:ClearAllPoints()
        legend:SetPoint("TOPLEFT", 0, -(rows * (boxH + GAP) + 2))
        legend:SetShown(groups > 0)
        extra:ClearAllPoints()
        extra:SetPoint("TOPLEFT", legend, "BOTTOMLEFT", 0, -10)
        extra:SetPoint("RIGHT")
        extra:SetText(#others > 0 and ("Not on the roster: " .. table.concat(others, ", ")) or "")
        if groups == 0 then
            summary:SetText("")
        else
            summary:SetText(("%d/%d in raid \194\183 %d in their group \194\183 %d to invite"):format(
                counts.raid, #slots, counts.right, counts.guild))
        end
        local lead = not SRT.Compat.IsLeaderOrAssist() and "Only the raid leader or an assistant can do this." or nil
        inviteMissing:SetLabel(("Invite missing (%d)"):format(counts.guild))
        inviteMissing:SetDisabled((not Invites.CanInvite() and "Only the raid leader or an assistant can invite.")
            or (counts.guild == 0 and "Nobody on the roster is online in the guild and missing from the raid.") or nil)
        sortBtn:SetLabel(Invites.IsSorting() and "Sorting..." or "Sort groups")
        sortBtn:SetDisabled((not IsInRaid() and "Sorting needs a raid.") or lead
            or (Invites.IsSorting() and "Sorting is running.") or (counts.raid == 0 and "Nobody on the roster is in the raid.") or nil)
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
