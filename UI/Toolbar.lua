-- Toolbar: a small bar outside the main window with the tools picked in the settings:
-- open SRT, raid target icons, world markers, ready check, pull, break and the note.
-- World markers are protected, so they are secure macro buttons ("/wm N"). A bar with
-- secure buttons may not be moved, shown, hidden or rebuilt in combat: those changes wait
-- for combat to end.
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets

local Toolbar = {}
SRT.Toolbar = Toolbar

local SIZE, GAP, GROUP_GAP, HANDLE = 24, 2, 8, 8
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- World marker N uses this raid icon: 1 blue square, 2 green triangle, 3 purple diamond,
-- 4 red cross, 5 yellow star, 6 orange circle, 7 silver moon, 8 white skull.
local WORLD_ICON = { 6, 4, 3, 7, 1, 2, 5, 8 }
local WORLD_NAME = { "Blue square", "Green triangle", "Purple diamond", "Red cross", "Yellow star", "Orange circle", "Silver moon", "White skull" }
local ICON_NAME = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

-- Order on the bar and the label in menus/settings.
Toolbar.ITEMS = {
    { "open", "Open SRT" },
    { "marks", "Raid target icons" },
    { "world", "World markers" },
    { "readycheck", "Ready check" },
    { "pull", "Pull timer" },
    { "breaktimer", "Break timer" },
    { "note", "Note window" },
}

local bar, handle
local parts = {}   -- [item] = { buttons }
local pending      -- a layout change waiting for combat to end

local function db() return SRT.db.toolbar end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

local function paintBorder(b, key)
    local r, g, bl
    if key == "accent" then r, g, bl = Theme:Accent() else r, g, bl = Theme:Color(key) end
    for _, side in pairs(b.border) do side:SetColorTexture(r, g, bl, 1) end
end

local function decorate(b, tooltip)
    b:SetSize(SIZE, SIZE)
    b.bg = W.Fill(b, "field", 1)
    b.bg:SetAllPoints()
    b.border = W.Border(b, "line")
    b.tooltip = tooltip
    b:HookScript("OnEnter", function(self)
        self.bg:SetColorTexture(Theme:Color("selected"))
        W.ShowTooltip(self, self.tooltip)
    end)
    b:HookScript("OnLeave", function(self)
        self.bg:SetColorTexture(Theme:Color("field"))
        W.HideTooltip()
    end)
end

local function iconButton(texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, bar)
    decorate(b, tooltip)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    b.icon:SetTexture(texture)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button) SRT:Call("toolbar", onClick, self, button) end)
    return b
end

local function textButton(label, tooltip, onClick)
    local b = CreateFrame("Button", nil, bar)
    decorate(b, tooltip)
    b.text = W.Text(b, -2, "text")
    b.text:SetPoint("CENTER")
    function b:SetLabel(text)
        self.text:SetText(text)
        self:SetWidth(max(SIZE, self.text:GetStringWidth() + 14))
    end
    b:SetLabel(label)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button) SRT:Call("toolbar", onClick, self, button) end)
    return b
end

-- Secure macro button (protected actions such as world markers).
local function secureButton(texture, tooltip, macro)
    local b = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
    decorate(b, tooltip)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    if texture then b.icon:SetTexture(texture) end
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", macro)
    b:RegisterForClicks("AnyUp", "AnyDown")
    return b
end

local function setTarget(i)
    if not UnitExists("target") then SRT:Print("Target something first.") return end
    local current = GetRaidTargetIndex("target")
    SetRaidTarget("target", current == i and 0 or i)
end

