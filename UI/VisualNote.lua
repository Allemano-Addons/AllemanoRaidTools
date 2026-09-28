-- Visual note: the drawing page (Plan > Visual note) and the viewer window everyone sees
-- when a visual note is shared.
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets
local Main, VN = SRT.Main, SRT.VisualNote

local PAD = 26
local MIN_STEP = 25 -- note units between two pen points while drawing

local TOOLS = {
    { value = "p", label = "Pen" }, { value = "l", label = "Line" }, { value = "a", label = "Arrow" },
    { value = "i", label = "Icon" }, { value = "t", label = "Text" }, { value = "e", label = "Erase" },
}

-- Cursor position in note coordinates (0..4095), nil when outside the canvas.
local function cursorIn(c)
    local x, y = GetCursorPosition()
    local s = c:GetEffectiveScale()
    local left, top, w, h = c:GetLeft(), c:GetTop(), c:GetWidth(), c:GetHeight()
    if not left or w <= 0 or h <= 0 then return nil end
    local nx = (x / s - left) / w * VN.MAX
    local ny = (top - y / s) / h * VN.MAX
    return max(0, min(VN.MAX, nx)), max(0, min(VN.MAX, ny))
end

-- ---------------------------------------------------------------------------
-- Drawing page
-- ---------------------------------------------------------------------------

