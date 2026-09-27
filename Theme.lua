-- Theme: colors, sizes and fonts. Same palette as Hush and AltBoard; font, text size and
-- accent come from the settings (Appearance page).
local _, SRT = ...

local Theme = {}
SRT.Theme = Theme

local function hex(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end
Theme.Hex = hex

Theme.colors = {
    window    = { hex("111418") },
    sidebar   = { hex("0D1013") },
    field     = { hex("15191E") },
    selected  = { hex("1A1F26") },
    line      = { hex("22272E") },
    text      = { hex("E6E8EB") },
    textDim   = { hex("9AA3AD") },
    textFaint = { hex("7C858F") },
    good      = { hex("3FC77F") },
    warn      = { hex("E8A33D") },
    bad       = { hex("E0564F") },
}

Theme.size = {
    titleH = 40,
    padding = 12,
}

Theme.TEXT_SIZES = { S = 11, M = 12, L = 14 }
Theme.DEFAULT_ACCENT = "3FC7EB"
Theme.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- Extra accent choices besides the default and the class colors.
Theme.EXTRA_ACCENTS = { { "C8332E", "Slaughter red" }, { "3FC77F", "Green" }, { "E8A33D", "Amber" }, { "E6E8EB", "White" } }

local function settings() return SRT.db and SRT.db.settings or {} end

function Theme:Color(key)
    local c = self.colors[key]
    return c[1], c[2], c[3]
end

local function classColor(classFile)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = classFile and colors and colors[classFile]
    if c then return c.r, c.g, c.b end
end
Theme.ClassColor = classColor

function Theme.ClassHex(classFile)
    local r, g, b = classColor(classFile)
    if not r then return nil end
    return ("%02X%02X%02X"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- The accent: the player's class color when useClassColor is on, otherwise settings.accent.
function Theme:Accent()
    local s = settings()
    if s.useClassColor then
        local r, g, b = classColor(select(2, UnitClass("player")))
        if r then return r, g, b end
    end
    local a = type(s.accent) == "string" and #s.accent == 6 and s.accent or self.DEFAULT_ACCENT
    return hex(a)
end

-- ---------------------------------------------------------------------------
-- Fonts. Font files in new addon folders are refused on WoW Forever, so the choice is
-- the game's fonts plus any LibSharedMedia fonts other addons registered (EllesmereUI).
-- ---------------------------------------------------------------------------

local FALLBACK = "Fonts\\FRIZQT__.TTF"

local BUILTIN_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri",        path = "Fonts\\skurri.ttf" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.ttf" },
}

local function normalizePath(p) return p and strlower((p:gsub("/", "\\"))) or "" end

local probe
local validCache = {}
-- Does this font file load here? (cached per path)
local function valid(path)
    if not path then return false end
    if validCache[path] == nil then
        probe = probe or UIParent:CreateFontString(nil, "BACKGROUND")
        probe:SetFont(FALLBACK, 12, "")
        local ok = probe:SetFont(path, 12, "")
        if ok == nil then ok = normalizePath(probe:GetFont()) == normalizePath(path) end
        validCache[path] = ok and true or false
    end
    return validCache[path]
end

local function lsm() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- { { name, path }, ... }: game fonts first, then shared fonts by name.
function Theme:AvailableFonts()
    local list, seen = {}, {}
    local function add(name, path)
        local key = normalizePath(path)
        if not seen[key] and valid(path) then
            seen[key] = true
            list[#list + 1] = { name = name, path = path }
        end
    end
    for _, f in ipairs(BUILTIN_FONTS) do add(f.name, f.path) end
    local L = lsm()
    if L then
        local shared = {}
        for name, path in pairs(L:HashTable("font") or {}) do shared[#shared + 1] = { name = name, path = path } end
        sort(shared, function(a, b) return a.name < b.name end)
        for _, f in ipairs(shared) do add(f.name, f.path) end
    end
    return list
end

local function fontPath(name)
    for _, f in ipairs(BUILTIN_FONTS) do if f.name == name then return f.path end end
    local L = lsm()
    return L and L:IsValid("font", name) and L:Fetch("font", name) or nil
end

-- The chosen font's path, or the game font if it is missing/refused (checked per call:
-- shared fonts may register after us).
function Theme:FontPath()
    local p = fontPath(settings().font)
    return p and valid(p) and p or FALLBACK
end

function Theme:TextSize(delta)
    return (self.TEXT_SIZES[settings().textSize] or 12) + (delta or 0)
end

function Theme:SetFont(fs, delta)
    fs:SetFont(self:FontPath(), self:TextSize(delta), "")
    fs:SetShadowOffset(0, 0)
end

-- ---------------------------------------------------------------------------
-- Pixel-perfect sizing
-- ---------------------------------------------------------------------------

function Theme:Pixel(frame)
    local physH = 1080
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then physH = h end
    end
    return 768 / physH / (frame or UIParent):GetEffectiveScale()
end