local function build()
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar.bg = W.Fill(bar, "window", 0.85)
    bar.bg:SetAllPoints()
    W.Border(bar, "line")
    local t = db()
    bar:SetPoint(t.point or "TOP", UIParent, t.rel or t.point or "TOP", t.x or 0, t.y or -40)

    -- Handle: drag to move, right-click for the menu.
    handle = CreateFrame("Button", nil, bar)
    handle:RegisterForDrag("LeftButton")
    handle:RegisterForClicks("RightButtonUp")
    handle.fill = handle:CreateTexture(nil, "ARTWORK")
    handle.fill:SetPoint("TOPLEFT", 2, -2)
    handle.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    W.OnAccent(function(r, g, b) handle.fill:SetColorTexture(r, g, b, 0.8) end)
    handle:SetScript("OnDragStart", function()
        if db().locked or InCombatLockdown() then return end
        bar:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        local point, _, rel, x, y = bar:GetPoint(1)
        t.point, t.rel, t.x, t.y = point, rel, x, y
    end)
    handle:SetScript("OnClick", function() Toolbar.Menu() end)
    handle:SetScript("OnEnter", function(self)
        W.ShowTooltip(self, { "SRT toolbar", db().locked and "Right-click: options" or "Drag to move, right-click: options" })
    end)
    handle:SetScript("OnLeave", function() W.HideTooltip() end)

    parts.open = { textButton("SRT", "Open or close SlaughterRaidTools", function() SRT.Main.Toggle() end) }

    parts.marks = {}
    for i = 1, 8 do
        parts.marks[i] = iconButton(ICON .. i, { ICON_NAME[i] .. " on your target", "Click again to remove it." },
            function() setTarget(i) end)
    end
    parts.marks[9] = textButton("x", "Remove the icon from your target", function()
        if UnitExists("target") then SetRaidTarget("target", 0) end
    end)

    parts.world = {}
    for i = 1, 8 do
        parts.world[i] = secureButton(ICON .. WORLD_ICON[i], { "World marker: " .. WORLD_NAME[i], "Click, then click the ground." }, "/wm " .. i)
        -- A small bar under the icon tells world markers apart from target icons.
        local strip = parts.world[i]:CreateTexture(nil, "OVERLAY")
        strip:SetPoint("BOTTOMLEFT", 4, 2)
        strip:SetPoint("BOTTOMRIGHT", -4, 2)
        strip:SetHeight(2)
        W.OnAccent(function(r, g, b) strip:SetColorTexture(r, g, b, 1) end)
    end
    local clearWorld = secureButton(nil, "Remove all world markers", "/cwm 0")
    clearWorld.label = W.Text(clearWorld, -2, "text")
    clearWorld.label:SetPoint("CENTER")
    clearWorld.label:SetText("x")
    parts.world[9] = clearWorld

    parts.readycheck = { textButton("RC", "Ready check", function() SRT.Timers.ReadyCheck() end) }
    parts.pull = { textButton("Pull", { "Left-click: pull in 10", "Shift-click: pull in 15", "Right-click: cancel the pull" },
        function(_, button)
            if button == "RightButton" then SRT.Timers.Pull(0) else SRT.Timers.Pull(IsShiftKeyDown() and 15 or 10) end
        end) }
    parts.breaktimer = { textButton("Break", { "Left-click: break 10 min", "Shift-click: break 5 min", "Right-click: end the break" },
        function(_, button)
            if button == "RightButton" or SRT.Timers.Remaining("break") then
                SRT.Timers.Break(0)
            else
                SRT.Timers.Break(IsShiftKeyDown() and 5 or 10)
            end
        end) }
    parts.note = { textButton("Note", "Show or hide the note window", function() SRT.NoteWindow.Toggle() end) }
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local function wanted()
    local t = db()
    if not t.shown then return false end
    if t.onlyInGroup and not IsInGroup() then return false end
    return true
end

-- Places the chosen items; hides the rest. Waits for the end of combat if needed.
function Toolbar.Layout()
    if not SRT.db then return end
    if InCombatLockdown() then pending = true return end
    pending = nil
    if not wanted() then
        if bar then bar:Hide() end
        return
    end
    if not bar then build() end
    local t = db()
    local vertical = t.vertical
    local x = HANDLE + 2
    local thickness = SIZE + 4
    handle:ClearAllPoints()
    if vertical then
        handle:SetPoint("TOPLEFT")
        handle:SetPoint("TOPRIGHT")
        handle:SetHeight(HANDLE)
    else
        handle:SetPoint("TOPLEFT")
        handle:SetPoint("BOTTOMLEFT")
        handle:SetWidth(HANDLE)
    end
    local first = true
    for _, item in ipairs(Toolbar.ITEMS) do
        local list = parts[item[1]]
        local on = t.items[item[1]]
        if on and not first then x = x + GROUP_GAP - GAP end
        for _, b in ipairs(list) do
            b:ClearAllPoints()
            b:SetShown(on and true or false)
            if on then
                if vertical then
                    b:SetPoint("TOP", bar, "TOP", 0, -x)
                    x = x + SIZE + GAP
                else
                    b:SetPoint("LEFT", bar, "LEFT", x, 0)
                    x = x + b:GetWidth() + GAP
                end
            end
        end
        if on then first = false end
    end
    -- Vertical text buttons are as wide as the widest one.
    if vertical then
        for _, item in ipairs(Toolbar.ITEMS) do
            for _, b in ipairs(parts[item[1]]) do thickness = max(thickness, b:GetWidth() + 4) end
        end
        bar:SetSize(thickness, x + 1)
    else
        bar:SetSize(x + 1, thickness)
    end
    bar:SetScale(t.scale or 1)
    bar:Show()
    Toolbar.Refresh()
