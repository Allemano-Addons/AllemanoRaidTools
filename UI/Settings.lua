-- Settings pages in the main window: Appearance (accent like Hush, font, sizes) and
-- Advanced (announcements, debug, probe). Every change applies at once.
local _, SRT = ...

local Theme, W = SRT.Theme, SRT.Widgets
local Main = SRT.Main

local LABEL_X, CONTROL_X, ROW = 26, 230, 38

local function set(key, value)
    SRT:SetSetting(key, value)
    Main.Refresh()
end

-- A page builder: rows of label (+ faint help) on the left and a control on the right.
local function newPage(page)
    local p = { y = 18, controls = {} }
    function p:Heading(text)
        self.y = self.y + 10
        local fs = W.Text(page, -2, "text")
        fs:SetPoint("TOPLEFT", LABEL_X, -self.y)
        fs:SetText(strupper(text))
        W.OnAccent(function(r, g, b) fs:SetTextColor(r, g, b) end)
        self.y = self.y + 26
    end
    function p:Row(label, help, control, offsetY)
        local fs = W.Text(page, 0, "text")
        fs:SetPoint("TOPLEFT", LABEL_X, -(self.y + 6))
        fs:SetText(label)
        if help then
            local h = W.Text(page, -2, "textFaint")
            h:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
            h:SetText(help)
        end
        control:SetPoint("TOPLEFT", CONTROL_X, -(self.y + (offsetY or 2)))
        self.y = self.y + ROW + (help and 8 or 0)
        if control.refresh then self.controls[#self.controls + 1] = control end
    end
    function p:Toggle(label, help, key)
        local t = W.Toggle(page, function(on) set(key, on) end)
        t.refresh = function() t:Set(SRT.db.settings[key]) end
        self:Row(label, help, t, 6)
        return t
    end
    function p:Refresh()
        for _, c in ipairs(self.controls) do c.refresh() end
    end
    return p
end

Main.RegisterPage("appearance", function(page)
    local p = newPage(page)
    local s = SRT.db.settings

    p:Heading("Accent color")
    local swatches = CreateFrame("Frame", nil, page)
    swatches:SetSize(14 * 28, 22)
    swatches.list = {}
    local function addSwatch(hex, tooltip)
        local sw = W.Swatch(swatches, hex, function()
            SRT:SetSetting("useClassColor", false)
            set("accent", hex)
            p:Refresh()
        end, tooltip)
        sw.hex = hex
        sw:SetPoint("LEFT", #swatches.list * 28, 0)
        swatches.list[#swatches.list + 1] = sw
    end
    addSwatch(Theme.DEFAULT_ACCENT, "SRT (default)")
    for _, class in ipairs(Theme.CLASS_ORDER) do
        local hex = Theme.ClassHex(class)
        if hex then addSwatch(hex, LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class) end
    end
    for _, e in ipairs(Theme.EXTRA_ACCENTS) do addSwatch(e[1], e[2]) end
    swatches.refresh = function()
        for _, sw in ipairs(swatches.list) do
            sw:SetSelected(not s.useClassColor and strupper(s.accent or "") == sw.hex)
            sw:SetAlpha(s.useClassColor and 0.4 or 1)
        end
    end
    p:Row("Color", "Buttons, headings and bars.", swatches, 4)
    p:Toggle("Use my class color", "Follows the class of the character you are playing.", "useClassColor")

    p:Heading("Text")
    local font = W.Dropdown(page, 220, function()
        local opts = {}
        for _, f in ipairs(Theme:AvailableFonts()) do opts[#opts + 1] = { value = f.name, label = f.name, font = f.path } end
        return opts
    end, function(v) set("font", v) end)
    font.refresh = function() font:Set(s.font) end
    p:Row("Font", "Game fonts and fonts shared by other addons.", font)
    local size = W.Segment(page, {
        { value = "S", label = "Small" }, { value = "M", label = "Medium" }, { value = "L", label = "Large" },
    }, function(v) set("textSize", v) end)
    size.refresh = function() size:Set(s.textSize) end
    p:Row("Text size", nil, size, 4)

    p:Heading("Window")
    local alpha = W.Slider(page, 50, 100, 5, 200, function(v) return v .. "%" end,
        function(v) set("bgAlpha", v / 100) end)
    alpha.refresh = function() alpha:Set(floor((s.bgAlpha or 0.97) * 100 + 0.5)) end
    p:Row("Background", nil, alpha, 8)
    local scale = W.Slider(page, 70, 130, 5, 200, function(v) return v .. "%" end,
        function(v) set("scale", v / 100) end)
    scale.refresh = function() scale:Set(floor((s.scale or 1) * 100 + 0.5)) end
    p:Row("Window scale", nil, scale, 8)
    local reset = W.Button(page, "Reset", nil, function() Main.ResetPosition() end, 26)
    p:Row("Window position", "Moves the window back to the center.", reset)

    return function() p:Refresh() end
end)

Main.RegisterPage("advanced", function(page)
    local p = newPage(page)

    p:Heading("Raid chat")
    p:Toggle("Announce breaks", "Posts \"Break 10 min, back at 21:14\" for raiders without SRT.", "announceBreak")

    p:Heading("Development")
    p:Toggle("Addon message debug", "Prints every SRT message sent and received in chat.", "debugComm")
    local probe = W.Button(page, "Run", nil, function() SlashCmdList.SLAUGHTERRAIDTOOLS("probe") end, 26)
    p:Row("Client probe", "Records what WoW Forever supports. /reload afterwards.", probe)
    local combat = W.Button(page, "Arm", nil, function()
        SRT.Probe.ArmCombat()
        Main.Refresh()
    end, 26)
    p:Row("Combat probe", "Records the next fights (a dungeon boss is best).", combat)
    local version = W.Button(page, "Check", nil, function() SRT.Version.Check() end, 26)
    p:Row("Version check", "Who in the group runs which SRT version.", version)
    local errors = W.Button(page, "Show", nil, function() SlashCmdList.SLAUGHTERRAIDTOOLS("errors") end, 26)
    p:Row("Errors", "Lua errors are hidden on WoW Forever; SRT keeps the last 10.", errors)

    return function() p:Refresh() end
end)

SRT:AddSlashCommand("settings", function() Main.Toggle("appearance") end, "open the settings")
