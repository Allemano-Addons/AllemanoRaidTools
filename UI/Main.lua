-- Main window: sidebar with every tool (grouped by when it is used), a header with the
-- raid status and the leader's quick actions, and the selected page below it.
-- Pages register themselves with Main.RegisterPage; the rest show "coming soon".
local _, ART = ...

local Theme, W = ART.Theme, ART.Widgets

local Main = {}
ART.Main = Main

local WIDTH, HEIGHT = 1000, 660
local MIN_W, MIN_H, MAX_W, MAX_H = 820, 560, 1800, 1200
local SIDEBAR_W, HEADER_H, FOOTER_H, LOGO_H = 210, 72, 30, 52
local ITEM_H, HEADING_H = 26, 30

-- Sidebar: { heading, { { id, label, badge }, ... } }
Main.NAV = {
    { "Overview",    { { "home", "Home" } } },
    { "Plan",        { { "notes", "Notes" }, { "visualnote", "Visual note" }, { "reminders", "Reminders" } } },
    { "Before pull", { { "raidcheck", "Raid check" }, { "buffs", "Buff assignments" }, { "invites", "Invites & groups" }, { "summons", "Summons" } } },
    { "During",      { { "marks", "Marks" }, { "timers", "Timers" }, { "cooldowns", "Cooldowns", "PROBE" }, { "bres", "Battle res", "PROBE" } } },
    { "After",       { { "pulllog", "Pull log" }, { "attendance", "Attendance" }, { "loot", "Loot" } } },
    { "Settings",    { { "appearance", "Appearance" }, { "toolbar", "Toolbar" }, { "combatlog", "Combat log" }, { "advanced", "Advanced" } } },
}

-- What each page will do, shown until it is built.
local COMING = {
    reminders = "Personal reminders that pop up at the right moment (\"Soulstone on pull\", \"Bring fire resistance\").",
    buffs = "Assign buffs (Fortitude, Mark of the Wild, Intellect...) per class and group, and post the assignments.",
    summons = "See who is not in the raid's zone and post the summon list in raid chat (/art summon).",
    cooldowns = "Raid cooldowns per player. Depends on what WoW Forever lets addons see in combat: run /art probe combat in a dungeon.",
    bres = "Battle res tracking. Depends on the combat probe as well.",
    attendance = "Who was in the raid, benched or late, with an export.",
    loot = "Loot council support (later).",
}

local frame, content, header, navButtons
local pages = {}      -- [id] = { build = fn(parent) -> refresh fn, frame, refresh }
local current

function Main.RegisterPage(id, build)
    pages[id] = { build = build }
end

function Main.Frame() return frame end

-- ---------------------------------------------------------------------------
-- Status (header subtitle): group size, online, in zone, when the raid formed.
-- ---------------------------------------------------------------------------

local function trackGroupStart()
    if not ART.db then return end
    local w = ART.db.window
    if IsInGroup() then
        w.groupSince = w.groupSince or time()
    else
        w.groupSince = nil
    end
end

