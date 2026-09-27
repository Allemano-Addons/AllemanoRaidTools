-- Widgets: flat building blocks copied from AltBoard (Hush look, no Blizzard textures).
local _, SRT = ...

local Theme = SRT.Theme

local W = {}
SRT.Widgets = W

-- Pixel-sized textures, re-sized when the UI scale changes.
local pixelItems = {}

local function applyPixel(item)
    local px = Theme:Pixel(item.frame)
    if item.axis == "h" then item.tex:SetHeight(px * item.n) else item.tex:SetWidth(px * item.n) end
end

function W.PixelSize(tex, frame, axis, n)
    local item = { tex = tex, frame = frame, axis = axis, n = n or 1 }
    pixelItems[#pixelItems + 1] = item
    applyPixel(item)
end

local function refreshPixels()
    for i = 1, #pixelItems do applyPixel(pixelItems[i]) end
end
SRT:RegisterEvent("UI_SCALE_CHANGED", refreshPixels)
SRT:RegisterEvent("DISPLAY_SIZE_CHANGED", refreshPixels)

function W.Fill(frame, colorKey, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    local r, g, b = Theme:Color(colorKey)
    t:SetColorTexture(r, g, b, alpha or 1)
    return t
end

-- A 1 px line along one side of frame.
function W.Line(frame, side, colorKey, layer)
    local t = W.Fill(frame, colorKey or "line", 1, layer or "BORDER")
    if side == "top" or side == "bottom" then
        local p = side == "top" and "TOP" or "BOTTOM"
        t:SetPoint(p .. "LEFT")
        t:SetPoint(p .. "RIGHT")
        W.PixelSize(t, frame, "h")
    else
        local p = side == "left" and "LEFT" or "RIGHT"
        t:SetPoint("TOP" .. p)
        t:SetPoint("BOTTOM" .. p)
        W.PixelSize(t, frame, "w")
    end
    return t
end

function W.Border(frame, colorKey)
    local b = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do b[side] = W.Line(frame, side, colorKey) end
    return b
end

-- Every text is registered so a font / size change applies at once.
local fontItems = {}

function W.Text(parent, delta, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Theme:SetFont(fs, delta)
    fs:SetTextColor(Theme:Color(colorKey or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fontItems[#fontItems + 1] = { fs = fs, delta = delta }
    return fs
end

function W.RefreshFonts()
    for i = 1, #fontItems do Theme:SetFont(fontItems[i].fs, fontItems[i].delta) end
end

-- Accent: fn(r, g, b) now and on every accent change.
local accentFns = {}
function W.OnAccent(fn)
    accentFns[#accentFns + 1] = fn
    fn(Theme:Accent())
end

function W.ApplyAccent()
    local r, g, b = Theme:Accent()
    for i = 1, #accentFns do accentFns[i](r, g, b) end
end

SRT:OnSettingChanged(function(key)
    if key == "font" or key == "textSize" then
        W.RefreshFonts()
    elseif key == "useClassColor" or key == "accent" then
        W.ApplyAccent()
    end
end)

-- Own flat tooltip. lines = string or { "line", "line", ... }.
local tip
function W.ShowTooltip(owner, lines)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        tip.bg = W.Fill(tip, "field", 0.98)
        tip.bg:SetAllPoints()
        W.Border(tip, "line")
        tip.text = W.Text(tip, -1, "text")
        tip.text:SetWordWrap(true)
        tip.text:SetSpacing(3)
        tip.text:SetPoint("TOPLEFT", 8, -6)
    end
    tip.text:SetText(type(lines) == "table" and table.concat(lines, "\n") or lines)
    tip.text:SetWidth(0)
    local w = min(tip.text:GetStringWidth() + 2, 320)
    tip.text:SetWidth(w)
    tip:SetSize(w + 16, tip.text:GetStringHeight() + 12)
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    tip:Show()
end

function W.HideTooltip()
    if tip then tip:Hide() end
end

-- Small square button with an "x" (text glyph: Friz Quadrata lacks fancy symbols).
function W.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.text = W.Text(b, 1, "textDim")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText("x")
    b:SetScript("OnEnter", function(self)
        self.bg:Show()
        self.text:SetTextColor(Theme:Color("text"))
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:Hide()
        self.text:SetTextColor(Theme:Color("textDim"))
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Icons drawn from rectangles in a 10x10 box: { { x, y, w, h }, ... } from the top-left.
local ICON_RECTS = {
    -- Hush's "settings": three sliders with knobs.
    settings = {
        { 0, 1, 10, 1 }, { 1, -1, 2, 5 },
        { 0, 5, 10, 1 }, { 5, 3, 2, 5 },
        { 0, 9, 10, 1 }, { 3, 7, 2, 5 },
    },
    -- Magnifier: a 7x7 ring and a stepped handle.
    search = {
        { 0, 0, 7, 1 }, { 0, 6, 7, 1 }, { 0, 1, 1, 5 }, { 6, 1, 1, 5 },
        { 6, 6, 2, 2 }, { 7, 7, 2, 2 }, { 8, 8, 2, 2 },
    },
}

-- Square title-bar button with a drawn icon (see ICON_RECTS).
function W.IconButton(parent, iconName, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    b.bg:Hide()
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(10, 10)
    box:SetPoint("CENTER")
    b.parts = {}
    for _, r in ipairs(ICON_RECTS[iconName]) do
        local t = box:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", r[1], -r[2])
        t:SetSize(r[3], r[4])
        b.parts[#b.parts + 1] = t
    end
    local function color(key)
        local r, g, bl = Theme:Color(key)
        for _, p in ipairs(b.parts) do p:SetColorTexture(r, g, bl, 1) end
    end
    color("textDim")
    b:SetScript("OnEnter", function(self)
        self.bg:Show()
        color("text")
        if tooltip then W.ShowTooltip(self, tooltip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:Hide()
        color("textDim")
        W.HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

function W.SettingsButton(parent, tooltip, onClick)
    return W.IconButton(parent, "settings", tooltip, onClick)
end

-- Flat single-line edit box with a placeholder (Hush's style).
function W.EditBox(parent, placeholder, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetHeight(height or 28)
    e:SetAutoFocus(false)
    Theme:SetFont(e)
    fontItems[#fontItems + 1] = { fs = e }
    e:SetTextColor(Theme:Color("text"))
    e:SetTextInsets(10, 10, 0, 0)
    e.bg = W.Fill(e, "field", 1)
    e.bg:SetAllPoints()
    e.border = W.Border(e, "line")
    e.placeholder = W.Text(e, 0, "textFaint")
    e.placeholder:SetPoint("LEFT", 10, 0)
    e.placeholder:SetText(placeholder or "")
    local function setBorder(r, g, b)
        for _, side in pairs(e.border) do side:SetColorTexture(r, g, b, 1) end
    end
    local function update(self)
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end
    e:SetScript("OnEditFocusGained", function(self)
        setBorder(Theme:Accent())
        update(self)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        setBorder(Theme:Color("line"))
        update(self)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:HookScript("OnTextChanged", update)
    return e
end

-- ---------------------------------------------------------------------------
-- Settings controls (same look as Hush's).
-- ---------------------------------------------------------------------------

function W.Toggle(parent, onChange)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(32, 16)
    t.track = t:CreateTexture(nil, "BACKGROUND")
    t.track:SetAllPoints()
    t.knob = t:CreateTexture(nil, "ARTWORK")
    t.knob:SetSize(12, 12)
    function t:Set(on)
        self.value = on and true or false
        self.knob:ClearAllPoints()
        if self.value then
            self.track:SetColorTexture(Theme:Accent())
            self.knob:SetColorTexture(Theme:Color("sidebar"))
            self.knob:SetPoint("RIGHT", -2, 0)
        else
            self.track:SetColorTexture(Theme:Color("line"))
            self.knob:SetColorTexture(Theme:Color("textDim"))
            self.knob:SetPoint("LEFT", 2, 0)
        end
    end
    W.OnAccent(function() if t.value ~= nil then t:Set(t.value) end end)
    t:SetScript("OnClick", function(self)
        self:Set(not self.value)
        if onChange then onChange(self.value) end
    end)
    t:Set(false)
    return t
end

-- options: { { value = "S", label = "S" }, ... }
function W.Segment(parent, options, onChange)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(24)
    s.buttons = {}
    local x = 0
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, s)
        b.value = opt.value
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        b.text = W.Text(b, -1, "textDim")
        b.text:SetPoint("CENTER")
        b.text:SetText(opt.label)
        local w = max(40, b.text:GetStringWidth() + 20)
        b:SetSize(w, 24)
        b:SetPoint("LEFT", x, 0)
        x = x + w + 2
        b:SetScript("OnClick", function(self)
            s:Set(self.value)
            if onChange then onChange(self.value) end
        end)
        b:SetScript("OnEnter", function(self) if self.value ~= s.value then self.text:SetTextColor(Theme:Color("text")) end end)
        b:SetScript("OnLeave", function() s:Set(s.value) end)
        s.buttons[i] = b
    end
    s:SetWidth(x - 2)
    W.Border(s, "line")
    function s:Set(value)
        self.value = value
        local r, g, bl = Theme:Accent()
        for _, b in ipairs(self.buttons) do
            if b.value == value then
                b.bg:SetColorTexture(r, g, bl, 1)
                b.text:SetTextColor(Theme:Color("sidebar"))
            else
                b.bg:SetColorTexture(Theme:Color("field"))
                b.text:SetTextColor(Theme:Color("textDim"))
            end
        end
    end
    W.OnAccent(function() if s.value ~= nil then s:Set(s.value) end end)
    return s
end

-- Horizontal slider. format(value) -> label text.
function W.Slider(parent, minV, maxV, step, width, format, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width or 200, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s.track = W.Fill(s, "line", 1, "BACKGROUND")
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.track:SetHeight(2)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    s:SetThumbTexture(thumb)
    W.OnAccent(function(r, g, b) thumb:SetColorTexture(r, g, b, 1) end)
    s.label = W.Text(s, -1, "textDim")
    s.label:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s.silent = false
    s:SetScript("OnValueChanged", function(self, value)
        value = floor(value / step + 0.5) * step
        self.label:SetText(format and format(value) or tostring(value))
        if not self.silent and onChange then onChange(value) end
    end)
    s:EnableMouseWheel(false)
    function s:Set(value)
        self.silent = true
        self:SetValue(value)
        self.label:SetText(format and format(value) or tostring(value))
        self.silent = false
    end
    return s
end

-- Dropdown: a field-styled button that opens a menu below itself.
-- getOptions() -> { { value, label, font = path (optional preview) }, ... }
function W.Dropdown(parent, width, getOptions, onChange)
    local d = CreateFrame("Button", nil, parent)
    d:SetSize(width or 200, 26)
    d.bg = W.Fill(d, "field", 1)
    d.bg:SetAllPoints()
    d.border = W.Border(d, "line")
    d.text = W.Text(d, 0, "text")
    d.text:SetPoint("LEFT", 10, 0)
    d.text:SetWidth((width or 200) - 30)
    d.arrow = W.Text(d, -2, "textDim")
    d.arrow:SetPoint("RIGHT", -10, 0)
    d.arrow:SetText("v")

    function d:Set(value)
        self.value = value
        local label = tostring(value)
        for _, opt in ipairs(getOptions()) do
            if opt.value == value then label = opt.label break end
        end
        self.text:SetText(label)
    end

    local function setBorder(key)
        local r, g, b = Theme:Color(key)
        for _, side in pairs(d.border) do side:SetColorTexture(r, g, b, 1) end
    end
    d:SetScript("OnEnter", function() setBorder("textFaint") end)
    d:SetScript("OnLeave", function() setBorder("line") end)
    d:SetScript("OnClick", function(self)
        if W.IsMenuOpen() then W.CloseMenus() return end
        local items = {}
        for _, opt in ipairs(getOptions()) do
            items[#items + 1] = {
                text = opt.label, font = opt.font, checked = opt.value == self.value,
                onClick = function()
                    self:Set(opt.value)
                    if onChange then onChange(opt.value) end
                end,
            }
        end
        W.OpenMenu(items, self)
    end)
    return d
end

-- Text button. style "accent" = filled with the accent (the main action), otherwise a
-- bordered dark button. b:SetDisabled(reason) greys it out; the reason is its tooltip.
function W.Button(parent, label, style, onClick, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height or 30)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.border = W.Border(b, "line")
    b.text = W.Text(b, 0, "text")
    b.text:SetPoint("CENTER")
    local hover = false
    local function paint()
        if style == "accent" then
            local r, g, bl = Theme:Accent()
            b.bg:SetColorTexture(r, g, bl, hover and 0.85 or 1)
            b.text:SetTextColor(Theme:Color("sidebar"))
            for _, side in pairs(b.border) do side:SetColorTexture(r, g, bl, 1) end
        else
            b.bg:SetColorTexture(Theme:Color(hover and "selected" or "field"))
            b.text:SetTextColor(Theme:Color("text"))
            local r, g, bl = Theme:Color(hover and "textFaint" or "line")
            for _, side in pairs(b.border) do side:SetColorTexture(r, g, bl, 1) end
        end
    end
    function b:SetLabel(text)
        self.text:SetText(text)
        self:SetWidth(max(60, self.text:GetStringWidth() + 28))
    end
    function b:SetDisabled(reason)
        self.disabledReason = reason
        self:SetAlpha(reason and 0.4 or 1)
    end
    b:SetScript("OnEnter", function(self)
        hover = not self.disabledReason
        paint()
        if self.disabledReason then W.ShowTooltip(self, self.disabledReason)
        elseif self.tooltip then W.ShowTooltip(self, self.tooltip) end
    end)
    b:SetScript("OnLeave", function()
        hover = false
        paint()
        W.HideTooltip()
    end)
    b:SetScript("OnClick", function(self)
        if self.disabledReason then return end
        if onClick then SRT:Call("button " .. tostring(label), onClick, self) end
    end)
    b:SetLabel(label)
    W.OnAccent(paint)
    return b
end

-- Underlined accent text link.
function W.Link(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.text = W.Text(b, -1, "text")
    b.text:SetPoint("RIGHT")
    b.text:SetText(label)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -1)
    b.line:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 0, -1)
    W.PixelSize(b.line, b, "h")
    b:SetSize(b.text:GetStringWidth() + 2, 16)
    W.OnAccent(function(r, g, bl)
        b.text:SetTextColor(r, g, bl)
        b.line:SetColorTexture(r, g, bl, 0.7)
    end)
    b:SetScript("OnClick", function() if onClick then SRT:Call("link " .. label, onClick) end end)
    return b
end

-- Card: a bordered box with an accent heading and an optional link at the top right.
-- dashed = a faint placeholder card.
function W.Card(parent, title, linkLabel, onLink, dashed)
    local c = CreateFrame("Frame", nil, parent)
    c.bg = W.Fill(c, dashed and "window" or "field", 1)
    c.bg:SetAllPoints()
    c.border = W.Border(c, "line")
    if dashed then
        for _, side in pairs(c.border) do side:SetAlpha(0.6) end
    end
    c.title = W.Text(c, -2, "text")
    c.title:SetPoint("TOPLEFT", 18, -18)
    c.title:SetText(strupper(title))
    if dashed then
        c.title:SetTextColor(Theme:Color("textDim"))
    else
        W.OnAccent(function(r, g, b) c.title:SetTextColor(r, g, b) end)
    end
    if linkLabel then
        c.link = W.Link(c, linkLabel, onLink)
        c.link:SetPoint("TOPRIGHT", -18, -15)
    end
    -- Body text (wraps).
    c.body = W.Text(c, 0, "textDim")
    c.body:SetWordWrap(true)
    c.body:SetJustifyV("TOP")
    c.body:SetSpacing(3)
    c.body:SetPoint("TOPLEFT", 18, -44)
    c.body:SetPoint("RIGHT", -18, 0)
    return c
end

-- Multi-line edit box in a scrolling, bordered field. onChange(text) on user edits.
function W.MultiEdit(parent, onChange, maxLetters)
    local box = CreateFrame("Frame", nil, parent)
    box.bg = W.Fill(box, "field", 1)
    box.bg:SetAllPoints()
    box.border = W.Border(box, "line")
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 10, -8)
    scroll:SetPoint("BOTTOMRIGHT", -10, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(maxLetters or 5000)
    Theme:SetFont(edit)
    edit:SetTextColor(Theme:Color("text"))
    edit:SetWidth(200)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(self, w) edit:SetWidth(max(50, w or self:GetWidth())) end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top, height = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -y
        if y < top then
            scroll:SetVerticalScroll(y)
        elseif y + h > top + height then
            scroll:SetVerticalScroll(y + h - height)
        end
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self, user)
        if user and onChange then onChange(self:GetText()) end
    end)
    local function setBorder(r, g, b)
        for _, side in pairs(box.border) do side:SetColorTexture(r, g, b, 1) end
    end
    edit:SetScript("OnEditFocusGained", function() setBorder(Theme:Accent()) end)
    edit:SetScript("OnEditFocusLost", function() setBorder(Theme:Color("line")) end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, edit:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * 30)))
    end)
    box.edit = edit
    return box
end

-- Square color swatch (hex "RRGGBB") with a selection ring.
function W.Swatch(parent, hex, onClick, tooltip)
    local r, g, b = Theme.Hex(hex)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(22, 22)
    s.ring = W.Border(s, "line")
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("TOPLEFT", 3, -3)
    s.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    s.fill:SetColorTexture(r, g, b, 1)
    function s:SetSelected(on)
        local cr, cg, cb = Theme:Color(on and "text" or "line")
        for _, side in pairs(self.ring) do side:SetColorTexture(cr, cg, cb, 1) end
    end
    s:SetScript("OnClick", function() if onClick then onClick() end end)
    if tooltip then
        s:SetScript("OnEnter", function(self) W.ShowTooltip(self, tooltip) end)
        s:SetScript("OnLeave", function() W.HideTooltip() end)
    end
    return s
end

-- ---------------------------------------------------------------------------
-- Context menu and confirm dialog. A full-screen invisible catcher closes them on any
-- click outside.
-- ---------------------------------------------------------------------------

local catcher, menu, dialog

local function closeAll()
    if menu then menu:Hide() end
    if dialog then dialog:Hide() end
    if catcher then catcher:Hide() end
end
W.CloseMenus = closeAll

local function getCatcher()
    if not catcher then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", closeAll)
    end
    catcher:Show()
    return catcher
end

local function panel()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(getCatcher():GetFrameLevel() + 10)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f.bg = W.Fill(f, "field", 0.98)
    f.bg:SetAllPoints()
    W.Border(f, "line")
    return f
end

local function menuButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.text = W.Text(b, 0, "text")
    b.text:SetPoint("LEFT", 10, 0)
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.bg:Show() end end)
    b:SetScript("OnLeave", function(self) self.bg:Hide() end)
    return b
end

function W.IsMenuOpen() return menu ~= nil and menu:IsShown() end

-- items = { { text, onClick, disabled, danger, title, checked, font } }. Title items are
-- faint headings, checked items use the accent, font previews the item in that font.
function W.OpenMenu(items, anchor)
    closeAll()
    getCatcher()
    if not menu then
        menu = panel()
        menu.buttons = {}
    end
    menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
    local width = 120
    for i, item in ipairs(items) do
        local b = menu.buttons[i] or menuButton(menu)
        menu.buttons[i] = b
        if item.font then
            b.text:SetFont(item.font, Theme:TextSize(), "")
        else
            Theme:SetFont(b.text)
        end
        b.text:SetText(item.text)
        if item.checked then
            b.text:SetTextColor(Theme:Accent())
        else
            local key = item.title and "textFaint" or item.disabled and "textFaint" or item.danger and "warn" or "text"
            b.text:SetTextColor(Theme:Color(key))
        end
        b:SetEnabled(not item.disabled and not item.title)
        b:SetScript("OnClick", function()
            closeAll()
            if item.onClick then SRT:Call("menu: " .. tostring(item.text), item.onClick) end
        end)
        b:Show()
        width = max(width, b.text:GetStringWidth() + 30)
    end
    for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
    -- Long lists (many fonts) wrap into columns of at most 18 rows.
    local perCol = min(#items, 18)
    local cols = ceil(#items / perCol)
    for i = 1, #items do
        local b = menu.buttons[i]
        local col, row = floor((i - 1) / perCol), (i - 1) % perCol
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 1 + col * width, -4 - row * 22)
        b:SetWidth(width - 2)
    end
    menu:SetSize(width * cols, perCol * 22 + 8)
    menu:ClearAllPoints()
    if anchor then
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
    end
    menu:Show()
end

-- Yes/No box in the middle of the screen.
function W.Confirm(text, yesLabel, onYes)
    closeAll()
    getCatcher()
    if not dialog then
        dialog = panel()
        dialog:SetSize(300, 110)
        dialog.text = W.Text(dialog, 0, "text")
        dialog.text:SetWordWrap(true)
        dialog.text:SetJustifyH("CENTER")
        dialog.text:SetPoint("TOPLEFT", 16, -18)
        dialog.text:SetPoint("TOPRIGHT", -16, -18)
        local function button(label, colorKey)
            local b = CreateFrame("Button", nil, dialog)
            b:SetSize(110, 26)
            b.bg = W.Fill(b, colorKey, 1)
            b.bg:SetAllPoints()
            W.Border(b, "line")
            b.text = W.Text(b, 0, "text")
            b.text:SetPoint("CENTER")
            b.text:SetText(label)
            b:SetScript("OnEnter", function(self) self.bg:SetAlpha(0.8) end)
            b:SetScript("OnLeave", function(self) self.bg:SetAlpha(1) end)
            return b
        end
        dialog.yes = button("", "selected")
        dialog.yes:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 14)
        dialog.yes.text:SetTextColor(Theme:Color("warn"))
        dialog.no = button("Cancel", "field")
        dialog.no:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 14)
        dialog.no:SetScript("OnClick", closeAll)
    end
    dialog:SetFrameLevel(catcher:GetFrameLevel() + 10)
    dialog.text:SetText(text)
    dialog.yes.text:SetText(yesLabel or "Yes")
    dialog.yes:SetScript("OnClick", function()
        closeAll()
        SRT:Call("confirm", onYes)
    end)
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    dialog:Show()
end

-- Reused frames.
function W.Pool(create, reset)
    local pool = { free = {}, active = {} }
    function pool:Acquire()
        local obj = tremove(self.free) or create()
        self.active[#self.active + 1] = obj
        obj:Show()
        return obj
    end
    function pool:ReleaseAll()
        for i = #self.active, 1, -1 do
            local obj = self.active[i]
            obj:Hide()
            obj:ClearAllPoints()
            if reset then reset(obj) end
            self.free[#self.free + 1] = obj
            self.active[i] = nil
        end
    end
    return pool
end
