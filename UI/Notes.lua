-- Notes page: the leader's saved notes (list + editor + send) and the personal note.
-- Everything saves while typing.
local _, ART = ...

local Theme, W = ART.Theme, ART.Widgets
local Main, Notes = ART.Main, ART.Notes

local PAD, LIST_W, ROW_H = 26, 190, 40

local HELP = {
    "Formatting",
    "{rt1} .. {rt8} or {skull}, {cross}, {star}... raid icons",
    "{spell:12345} spell icon",
    "{p:Name, Other Name} ... {/p} only these players see it",
    "Names of group members get their class color.",
}

-- Small square button showing a raid icon.
local function iconButton(parent, i, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.bg = W.Fill(b, "field", 1)
    b.bg:SetAllPoints()
    W.Border(b, "line")
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 4, -4)
    t:SetPoint("BOTTOMRIGHT", -4, 4)
    t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(Theme:Color("selected"))
        W.ShowTooltip(self, "Insert {rt" .. i .. "}")
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(Theme:Color("field"))
        W.HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

Main.RegisterPage("notes", function(page)
    local raidView = CreateFrame("Frame", nil, page)
    local personalView = CreateFrame("Frame", nil, page)
    for _, v in ipairs({ raidView, personalView }) do
        v:SetPoint("TOPLEFT", 0, -56)
        v:SetPoint("BOTTOMRIGHT")
    end

    local mode = "raid"
    local refresh
    local tabs = W.Segment(page, { { value = "raid", label = "Raid notes" }, { value = "personal", label = "Personal note" } },
        function(v)
            mode = v
            refresh()
        end)
    tabs:SetPoint("TOPLEFT", PAD, -20)

    local windowBtn = W.Button(page, "Show note window", nil, function()
        ART.NoteWindow.Toggle()
        refresh()
    end, 24)
    windowBtn:SetPoint("TOPRIGHT", -PAD, -20)

    -- Raid notes: list ------------------------------------------------------------
    local newBtn = W.Button(raidView, "New note", nil, function()
        Notes.New()
    end, 26)
    newBtn:SetPoint("TOPLEFT", PAD, 0)
    newBtn:SetWidth(LIST_W)

    local list = CreateFrame("Frame", nil, raidView)
    list:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -8)
    list:SetPoint("BOTTOM", 0, 20)
    list:SetWidth(LIST_W)
    list.bg = W.Fill(list, "field", 1)
    list.bg:SetAllPoints()
    W.Border(list, "line")
    local offset = 0
    local rows = {}
    local function row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * ROW_H)
        r.bg = W.Fill(r, "selected", 1)
        r.bg:SetAllPoints()
        r.bg:Hide()
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        W.OnAccent(function(cr, cg, cb) r.mark:SetColorTexture(cr, cg, cb, 1) end)
        r.title = W.Text(r, 0, "text")
        r.title:SetPoint("TOPLEFT", 12, -7)
        r.title:SetPoint("RIGHT", -8, 0)
        r.sub = W.Text(r, -2, "textFaint")
        r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
        W.Line(r, "bottom", "line")
        r:SetScript("OnClick", function(self) Notes.Select(self.id) end)
        rows[i] = r
        return r
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = max(0, min(#Notes.List() - 1, offset - delta))
        refresh()
    end)

    -- Raid notes: editor ------------------------------------------------------------
    local editor = CreateFrame("Frame", nil, raidView)
    editor:SetPoint("TOPLEFT", LIST_W + PAD + 16, 0)
    editor:SetPoint("BOTTOMRIGHT", -PAD, 20)

    local current -- the note being edited
    local title = W.EditBox(editor, "Title", 28)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetMaxLetters(60)

    local toolbar = CreateFrame("Frame", nil, editor)
    toolbar:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    toolbar:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -8)
    toolbar:SetHeight(26)

    local body = W.MultiEdit(editor, function(text)
        if current then Notes.Save(current.id, title:GetText(), text) end
    end)
    body:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    body:SetPoint("BOTTOMRIGHT", 0, 44)
    title:SetScript("OnTextChanged", function(self, user)
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        if user and current then
            Notes.Save(current.id, self:GetText(), body.edit:GetText())
            refresh()
        end
    end)
    title:SetScript("OnEnterPressed", function() body.edit:SetFocus() end)

    local function insert(s)
        body.edit:SetFocus()
        body.edit:Insert(s)
        if current then Notes.Save(current.id, title:GetText(), body.edit:GetText()) end
    end
    for i = 1, 8 do
        local b = iconButton(toolbar, i, function() insert("{rt" .. i .. "}") end)
        b:SetPoint("LEFT", (i - 1) * 28, 0)
    end
    local names
    names = W.Dropdown(toolbar, 150, function()
        local opts = {}
        for _, m in ipairs(ART.Compat.GroupMembers()) do opts[#opts + 1] = { value = m.name, label = m.name } end
        sort(opts, function(a, b) return a.label < b.label end)
        return opts
    end, function(name)
        insert(name)
        names.text:SetText("Insert name")
    end)
    names:SetPoint("LEFT", 8 * 28 + 8, 0)
    names.text:SetText("Insert name")
    local help = W.Link(toolbar, "Formatting")
    help:SetPoint("RIGHT", 0, 0)
    help:SetScript("OnEnter", function(self) W.ShowTooltip(self, HELP) end)
    help:SetScript("OnLeave", function() W.HideTooltip() end)

    local status = W.Text(editor, -1, "textDim")
    status:SetPoint("BOTTOMLEFT", 0, 8)
    status:SetPoint("RIGHT", editor, "CENTER", 0, 0)
    local send = W.Button(editor, "Send to raid", "accent", function()
        if current then Notes.Send(current.id) end
    end)
    send:SetPoint("BOTTOMRIGHT", 0, 0)
    local post = W.Button(editor, "Post in raid chat", nil, function()
        if current then Notes.PostToChat(current.text) end
    end)
    post:SetPoint("RIGHT", send, "LEFT", -10, 0)
    local delete = W.Button(editor, "Delete", nil, function()
        if current then
            W.Confirm(("Delete the note \"%s\"?"):format(current.title), "Delete", function() Notes.Delete(current.id) end)
        end
    end)
    delete:SetPoint("RIGHT", post, "LEFT", -10, 0)

    local empty = W.Text(raidView, 0, "textDim")
    empty:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -4)
    empty:SetText("No notes yet. \"New note\" starts one.")

    -- Personal note ---------------------------------------------------------------------
    local pInfo = W.Text(personalView, 0, "textDim")
    pInfo:SetPoint("TOPLEFT", PAD, 0)
    pInfo:SetText("Only you see this note. It is shown under the raid note in the note window.")
    local pToggle = W.Toggle(personalView, function(on) ART:SetSetting("notePersonal", on) end)
    pToggle:SetPoint("TOPRIGHT", -PAD, 0)
    local pLabel = W.Text(personalView, -1, "textDim")
    pLabel:SetPoint("RIGHT", pToggle, "LEFT", -8, 0)
    pLabel:SetText("Show in note window")
    local personal = W.MultiEdit(personalView, function(text)
        Notes.SetPersonal(text)
        ART.NoteWindow.Refresh()
    end)
    personal:SetPoint("TOPLEFT", PAD, -30)
    personal:SetPoint("BOTTOMRIGHT", -PAD, 20)

    local function statusText()
        local s = Notes.Status()
        if not IsInGroup() then return "Not in a group: Send shows the note only to you." end
        if not Notes.CanSend() then return "Only the raid leader or an assistant can send notes." end
        if not s then return "Not sent yet." end
        return ("Sent \"%s\" %s \194\183 %d of %d have it"):format(s.title, date("%H:%M", s.at), s.have, s.total)
    end

    function refresh()
        tabs:Set(mode)
        raidView:SetShown(mode == "raid")
        personalView:SetShown(mode == "personal")
        windowBtn:SetLabel(ART.NoteWindow.IsShown() and "Hide note window" or "Show note window")
        if mode == "personal" then
            if not personal.edit:HasFocus() then personal.edit:SetText(Notes.Personal()) end
            pToggle:Set(ART.db.settings.notePersonal)
            return
        end
        local all = Notes.List()
        offset = max(0, min(offset, #all - 1))
        local visible = max(1, floor((list:GetHeight() - 2) / ROW_H))
        local selected = Notes.Selected()
        for i = 1, max(visible, #rows) do
            local n = i <= visible and all[offset + i]
            local r = (n or rows[i]) and row(i)
            if r then
                r:SetShown(n and true or false)
                if n then
                    r.id = n.id
                    r.title:SetText(n.title ~= "" and n.title or "(untitled)")
                    r.sub:SetText(date("%d/%m %H:%M", n.updated or time()))
                    local on = selected and selected.id == n.id
                    r.bg:SetShown(on)
                    r.mark:SetShown(on)
                end
            end
        end
        -- A different note selected: load it into the editor.
        if selected ~= current then
            current = selected
            title:SetText(current and current.title or "")
            body.edit:SetText(current and current.text or "")
            title.placeholder:SetShown(title:GetText() == "" and not title:HasFocus())
        end
        editor:SetShown(current ~= nil)
        empty:SetShown(current == nil)
        status:SetText(statusText())
        local lead = IsInGroup() and not Notes.CanSend() and "Only the raid leader or an assistant can send notes." or nil
        send:SetDisabled(lead)
        send:SetLabel(IsInGroup() and "Send to raid" or "Show to me")
        post:SetDisabled(not IsInGroup() and "Join a group first." or lead)
    end

    Notes.OnChange(function() if page:IsShown() then refresh() end end)
    page:SetScript("OnSizeChanged", function() if page:IsShown() then refresh() end end)
    return refresh
end)
