-- Toolbar: a small bar outside the main window with the tools picked in the settings:
-- open SRT, raid target icons, world markers, ready check, pull, break and the note.
-- Target icons and world markers are protected on WoW Forever, so they are secure macro
-- buttons ("/tm N", "/wm N"). A bar with
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

    -- Open SRT: the SRT mark in the accent color ("SRT" as text if the file does not load).
    local open = textButton("", "Open or close SlaughterRaidTools", function() SRT.Main.Toggle() end)
    open.mark = open:CreateTexture(nil, "ARTWORK")
    if open.mark:SetTexture(SRT.MARK) ~= false then
        open.mark:SetSize(18, 18)
        open.mark:SetPoint("CENTER")
        W.OnAccent(function(r, g, b) open.mark:SetVertexColor(r, g, b, 1) end)
    else
        open:SetLabel("SRT")
    end
    parts.open = { open }

    -- Target icons are protected on WoW Forever (SetRaidTarget is forbidden for addons):
    -- secure "/tm N" macro buttons, like the world markers.
    parts.marks = {}
    for i = 1, 8 do
        parts.marks[i] = secureButton(ICON .. i, ICON_NAME[i] .. " on your target", "/tm " .. i)
    end
    local clearMark = secureButton(nil, "Remove the icon from your target", "/tm 0")
    clearMark.label = W.Text(clearMark, -2, "text")
    clearMark.label:SetPoint("CENTER")
    clearMark.label:SetText("x")
    parts.marks[9] = clearMark

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
    -- "/cwm 0" does nothing on Forever: clear the eight markers one by one.
    local clearAll = {}
    for i = 1, 8 do clearAll[i] = "/cwm " .. i end
    Toolbar.CLEAR_WORLD = table.concat(clearAll, "\n")
    local clearWorld = secureButton(nil, "Remove all world markers", Toolbar.CLEAR_WORLD)
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

-- Splits groups ({ len }) into at most `count` lines, keeping their order, so the longest
-- line is as short as possible. Returns { { group, ... }, ... }.
function Toolbar.SplitLines(groups, count)
    local n = #groups
    count = max(1, min(count, n))
    if n == 0 then return { {} } end
    local function lineLen(a, b)
        local len = 0
        for i = a, b do len = len + groups[i].len + (i > a and GROUP_GAP or 0) end
        return len
    end
    local best, bestCuts
    -- cuts = the last group index of every line but the last.
    local function try(cuts, start, left)
        if left == 1 then
            local worst, a = 0, 1
            for _, c in ipairs(cuts) do
                worst = max(worst, lineLen(a, c))
                a = c + 1
            end
            worst = max(worst, lineLen(a, n))
            if not best or worst < best then best, bestCuts = worst, { unpack(cuts) } end
            return
        end
        for c = start, n - left + 1 do
            cuts[#cuts + 1] = c
            try(cuts, c + 1, left - 1)
            cuts[#cuts] = nil
        end
    end
    try({}, 1, count)
    local lines, a = {}, 1
    for _, c in ipairs(bestCuts) do
        local line = {}
        for i = a, c do line[#line + 1] = groups[i] end
        lines[#lines + 1] = line
        a = c + 1
    end
    local last = {}
    for i = a, n do last[#last + 1] = groups[i] end
    lines[#lines + 1] = last
    return lines
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

    -- The chosen groups and their length along the bar.
    local groups = {}
    for _, item in ipairs(Toolbar.ITEMS) do
        local on = t.items[item[1]] and true or false
        local len = 0
        for i, b in ipairs(parts[item[1]]) do
            b:ClearAllPoints()
            b:SetShown(on)
            len = len + (vertical and SIZE or b:GetWidth()) + (i > 1 and GAP or 0)
        end
        if on then groups[#groups + 1] = { buttons = parts[item[1]], len = len } end
    end

    -- Rows (columns when vertical): groups stay whole, in order, split so the longest
    -- line is as short as possible.
    local lines = Toolbar.SplitLines(groups, t.rows or 1)
    local across = 2          -- position across the lines
    local longest = 0
    for _, line in ipairs(lines) do
        local along = HANDLE + 2
        local thick = SIZE
        if vertical then
            for _, grp in ipairs(line) do
                for _, b in ipairs(grp.buttons) do thick = max(thick, b:GetWidth()) end
            end
        end
        for gi, grp in ipairs(line) do
            if gi > 1 then along = along + GROUP_GAP end
            for bi, b in ipairs(grp.buttons) do
                if bi > 1 then along = along + GAP end
                if vertical then
                    b:SetPoint("TOP", bar, "TOPLEFT", across + thick / 2, -along)
                    along = along + SIZE
                else
                    b:SetPoint("TOPLEFT", bar, "TOPLEFT", along, -across)
                    along = along + b:GetWidth()
                end
            end
        end
        longest = max(longest, along)
        across = across + thick + GAP
    end
    across = across - GAP + 2
    if vertical then bar:SetSize(across, longest + 3) else bar:SetSize(longest + 3, across) end
    bar:SetScale(t.scale or 1)
    bar:Show()
    Toolbar.Refresh()
end

-- Live state: the icon on your target, break running, leader-only buttons dimmed.
function Toolbar.Refresh()
    if not bar or not bar:IsShown() then return end
    local current = UnitExists("target") and GetRaidTargetIndex("target")
    if issecretvalue and issecretvalue(current) then current = nil end -- hidden in combat
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
    SRT.Main.Refresh() -- the settings page shows these too
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
    local unit = t.vertical and "column" or "row"
    for n = 1, 3 do
        items[#items + 1] = { text = ("%d %s%s"):format(n, unit, n > 1 and "s" or ""), checked = (t.rows or 1) == n,
            onClick = function() Toolbar.Set("rows", n) end }
    end
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
