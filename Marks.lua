-- Mouseover marking: every press of the mark key (default: Ctrl + mouse wheel) puts the
-- next raid icon of the list on the unit under the mouse. Setting icons is protected on
-- WoW Forever, so this is a secure macro button ("/tm [@mouseover] N"); a secure snippet
-- picks the next icon on each press, which also works in combat. A key press per unit is
-- needed: the game never lets addons mark by themselves (no "just hover").
local _, SRT = ...

local Marks = {}
SRT.Marks = Marks

-- Default order: skull, cross, square, moon, triangle, diamond, circle, star.
Marks.DEFAULT_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
Marks.ICON_NAME = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
Marks.WHEEL_KEYS = { "CTRL-MOUSEWHEELUP", "CTRL-MOUSEWHEELDOWN" }

local button, header, pending

-- Names in Key Bindings > AddOns (Bindings.xml).
BINDING_HEADER_SLAUGHTERRAIDTOOLS = "SlaughterRaidTools"
_G["BINDING_NAME_CLICK SlaughterRaidToolsMarkButton:LeftButton"] = "Mark mouseover (next icon)" -- luacheck: ignore 122

local function db() return SRT.db.marks end

-- The icons in use, in order.
function Marks.Order()
    local out = {}
    for _, i in ipairs(db().order) do
        if not db().off[i] then out[#out + 1] = i end
    end
    return out
end

-- Runs in the game's restricted (secure) environment on every press, before the macro.
local PRE_CLICK = [[
    local n = self:GetAttribute("srt-count") or 0
    if n == 0 then return false end
    local i = (self:GetAttribute("srt-index") or 0) % n + 1
    self:SetAttribute("srt-index", i)
    self:SetAttribute("macrotext", "/tm [@mouseover,exists] " .. self:GetAttribute("srt-icon" .. i))
]]

-- Builds the button (named: key bindings click it by name).
local function build()
    button = CreateFrame("Button", "SlaughterRaidToolsMarkButton", UIParent, "SecureActionButtonTemplate")
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "")
    button:RegisterForClicks("AnyUp", "AnyDown")
    header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    header:WrapScript(button, "OnClick", PRE_CLICK)
end

-- Writes the icon list into the button and sets the Ctrl + wheel keys. Protected in
-- combat: waits for it to end.
function Marks.Apply()
    if not SRT.db then return end
    if InCombatLockdown() then pending = true return end
    pending = nil
    if not button then build() end
    local order = Marks.Order()
    button:SetAttribute("srt-count", #order)
    for i = 1, 8 do button:SetAttribute("srt-icon" .. i, order[i]) end
    button:SetAttribute("srt-index", 0)
    ClearOverrideBindings(button)
    if db().wheel and #order > 0 then
        for _, key in ipairs(Marks.WHEEL_KEYS) do SetOverrideBindingClick(button, true, key, button:GetName(), "LeftButton") end
    end
    if SRT.Main then SRT.Main.Refresh() end
end

-- The next press starts with the first icon again.
function Marks.StartOver()
    if InCombatLockdown() then SRT:Print("Not in combat.") return end
    if button then button:SetAttribute("srt-index", 0) end
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

SRT:OnReady(Marks.Apply)
SRT:RegisterEvent("PLAYER_REGEN_ENABLED", function() if pending then Marks.Apply() end end)