end

-- Live state: the icon on your target, break running, leader-only buttons dimmed.
function Toolbar.Refresh()
    if not bar or not bar:IsShown() then return end
    local current = UnitExists("target") and GetRaidTargetIndex("target")
    for i = 1, 8 do paintBorder(parts.marks[i], current == i and "accent" or "line") end
    local lead = SRT.Timers.CanLead()
    for _, key in ipairs({ "readycheck", "pull", "breaktimer" }) do parts[key][1]:SetAlpha(lead and 1 or 0.4) end
    local breakBtn = parts.breaktimer[1]
    local running = SRT.Timers.Remaining("break")
    breakBtn.text:SetTextColor(Theme:Color(running and "warn" or "text"))
    parts.note[1].text:SetTextColor(Theme:Color(SRT.NoteWindow.IsShown() and "text" or "textDim"))
end

function Toolbar.IsShown() return bar ~= nil and bar:IsShown() end

-- Changes a toolbar option and lays out again.
function Toolbar.Set(key, value)
    db()[key] = value
    Toolbar.Layout()
    if pending then SRT:Print("The toolbar changes after combat.") end
end

function Toolbar.SetItem(item, on)
    db().items[item] = on and true or false
    Toolbar.Layout()
    if pending then SRT:Print("The toolbar changes after combat.") end
end

function Toolbar.Menu()
    local t = db()
    local items = { { text = "Show on the toolbar", title = true } }
    for _, item in ipairs(Toolbar.ITEMS) do
        items[#items + 1] = { text = item[2], checked = t.items[item[1]], onClick = function() Toolbar.SetItem(item[1], not t.items[item[1]]) end }
    end
    items[#items + 1] = { text = "Options", title = true }
    items[#items + 1] = { text = "Vertical", checked = t.vertical, onClick = function() Toolbar.Set("vertical", not t.vertical) end }
    items[#items + 1] = { text = "Lock position", checked = t.locked, onClick = function() Toolbar.Set("locked", not t.locked) end }
    items[#items + 1] = { text = "Only in a group", checked = t.onlyInGroup, onClick = function() Toolbar.Set("onlyInGroup", not t.onlyInGroup) end }
    items[#items + 1] = { text = "More settings...", onClick = function() SRT.Main.Toggle("toolbar") end }
    items[#items + 1] = { text = "Hide toolbar (/srt bar)", danger = true, onClick = function() Toolbar.Set("shown", false) end }
    W.OpenMenu(items)
end

SRT:OnReady(Toolbar.Layout)
SRT:RegisterEvent("PLAYER_REGEN_ENABLED", function() if pending then Toolbar.Layout() end end)
SRT:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if db().onlyInGroup and Toolbar.IsShown() ~= wanted() then Toolbar.Layout() end
    Toolbar.Refresh()
end)
SRT:RegisterEvent("PARTY_LEADER_CHANGED", Toolbar.Refresh)
SRT:RegisterEvent("RAID_TARGET_UPDATE", Toolbar.Refresh)
SRT:RegisterEvent("PLAYER_TARGET_CHANGED", Toolbar.Refresh)
SRT.Notes.OnChange(Toolbar.Refresh)
SRT:OnSettingChanged(function(key) if key == "accent" or key == "useClassColor" then Toolbar.Refresh() end end)

SRT:AddSlashCommand("bar", function()
    Toolbar.Set("shown", not db().shown)
end, "show or hide the toolbar")