local function statusText()
    if not IsInGroup() then return "Raid tools", "Not in a group" end
    local online, total = 0, 0
    for _, m in ipairs(ART.Compat.GroupMembers()) do
        total = total + 1
        if m.online then online = online + 1 end
    end
    local inZone = ART.Compat.InZoneCount()
    local title = IsInRaid() and "Tonight" or "Group"
    local inInstance = IsInInstance()
    if inInstance then
        local name = GetInstanceInfo()
        if name then title = title .. " \194\183 " .. name end
    end
    local parts = {
        ("%d/%d online"):format(online, total),
        ("%d in zone"):format(inZone),
    }
    local since = ART.db.window.groupSince
    if since then parts[#parts + 1] = (IsInRaid() and "raid started " or "group formed ") .. date("%H:%M", since) end
    local breakLeft = ART.Timers.Remaining("break")
    if breakLeft then parts[#parts + 1] = "break " .. ART.Timers.Format(breakLeft) .. " left" end
    return title, table.concat(parts, " \194\183 ")
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function savePosition()
    local point, _, rel, x, y = frame:GetPoint(1)
    ART.db.window.point, ART.db.window.rel, ART.db.window.x, ART.db.window.y = point, rel, x, y
end

local function applyLook()
    local s = ART.db.settings
    frame.bg:SetAlpha(s.bgAlpha or 0.97)
    frame.sidebarBg:SetAlpha(s.bgAlpha or 0.97)
    frame:SetScale(s.scale or 1)
end

local function buildSidebar()
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDEBAR_W)
    frame.sidebarBg = W.Fill(side, "sidebar", 1)
    frame.sidebarBg:SetAllPoints()
    frame.sidebarBg:Hide() -- one surface with the rounded window (the line separates)
    W.Line(side, "right", "line")

    -- Logo: accent square, "ART", "RAID TOOLS".
    local logo = CreateFrame("Frame", nil, side)
    logo:SetPoint("TOPLEFT")
    logo:SetPoint("TOPRIGHT")
    logo:SetHeight(LOGO_H)
    W.Line(logo, "bottom", "line")
    -- The ART mark in its own colors (a plain accent square if the file does not load).
    local square = logo:CreateTexture(nil, "ARTWORK")
    local hasMark = square:SetTexture(ART.MARK) ~= false
    if hasMark then
        square:SetSize(24, 24)
        square:SetPoint("LEFT", 13, 0)
    else
        square:SetSize(8, 8)
        square:SetPoint("LEFT", 18, 0)
        W.OnAccent(function(r, g, b) square:SetColorTexture(r, g, b, 1) end)
    end
    local art = W.Text(logo, 4, "text")
    art:SetPoint("LEFT", square, "RIGHT", 8, 0)
    art:SetText("ART")
    local sub = W.Text(logo, -1, "textFaint")
    sub:SetPoint("LEFT", art, "RIGHT", 8, 0)
    sub:SetText("RAID TOOLS")

    -- Footer: version and guild.
    local footer = CreateFrame("Frame", nil, side)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(FOOTER_H)
    W.Line(footer, "top", "line")
    frame.footerText = W.Text(footer, -2, "textFaint")
    frame.footerText:SetPoint("LEFT", 18, 0)

    -- Scrolling navigation.
    local scroll = CreateFrame("ScrollFrame", nil, side)
    scroll:SetPoint("TOPLEFT", 0, -LOGO_H)
    scroll:SetPoint("BOTTOMRIGHT", -1, FOOTER_H)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetWidth(SIDEBAR_W - 1)
    scroll:SetScrollChild(list)
    navButtons = {}
    local y = 6
    for _, section in ipairs(Main.NAV) do
        local h = W.Text(list, -2, "textFaint")
        h:SetPoint("TOPLEFT", 18, -(y + 12))
        h:SetText(strupper(section[1]))
        W.OnAccent(function(r, g, b) h:SetTextColor(r, g, b) end)
        y = y + HEADING_H
        for _, item in ipairs(section[2]) do
            local b = CreateFrame("Button", nil, list)
            b.id = item[1]
            b:SetPoint("TOPLEFT", 0, -y)
            b:SetPoint("TOPRIGHT", 0, -y)
            b:SetHeight(ITEM_H)
            b.bg = W.Fill(b, "selected", 1)
            b.bg:SetAllPoints()
            b.bg:Hide()
            -- Selected page: a rounded, inset highlight (the Allemano look).
            W.Round(b.bg, Theme.radius.small)
            b.bg:ClearAllPoints()
            b.bg:SetPoint("TOPLEFT", 8, -1)
            b.bg:SetPoint("BOTTOMRIGHT", -8, 1)
            b.text = W.Text(b, 0, "textDim")
            b.text:SetPoint("LEFT", 18, 0)
            b.text:SetText(item[2])
            -- Badge: the item's own (PROBE), or SOON for tools that are not built yet.
            local badgeText = item[3] or (not pages[item[1]] and "SOON") or nil
            if badgeText then
                local badge = CreateFrame("Frame", nil, b)
                badge:SetHeight(14)
                badge:SetPoint("RIGHT", -16, 0)
                W.RoundBorder(W.Border(badge, "textFaint"), Theme.radius.small)
                local t = W.Text(badge, -4, "textDim")
                t:SetPoint("CENTER", 0, 0)
                t:SetText(badgeText)
                badge:SetWidth(t:GetStringWidth() + 10)
                b.badge = badgeText
            end
            b:SetScript("OnEnter", function(self) if current ~= self.id then self.text:SetTextColor(Theme:Color("text")) end end)
            b:SetScript("OnLeave", function(self) if current ~= self.id then self.text:SetTextColor(Theme:Color("textDim")) end end)
            b:SetScript("OnClick", function(self) Main.Show(self.id) end)
            navButtons[#navButtons + 1] = b
            y = y + ITEM_H
        end
    end
    list:SetHeight(y + 8)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, list:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * ITEM_H * 2)))
    end)
