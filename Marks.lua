-- Mouseover marking: every press of the mark key (default: Ctrl + mouse wheel) puts the
-- next raid icon of the list on the unit under the mouse. Setting icons is protected on
-- WoW Forever, so this is a secure macro button ("/tm [@mouseover] N"); a secure snippet
-- picks the next icon on each press, which also works in combat. A key press per unit is
-- needed: the game never lets addons mark by themselves (no "just hover").
local _, ART = ...

local Marks = {}
ART.Marks = Marks

-- Default order: skull, cross, square, moon, triangle, diamond, circle, star.
Marks.DEFAULT_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
Marks.ICON_NAME = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
Marks.WHEEL_KEYS = { "CTRL-MOUSEWHEELUP", "CTRL-MOUSEWHEELDOWN" }

local button, header, pending

-- Names in Key Bindings > AddOns (Bindings.xml).
BINDING_HEADER_ALLEMANORAIDTOOLS = "Allemano Raid Tools"
_G["BINDING_NAME_CLICK AllemanoRaidToolsMarkButton:LeftButton"] = "Mark mouseover (next icon)" -- luacheck: ignore 122

local function db() return ART.db.marks end

-- The icons in use, in order.
function Marks.Order()
    local out = {}
    for _, i in ipairs(db().order) do
        if not db().off[i] then out[#out + 1] = i end
    end
    return out
end

-- Runs in the game's restricted (secure) environment on every press, before the macro.
-- art-fixed: 0 = next icon of the general order, N = icon N (a mob list picked it while
-- out of combat), -1 = nothing (the unit already has an icon and marks are locked).
local PRE_CLICK = [[
    local fixed = self:GetAttribute("art-fixed") or 0
    if fixed < 0 then return false end
    if fixed > 0 then
        self:SetAttribute("macrotext", "/tm [@mouseover,exists] " .. fixed)
        return
    end
    local n = self:GetAttribute("art-count") or 0
    if n == 0 then return false end
    local i = (self:GetAttribute("art-index") or 0) % n + 1
    self:SetAttribute("art-index", i)
    self:SetAttribute("macrotext", "/tm [@mouseover,exists] " .. self:GetAttribute("art-icon" .. i))
]]
Marks.PRE_CLICK = PRE_CLICK

-- ---------------------------------------------------------------------------
-- Mob lists: db.marks.mobs[zone][mob name] = { icon, ... }. While out of combat, pointing
-- at a mob that has a list picks its next free icon (an icon is used once per pack); with
-- "lock", a mob that already has an icon keeps it. Everything starts over after a fight.
-- ---------------------------------------------------------------------------

local usedIcons = {} -- icons given out since the last start over

local function safe(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The zone lists are kept under: the instance's name inside one, else the zone.
function Marks.ZoneKey()
    local inInstance = IsInInstance()
    local name = inInstance and GetInstanceInfo() or GetRealZoneText()
    return name ~= "" and name or "Unknown"
end

-- The list for a mob name: this zone's first, else any zone's.
function Marks.ListFor(name)
    if not name then return nil end
    local mobs = db().mobs
    local here = mobs[Marks.ZoneKey()]
    if here and here[name] then return here[name] end
    for _, zone in pairs(mobs) do
        if zone[name] then return zone[name] end
    end
end

-- The next icon of a list nobody has got yet, nil when all are used.
function Marks.NextFree(list)
    for _, icon in ipairs(list) do
        if not usedIcons[icon] then return icon end
    end
end

local function setFixed(value)
    if button and not InCombatLockdown() then button:SetAttribute("art-fixed", value) end
end

-- Out of combat: prepares the next press for the unit under the mouse.
-- /art markdebug: say in chat what the mark button does (to find out why nothing is marked).
local function debug(fmt, ...)
    if Marks.debug then ART:Print("|cff888888[mark] " .. fmt:format(...) .. "|r") end
end

function Marks.Prepare()
    if not button or InCombatLockdown() or not db().wheel then return end
    if not UnitExists("mouseover") then setFixed(0) return end
    local current = safe(GetRaidTargetIndex("mouseover"))
    local name = safe(UnitName("mouseover"))
    if current and db().lock then
        setFixed(-1)
        debug("%s already has icon %s: locked", tostring(name), tostring(current))
        return
    end
    local list = not UnitIsPlayer("mouseover") and Marks.ListFor(name)
    if list then
        setFixed(Marks.NextFree(list) or -1)
        local nextIcon = button:GetAttribute("art-fixed")
        debug(nextIcon > 0 and "%s: list, next icon %s" or "%s: list, all its icons are used (Start over)", tostring(name), tostring(nextIcon))
    else
        setFixed(0)
        debug("%s: no list, general order", tostring(name))
    end
end

-- After a press: stop a second press on the same unit until the game has set the icon
-- (RAID_TARGET_UPDATE prepares again). An icon only counts as used once the game shows
-- it on the unit (a press that marked nothing must not use up the list).
local function afterPress()
    local fixed = button:GetAttribute("art-fixed") or 0
    local who = tostring(UnitExists("mouseover") and safe(UnitName("mouseover")) or "nothing")
    if fixed < 0 then
        debug("pressed: nothing to do (already marked, or its list is used up: Start over) (mouseover: %s)", who)
    else
        debug("pressed: macro \"%s\" (mouseover: %s)", tostring(button:GetAttribute("macrotext")), who)
    end
    if InCombatLockdown() then return end
    if db().lock and fixed >= 0 then setFixed(-1) else Marks.Prepare() end
end

-- The game set (or removed) an icon: the one on the unit under the mouse is now in use.
local function iconChanged()
    local icon = UnitExists("mouseover") and safe(GetRaidTargetIndex("mouseover"))
    if icon then
        usedIcons[icon] = true
        debug("%s now has icon %d", tostring(safe(UnitName("mouseover"))), icon)
    end
    Marks.Prepare()
end

ART:AddSlashCommand("markdebug", function()
    Marks.debug = not Marks.debug
    ART:Print("Mark debug " .. (Marks.debug and "on: every Ctrl + wheel press is shown in chat." or "off."))
end, "show what mouseover marking does (for testing)")

function Marks.AddMob(name, zone)
    name = strtrim(name or "")
    if name == "" then return false end
    zone = zone or Marks.ZoneKey()
    local mobs = db().mobs
    mobs[zone] = mobs[zone] or {}
    mobs[zone][name] = mobs[zone][name] or { 8 }
    if ART.Main then ART.Main.Refresh() end
    return true
end

-- Adds the target (a mob) to this zone's lists.
function Marks.AddTarget()
    if not UnitExists("target") or UnitIsPlayer("target") then
        ART:Print("Target the mob first.")
        return false
    end
    return Marks.AddMob(safe(UnitName("target")))
end

function Marks.RemoveMob(zone, name)
    local mobs = db().mobs
    if mobs[zone] then
        mobs[zone][name] = nil
        if not next(mobs[zone]) then mobs[zone] = nil end
    end
    if ART.Main then ART.Main.Refresh() end
end

-- Sets slot `slot` of a mob's list to an icon (nil removes it; the list closes up).
function Marks.SetSlot(zone, name, slot, icon)
    local list = db().mobs[zone] and db().mobs[zone][name]
    if not list then return end
    if icon then
        list[min(slot, #list + 1)] = icon
    else
        tremove(list, slot)
    end
    if ART.Main then ART.Main.Refresh() end
end

-- Builds the button (named: key bindings click it by name).
local function build()
    button = CreateFrame("Button", "AllemanoRaidToolsMarkButton", UIParent, "SecureActionButtonTemplate")
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "")
    -- Only "down": a mouse wheel notch has no "up", and with both the lock set after the
    -- down press stopped the macro that the game runs on the up press.
    button:RegisterForClicks("AnyDown")
    button:SetAttribute("useOnKeyDown", true)
    button:SetAttribute("art-fixed", 0)
    header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    header:WrapScript(button, "OnClick", PRE_CLICK)
    button:SetScript("PostClick", function() ART:Call("mark", afterPress) end)
end

-- Writes the icon list into the button and sets the Ctrl + wheel keys. Protected in
-- combat: waits for it to end.
function Marks.Apply()
    if not ART.db then return end
    if InCombatLockdown() then pending = true return end
    pending = nil
    if not button then build() end
    local order = Marks.Order()
    button:SetAttribute("art-count", #order)
    for i = 1, 8 do button:SetAttribute("art-icon" .. i, order[i]) end
    button:SetAttribute("art-index", 0)
    ClearOverrideBindings(button)
    if db().wheel and #order > 0 then
        for _, key in ipairs(Marks.WHEEL_KEYS) do SetOverrideBindingClick(button, true, key, button:GetName(), "LeftButton") end
    end
    if ART.Main then ART.Main.Refresh() end
end

-- The next press starts with the first icon again (and every mob list from its start).
function Marks.StartOver()
    if InCombatLockdown() then ART:Print("Not in combat.") return end
    wipe(usedIcons)
    if button then button:SetAttribute("art-index", 0) end
    Marks.Prepare()
end

function Marks.Toggle(icon)
    db().off[icon] = not db().off[icon] or nil
    Marks.Apply()
end

function Marks.MoveUp(pos)
    local order = db().order
    if pos > 1 then
        order[pos], order[pos - 1] = order[pos - 1], order[pos]
        Marks.Apply()
    end
end

function Marks.Reset()
    db().order = CopyTable(Marks.DEFAULT_ORDER)
    db().off = {}
    Marks.Apply()
end

ART:OnReady(Marks.Apply)
-- After a fight the next pack starts from the top of every list.
ART:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pending then Marks.Apply() end
    Marks.StartOver()
end)
-- Just before combat locks the button: use the general order in the fight.
ART:RegisterEvent("PLAYER_REGEN_DISABLED", function() if button then button:SetAttribute("art-fixed", 0) end end)
ART:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Marks.Prepare() end)
ART:RegisterEvent("RAID_TARGET_UPDATE", function() ART:Call("mark", iconChanged) end)
ART:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() if not InCombatLockdown() then wipe(usedIcons) end end)