Main.RegisterPage("visualnote", function(page)
    local refresh
    local tool, color, width, icon = "p", 1, 2, 8
    local function draft() return VN.Draft() end

    -- Row 1: saved drawings, save, delete, show, send.
    local saved = W.Dropdown(page, 170, function()
        local opts = {}
        for _, n in ipairs(VN.SavedNames()) do opts[#opts + 1] = { value = n, label = n } end
        return opts
    end, function(name) VN.Load(name) end)
    saved:SetPoint("TOPLEFT", PAD, -20)
    local nameEdit = W.EditBox(page, "Name", 26)
    nameEdit:SetWidth(140)
    nameEdit:SetMaxLetters(40)
    nameEdit:SetPoint("LEFT", saved, "RIGHT", 10, 0)
    local saveBtn = W.Button(page, "Save", nil, function()
        local name = strtrim(nameEdit:GetText())
        if name == "" then SRT:Print("Give the drawing a name first.") return end
        VN.Save(name)
        SRT:Print(("Saved \"%s\"."):format(name))
    end, 26)
    saveBtn:SetPoint("LEFT", nameEdit, "RIGHT", 6, 0)
    local deleteBtn = W.Button(page, "Delete", nil, function()
        local name = saved.value
        if name then W.Confirm(("Delete the drawing \"%s\"?"):format(name), "Delete", function() VN.Delete(name) end) end
    end, 26)
    deleteBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    local sendBtn = W.Button(page, "Send to raid", "accent", function() VN.Send() end, 26)
    sendBtn:SetPoint("TOPRIGHT", -PAD, -20)

    -- Row 2: tool, colors, width, undo, clear.
    local tools = W.Segment(page, TOOLS, function(v)
        tool = v
        refresh()
    end)
    tools:SetPoint("TOPLEFT", PAD, -56)
    local swatches = {}
    for i, hex in ipairs(VN.COLORS) do
        local sw = W.Swatch(page, hex, function()
            color = i
            refresh()
        end)
        sw:SetPoint("LEFT", tools, "RIGHT", 14 + (i - 1) * 24, 0)
        swatches[i] = sw
    end
    local widths = W.Segment(page, { { value = 1, label = "S" }, { value = 2, label = "M" }, { value = 3, label = "L" } },
        function(v) width = v end)
    widths:SetPoint("LEFT", swatches[#swatches], "RIGHT", 14, 0)
    local clearBtn = W.Button(page, "Clear", nil, function()
        W.Confirm("Remove everything from the drawing?", "Clear", function()
            draft().items = {}
            VN.Changed()
        end)
    end, 24)
    clearBtn:SetPoint("TOPRIGHT", -PAD, -56)
    local undoBtn = W.Button(page, "Undo", nil, function()
        tremove(draft().items)
        VN.Changed()
    end, 24)
    undoBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)

    -- Row 3: background, and the icon to place.
    local bgSeg = W.Segment(page, { { value = "none", label = "No background" }, { value = "map", label = "Current map" },
        { value = "image", label = "Picture" } }, function(v)
        local bg = draft().bg
        bg.kind = v
        if v == "map" then
            local mapID = C_Map and C_Map.GetBestMapForUnit("player")
            bg.ref = mapID
            if not mapID then SRT:Print("No map here.") end
        elseif v == "image" then
            bg.ref = nil
        else
            bg.ref = nil
        end
        VN.Changed()
    end)
    bgSeg:SetPoint("TOPLEFT", PAD, -90)
    local imageEdit = W.EditBox(page, "Picture name (Images folder)", 24)
    imageEdit:SetWidth(200)
    imageEdit:SetMaxLetters(40)
    imageEdit:SetPoint("LEFT", bgSeg, "RIGHT", 10, 0)
    imageEdit:SetScript("OnEnterPressed", function(self)
        local name = strlower(strtrim(self:GetText())):gsub("%.tga$", ""):gsub("[^%w_%-]", "")
        draft().bg.kind, draft().bg.ref = "image", name ~= "" and name or nil
        self:ClearFocus()
        VN.Changed()
    end)
    imageEdit.tip = { "Type the file name and press Enter, e.g. ony_p2",
        "The file SlaughterRaidTools\\Images\\ony_p2.tga must exist for everyone who should see it.",
        "Tools\\img2tga.ps1 makes one from a screenshot. Restart WoW after adding files." }
    imageEdit:HookScript("OnEnter", function(self) W.ShowTooltip(self, self.tip) end)
    imageEdit:HookScript("OnLeave", function() W.HideTooltip() end)
    imageEdit:EnableMouse(true)
    local iconButtons = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(22, 22)
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        b.border = W.Border(b, "line")
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", 3, -3)
        t:SetPoint("BOTTOMRIGHT", -3, 3)
        t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
        b:SetPoint("TOPRIGHT", -PAD - (8 - i) * 25, -91)
        b:SetScript("OnClick", function()
            icon = i
            refresh()
        end)
        iconButtons[i] = b
    end

    -- Canvas.
    local canvas = VN.CreateCanvas(page)
    canvas:EnableMouse(true)
    W.Border(canvas, "line")
    local status = W.Text(page, -2, "textFaint")
    status:SetPoint("BOTTOMLEFT", PAD, 14)
    local help = W.Text(page, -2, "textFaint")
    help:SetPoint("BOTTOMRIGHT", -PAD, 14)

    -- Preview for lines and arrows while dragging.
    local preview = canvas:CreateLine(nil, "OVERLAY")
    preview:Hide()

    -- Text entry at the clicked spot.
    local textEdit = W.EditBox(canvas, "Text, Enter to place", 24)
    textEdit:SetWidth(180)
    textEdit:SetMaxLetters(60)
    textEdit:Hide()
    textEdit:SetScript("OnEnterPressed", function(self)
        local s = strtrim(self:GetText())
        if s ~= "" and self.at then
            tinsert(draft().items, { k = "t", c = color, x = self.at[1], y = self.at[2], s = s })
            VN.Changed()
        end
        self:SetText("")
        self:ClearFocus()
        self:Hide()
    end)
    textEdit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        self:Hide()
    end)

    local drawing -- the stroke / line being drawn
    local function finishStroke()
        local d = drawing
        drawing = nil
        canvas:SetScript("OnUpdate", nil)
        preview:Hide()
        if not d then return end
        if d.k == "p" then
            d.pts = VN.Simplify(d.pts)
            tinsert(draft().items, d)
        elseif (d.x2 - d.x1) ^ 2 + (d.y2 - d.y1) ^ 2 > 40 * 40 then
            tinsert(draft().items, d)
        end
        VN.Changed()
    end

    canvas:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local x, y = cursorIn(self)
        if not x then return end
        if tool == "i" then
            tinsert(draft().items, { k = "i", n = icon, x = x, y = y })
            VN.Changed()
        elseif tool == "t" then
            textEdit.at = { x, y }
            textEdit:ClearAllPoints()
            textEdit:SetPoint("CENTER", self, "TOPLEFT", x / VN.MAX * self:GetWidth(), -y / VN.MAX * self:GetHeight())
            textEdit:Show()
            textEdit:SetFocus()
        elseif tool == "e" then
            local i = VN.HitTest(draft(), x, y)
            if i then
                tremove(draft().items, i)
                VN.Changed()
            end
        elseif tool == "p" then
            drawing = { k = "p", c = color, w = width, pts = { x, y } }
            self:SetScript("OnUpdate", function(c)
                local nx, ny = cursorIn(c)
                local p = drawing and drawing.pts
                if not nx or not p then return end
                local lx, ly = p[#p - 1], p[#p]
                if (nx - lx) ^ 2 + (ny - ly) ^ 2 >= MIN_STEP * MIN_STEP then
                    p[#p + 1], p[#p + 2] = nx, ny
                    VN.DrawSegment(c, drawing, lx, ly, nx, ny)
                end
            end)
        else -- line / arrow
            drawing = { k = tool, c = color, w = width, x1 = x, y1 = y, x2 = x, y2 = y }
            local r, g, b = Theme.Hex(VN.COLORS[color])
            preview:SetColorTexture(r, g, b, 0.8)
            preview:SetThickness(VN.WIDTHS[width] * self:GetWidth() / 800)
            self:SetScript("OnUpdate", function(c)
                local nx, ny = cursorIn(c)
                if not nx or not drawing then return end
                drawing.x2, drawing.y2 = nx, ny
                local cw, ch = c:GetWidth(), c:GetHeight()
                preview:SetStartPoint("TOPLEFT", c, drawing.x1 / VN.MAX * cw, -drawing.y1 / VN.MAX * ch)
                preview:SetEndPoint("TOPLEFT", c, nx / VN.MAX * cw, -ny / VN.MAX * ch)
                preview:Show()
            end)
        end
    end)
    canvas:SetScript("OnMouseUp", function() SRT:Call("visual note draw", finishStroke) end)
    canvas:SetScript("OnHide", function() SRT:Call("visual note draw", finishStroke) end)

    local HELP = { p = "Hold the left button and draw.", l = "Drag to draw a line.", a = "Drag to draw an arrow.",
        i = "Pick an icon on the right, then click to place it.", t = "Click where the text goes, type, Enter.",
        e = "Click a stroke, icon or text to remove it." }

    function refresh()
        local d = draft()
        -- Canvas: 2:1, as big as the page allows.
        local pw, ph = page:GetWidth(), page:GetHeight()
        local cw = min(pw - PAD * 2, (ph - 124 - 40) * 2)
        cw = max(200, cw)
        canvas:ClearAllPoints()
        canvas:SetPoint("TOP", page, "TOP", 0, -124)
        canvas:SetSize(cw, cw / 2)
        local lines = VN.Render(canvas, d)
        tools:Set(tool)
        widths:Set(width)
        for i, sw in ipairs(swatches) do sw:SetSelected(i == color) end
        bgSeg:Set(d.bg.kind or "none")
        imageEdit:SetShown(d.bg.kind == "image")
        if not imageEdit:HasFocus() then imageEdit:SetText(d.bg.kind == "image" and d.bg.ref or "") end
        imageEdit.placeholder:SetShown(imageEdit:GetText() == "")
        for i, b in ipairs(iconButtons) do
            b:SetShown(tool == "i")
            local r, g, bl
            if i == icon then r, g, bl = Theme:Accent() else r, g, bl = Theme:Color("line") end
            for _, side in pairs(b.border) do side:SetColorTexture(r, g, bl, 1) end
        end
        saved:Set(d.title ~= "" and d.title or nil)
        if d.title == "" then saved.text:SetText("Saved drawings") end
        if not nameEdit:HasFocus() then nameEdit:SetText(d.title or "") end
        nameEdit.placeholder:SetShown(nameEdit:GetText() == "")
        deleteBtn:SetDisabled(not saved.value and "Load a saved drawing first." or nil)
        local bytes = #VN.Encode(d)
        status:SetText(("%d item%s \194\183 %.1f kB of %d kB \194\183 %d lines drawn"):format(#d.items, #d.items == 1 and "" or "s",
            bytes / 1000, VN.MAX_BYTES / 1000, lines))
        status:SetTextColor(Theme:Color(bytes > VN.MAX_BYTES and "bad" or "textFaint"))
        help:SetText(HELP[tool] or "")
        sendBtn:SetLabel(IsInGroup() and "Send to raid" or "Show to me")
        undoBtn:SetDisabled(#d.items == 0 and "Nothing to undo." or nil)
    end

    VN.OnChange(function() if page:IsShown() then refresh() end end)
    page:SetScript("OnSizeChanged", function() if page:IsShown() then refresh() end end)
    return refresh
end)

-- ---------------------------------------------------------------------------
-- Viewer: the shared visual note, for everyone. Moves, resizes (2:1), stays through ESC.
-- ---------------------------------------------------------------------------

local Viewer = {}
SRT.VisualViewer = Viewer

local TITLE_H = 24
local viewer

local function saved() return SRT.db.visual.viewer end

local function buildViewer()
    viewer = CreateFrame("Frame", nil, UIParent)
    viewer:SetFrameStrata("MEDIUM")
    viewer:SetClampedToScreen(true)
    viewer:SetMovable(true)
    viewer:SetResizable(true)
    if viewer.SetResizeBounds then viewer:SetResizeBounds(240, 120 + TITLE_H, 1600, 800 + TITLE_H) end
    local s = saved()
    local w = s.w or 480
    viewer:SetSize(w, w / 2 + TITLE_H)
    viewer:SetPoint(s.point or "CENTER", UIParent, s.rel or s.point or "CENTER", s.x or 0, s.y or 0)
    viewer.bg = W.Fill(viewer, "window", 0.95)
    viewer.bg:SetAllPoints()
    W.Border(viewer, "line")
    local bar = CreateFrame("Frame", nil, viewer)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    local function save()
        local point, _, rel, x, y = viewer:GetPoint(1)
        s.point, s.rel, s.x, s.y, s.w = point, rel, x, y, floor(viewer:GetWidth() + 0.5)
    end
    bar:SetScript("OnDragStart", function() viewer:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        viewer:StopMovingOrSizing()
        save()
    end)
    local square = bar:CreateTexture(nil, "ARTWORK")
    square:SetSize(6, 6)
    square:SetPoint("LEFT", 8, 0)
    W.OnAccent(function(r, g, b) square:SetColorTexture(r, g, b, 1) end)
    viewer.title = W.Text(bar, -1, "text")
    viewer.title:SetPoint("LEFT", square, "RIGHT", 6, 0)
    viewer.title:SetPoint("RIGHT", -30, 0)
    local close = W.CloseButton(bar, function() Viewer.Hide() end)
    close:SetPoint("RIGHT", -2, 0)
    viewer.canvas = VN.CreateCanvas(viewer)
    viewer.canvas:SetPoint("TOPLEFT", 1, -TITLE_H)
    viewer.canvas:SetPoint("BOTTOMRIGHT", -1, 1)
    local grip = CreateFrame("Button", nil, viewer)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(viewer:GetFrameLevel() + 10)
    for _, d in ipairs({ { 9, 1 }, { 5, 5 }, { 9, 5 }, { 1, 9 }, { 5, 9 }, { 9, 9 } }) do
        local t = grip:CreateTexture(nil, "OVERLAY")
        t:SetSize(2, 2)
        t:SetPoint("TOPLEFT", d[1], -d[2])
        t:SetColorTexture(Theme:Color("textFaint"))
    end
    grip:SetScript("OnMouseDown", function() viewer:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        viewer:StopMovingOrSizing()
        -- Keep 2:1.
        viewer:SetHeight(viewer:GetWidth() / 2 + TITLE_H)
        save()
        Viewer.Refresh()
    end)
    viewer:Hide()
end

function Viewer.Refresh()
    if not viewer or not viewer:IsShown() then return end
    local note, info = VN.Received()
    if note then
        viewer.title:SetText(("%s  |cff7c858ffrom %s, %s|r"):format(note.title ~= "" and note.title or "Visual note",
            info.sender or "?", date("%H:%M", info.at or time())))
    else
        viewer.title:SetText("Visual note  |cff7c858fnothing shared yet|r")
    end
    VN.Render(viewer.canvas, note)
end

function Viewer.Show()
    if not viewer then buildViewer() end
    saved().shown = true
    viewer:Show()
    Viewer.Refresh()
end

function Viewer.Hide()
    saved().shown = nil
    if viewer then viewer:Hide() end
end

function Viewer.Toggle()
    if viewer and viewer:IsShown() then Viewer.Hide() else Viewer.Show() end
end

function Viewer.IsShown() return viewer ~= nil and viewer:IsShown() end

VN.OnChange(Viewer.Refresh)
SRT:OnReady(function() if saved().shown and VN.Received() then Viewer.Show() end end)