end

local function buildHeader()
    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", SIDEBAR_W, 0)
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    W.Line(header, "bottom", "line")
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    header.title = W.Text(header, 5, "text")
    header.title:SetPoint("TOPLEFT", 26, -18)
    header.sub = W.Text(header, -1, "textFaint")
    header.sub:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -6)

    local close = W.CloseButton(header, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Quick actions, right to left.
    header.note = W.Button(header, "Send note", "accent", function()
        local n = ART.Notes.Selected()
        if n then ART.Notes.Send(n.id) else Main.Show("notes") end
    end)
    header.note:SetPoint("RIGHT", -40, -2)
    header.breakBtn = W.Button(header, "Break 10 min", nil, function()
        if ART.Timers.Remaining("break") then ART.Timers.Break(0) else ART.Timers.Break(10) end
    end)
    header.breakBtn:SetPoint("RIGHT", header.note, "LEFT", -10, 0)
    header.pull = W.Button(header, "Pull 10s", nil, function() ART.Timers.Pull(10) end)
    header.pull:SetPoint("RIGHT", header.breakBtn, "LEFT", -10, 0)
    header.rc = W.Button(header, "Ready check", nil, function() ART.Timers.ReadyCheck() end)
    header.rc:SetPoint("RIGHT", header.pull, "LEFT", -10, 0)
end

local function refreshHeader()
    local title, sub = statusText()
    header.title:SetText(title)
    header.sub:SetText(sub)
    local lead -- disabled reason for the leader buttons, nil when allowed
    if not ART.Timers.CanLead() then lead = "Only the raid leader or an assistant can do this." end
    header.rc:SetDisabled(lead or (not IsInGroup() and "Join a group first.") or nil)
    header.pull:SetDisabled(lead)
    header.breakBtn:SetDisabled(lead)
    header.breakBtn:SetLabel(ART.Timers.Remaining("break") and "End break" or "Break 10 min")
    local selected = ART.Notes.Selected()
    header.note:SetDisabled(lead or (not selected and "No note yet: write one under Notes.") or nil)
    header.note.tooltip = selected and ("Sends \"%s\" (the note selected under Notes)"):format(selected.title) or nil
    frame.footerText:SetText(("v%s%s"):format(tostring(ART.version), ART.Compat.GuildName() and (" \194\183 " .. ART.Compat.GuildName()) or ""))
end

local function comingSoon(id, label)
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    local card = W.Card(p, label, nil, nil, true)
    card:SetPoint("TOPLEFT", 26, -24)
    card:SetPoint("TOPRIGHT", -26, -24)
    card:SetHeight(110)
    card.body:SetText((COMING[id] or "") .. "\n\n|cff7c858fComing in a later version.|r")
    return p
end

local function labelFor(id)
    for _, section in ipairs(Main.NAV) do
        for _, item in ipairs(section[2]) do if item[1] == id then return item[2] end end
    end
end

local placeholders = {}
function Main.Show(id)
    if not frame then return end
    if not labelFor(id) then id = "home" end
    for _, p in pairs(pages) do if p.frame then p.frame:Hide() end end
    for _, p in pairs(placeholders) do p:Hide() end
    local page = pages[id]
    if page then
        if not page.frame then
            page.frame = CreateFrame("Frame", nil, content)
            page.frame:SetAllPoints()
            page.refresh = page.build(page.frame)
        end
        page.frame:Show()
        if page.refresh then ART:Call("page " .. id, page.refresh) end
    else
        placeholders[id] = placeholders[id] or comingSoon(id, labelFor(id))
        placeholders[id]:Show()
    end
    current = id
    ART.db.window.page = id
    for _, b in ipairs(navButtons) do
        local on = b.id == id
        b.bg:SetShown(on)
        b.text:SetTextColor(Theme:Color(on and "text" or "textDim"))
    end
    frame:Show()
end

-- Header and the visible page again (group changes, timers, settings).
function Main.Refresh()
    if not frame or not frame:IsShown() then return end
    refreshHeader()
    local page = current and pages[current]
    if page and page.refresh then ART:Call("page " .. current, page.refresh) end
end

-- Resize grip in the bottom right corner: three steps of small squares.
local function buildGrip()
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip.dots = {}
    for _, d in ipairs({ { 10, 2 }, { 6, 6 }, { 10, 6 }, { 2, 10 }, { 6, 10 }, { 10, 10 } }) do
        local t = grip:CreateTexture(nil, "OVERLAY")
        t:SetSize(2, 2)
        t:SetPoint("TOPLEFT", d[1], -d[2])
        grip.dots[#grip.dots + 1] = t
    end
    local function color(key)
        local r, g, b = Theme:Color(key)
        for _, t in ipairs(grip.dots) do t:SetColorTexture(r, g, b, 1) end
    end
    color("textFaint")
    grip:SetScript("OnEnter", function(self)
        color("text")
        W.ShowTooltip(self, "Drag to resize")
    end)
    grip:SetScript("OnLeave", function()
        color("textFaint")
        W.HideTooltip()
    end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        ART.db.window.w, ART.db.window.h = floor(frame:GetWidth() + 0.5), floor(frame:GetHeight() + 0.5)
        savePosition() -- sizing re-anchors the frame
    end)
end

local statusTicker
local function build()
    frame = CreateFrame("Frame", "AllemanoRaidToolsFrame", UIParent)
    tinsert(UISpecialFrames, "AllemanoRaidToolsFrame") -- ESC closes it
    local saved = ART.db.window
    frame:SetSize(min(MAX_W, max(MIN_W, saved.w or WIDTH)), min(MAX_H, max(MIN_H, saved.h or HEIGHT)))
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_W, MIN_H)
        frame:SetMaxResize(MAX_W, MAX_H)
    end
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame.bg = W.Fill(frame, "window", 1)
    frame.bg:SetAllPoints()
    W.Panel(frame, frame.bg, W.Border(frame, "line"))
    local w = ART.db.window
    if w.point then
        frame:SetPoint(w.point, UIParent, w.rel or w.point, w.x or 0, w.y or 0)
    else
        frame:SetPoint("CENTER", 0, 40)
    end
    buildSidebar()
    buildHeader()
    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", SIDEBAR_W, -HEADER_H)
    content:SetPoint("BOTTOMRIGHT")
    buildGrip()
    applyLook()
    frame:SetScript("OnShow", function()
        refreshHeader()
        -- The subtitle has live parts (in zone, break left): refresh while open only.
        statusTicker = statusTicker or C_Timer.NewTicker(1, function() ART:Call("status", refreshHeader) end)
    end)
    frame:SetScript("OnHide", function()
        if statusTicker then statusTicker:Cancel() statusTicker = nil end
        W.HideTooltip()
        W.CloseMenus()
    end)
    frame:Hide()
end

function Main.Toggle(id)
    if not ART.db then return end
    if not frame then
        -- A failed build must not leave a half-made (invisible) window behind.
        local ok, err = pcall(build)
        if not ok then
            if frame then frame:Hide() end
            frame = nil
            ART:RecordError("window build", err)
            return
        end
    end
    if frame:IsShown() and not id then frame:Hide() return end
    Main.Show(id or ART.db.window.page or "home")
end

function Main.ResetPosition()
    local w = ART.db.window
    w.point, w.rel, w.x, w.y, w.w, w.h = nil, nil, nil, nil, nil, nil
    if frame then
        frame:SetSize(WIDTH, HEIGHT)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", 0, 40)
    end
end

ART:OnSettingChanged(function(key)
    if frame and (key == "bgAlpha" or key == "scale") then applyLook() end
end)

local function onGroup()
    trackGroupStart()
    Main.Refresh()
end
ART:RegisterEvent("GROUP_ROSTER_UPDATE", onGroup)
ART:RegisterEvent("PARTY_LEADER_CHANGED", onGroup)
ART:RegisterEvent("PLAYER_ENTERING_WORLD", onGroup)
ART:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Main.Refresh() end)
ART.Notes.OnChange(function() if frame and frame:IsShown() then refreshHeader() end end)
