-- Raid check: who has which consumables and buffs, from the group's auras plus what every
-- ART user reports about themselves (weapon oil and durability cannot be read for others).
-- What counts is a list of editable categories (the Forever meta is not known yet):
--   { id, short, name, kind, match = "Flask of, Supreme Power, 17628", optional, on }
-- kind "aura" (default): has a buff whose name contains one of the words, or whose spell
-- ID is listed. Special kinds: "ready" (ready check answer), "weapon" (temporary weapon
-- enchant, self-reported), "durability" (lowest item %, self-reported), "blessings"
-- (every matching buff, shown as short names).
local _, ART = ...

local RaidCheck = {}
ART.RaidCheck = RaidCheck

local MAX_AURAS = 40

RaidCheck.DEFAULTS = {
    { id = "ready", short = "Ready", name = "Ready check", kind = "ready", on = true },
    { id = "flask", short = "Flask", name = "Flask", on = true,
        match = "Flask of, Supreme Power, Distilled Wisdom, Chromatic Resistance, 17626, 17627, 17628, 17629" },
    { id = "battle", short = "B.Elix", name = "Battle elixir", on = true,
        match = "Elixir of the Mongoose, Elixir of the Giants, Greater Arcane Elixir, Arcane Elixir, Shadow Power, "
            .. "Greater Firepower, Frost Power, Greater Agility, Juju Power, Juju Might, Winterfall Firewater, "
            .. "17538, 11405, 17539, 11390, 11474, 26276, 21920, 11334, 16323, 16329, 17038" },
    { id = "guardian", short = "G.Elix", name = "Guardian elixir", on = true,
        match = "Greater Armor, Health II, Gift of Arthas, Spirit of Zanza, Greater Intellect, Mana Regeneration, "
            .. "11348, 3593, 11371, 24382, 11396, 24363" },
    { id = "food", short = "Food", name = "Food buff", on = true, match = "Well Fed, 18192, 18194, 22730, 25661" },
    { id = "oil", short = "Oil", name = "Weapon oil / stone", kind = "weapon", on = true },
    { id = "rune", short = "Rune", name = "Rune", on = false, match = "" },
    { id = "int", short = "Int", name = "Arcane Intellect", on = true, match = "Arcane Intellect, Arcane Brilliance" },
    { id = "stam", short = "Stam", name = "Fortitude", on = true, match = "Power Word: Fortitude, Prayer of Fortitude" },
    { id = "motw", short = "MotW", name = "Mark of the Wild", on = true, match = "Mark of the Wild, Gift of the Wild" },
    { id = "spirit", short = "Spirit", name = "Divine Spirit", on = true, optional = true, match = "Divine Spirit, Prayer of Spirit" },
    { id = "ap", short = "AP", name = "Attack power", on = true, optional = true, match = "Battle Shout, Trueshot Aura" },
    { id = "scroll", short = "Scroll", name = "Scroll", on = true, optional = true, match = "12174, 12175, 12176, 12177, 12178, 12179" },
    { id = "ss", short = "SS", name = "Soulstone", on = true, optional = true, match = "Soulstone Resurrection" },
    { id = "dur", short = "Dur", name = "Durability", kind = "durability", on = true },
    { id = "bless", short = "Blessings", name = "Paladin blessings", kind = "blessings", on = true, match = "Blessing of" },
}

local listeners = {}
function RaidCheck.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do ART:Call("raid check listener", fn) end
end

local function db() return ART.db.raidcheck end

function RaidCheck.Categories() return db().categories end

function RaidCheck.Enabled()
    local out = {}
    for _, c in ipairs(db().categories) do if c.on then out[#out + 1] = c end end
    return out
end

function RaidCheck.ResetCategories()
    db().categories = CopyTable(RaidCheck.DEFAULTS)
    changed()
end

function RaidCheck.AddCategory()
    local cats = db().categories
    local n = 1
    for _, c in ipairs(cats) do
        local k = tonumber((c.id or ""):match("^custom(%d+)$"))
        if k and k >= n then n = k + 1 end
    end
    tinsert(cats, { id = "custom" .. n, short = "New", name = "New category", match = "", on = true, custom = true })
    changed()
end

function RaidCheck.RemoveCategory(id)
    local cats = db().categories
    for i, c in ipairs(cats) do
        if c.id == id then tremove(cats, i) break end
    end
    changed()
end

function RaidCheck.Changed() changed() end

-- "Flask of, 17628" -> { names = { "flask of" }, ids = { [17628] = true } }
local function parseMatch(text)
    local names, ids = {}, {}
    for entry in (text or ""):gmatch("[^,]+") do
        entry = strtrim(entry)
        local id = tonumber(entry)
        if id then ids[id] = true elseif entry ~= "" then names[#names + 1] = strlower(entry) end
    end
    return { names = names, ids = ids }
end

local function matches(m, name, spellId)
    if spellId and m.ids[spellId] then return true end
    if name then
        local lname = strlower(name)
        for _, n in ipairs(m.names) do
            if lname:find(n, 1, true) then return true end
        end
    end
    return false
end

-- "Greater Blessing of Might" -> "Mi", "Blessing of Sanctuary" -> "Sn".
local BLESS_SHORT = { might = "Mi", kings = "Ki", wisdom = "Wi", salvation = "Sa", light = "Li", sanctuary = "Sn", protection = "Pr", freedom = "Fr", sacrifice = "Sc" }
local function blessShort(name)
    local word = strlower(name):match("blessing of (%a+)")
    return word and (BLESS_SHORT[word] or word:sub(1, 2):gsub("^%l", strupper)) or name:sub(1, 2)
end

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

local function safe(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The unit's buffs: { { name, spellId, expires } }, or nil when they cannot be read
-- (out of range / not visible).
local function readAuras(unit)
    if not UnitIsVisible(unit) then return nil end
    local get = C_UnitAuras and (C_UnitAuras.GetBuffDataByIndex or C_UnitAuras.GetAuraDataByIndex)
    if not get then return nil end
    local out = {}
    for i = 1, MAX_AURAS do
        local ok, a = pcall(get, unit, i, "HELPFUL")
        if not ok or not a then break end
        local name = safe(a.name)
        if name then
            out[#out + 1] = { name = name, spellId = safe(a.spellId), expires = safe(a.expirationTime),
                icon = safe(a.icon), id = safe(a.auraInstanceID) }
        end
    end
    return out
end

local ready = {}   -- [nameKey] = true / false (ready check answer)
local reports = {} -- [nameKey] = { dur, mh, mhLeft, t } from ART users
local auraReports = {} -- [nameKey] = { list = { { id, left } }, t }: ART users' own buffs
local scan         -- last result, see RaidCheck.Scan
local REPORT_MAX_AGE = 300 -- a buff report older than this is not used

-- Buffs of a player who is too far away to read, from their own ART report.
local function reportedAuras(key)
    local r = auraReports[key]
    if not r or GetTime() - r.t > REPORT_MAX_AGE then return nil end
    local out = {}
    for _, a in ipairs(r.list) do
        local name, icon = ART.Compat.SpellInfo(a.id)
        if name then
            out[#out + 1] = { name = name, spellId = a.id, icon = icon, expires = a.left > 0 and (r.t + a.left) or nil }
        end
    end
    return out
end

-- Result: { at, rows = { { name, unit, classFile, group, cells = { [catId] = cell } } },
-- totals = { [catId] = { have, total } } }. cell = { state = "yes"/"no"/"unknown"/"low",
-- text }.
function RaidCheck.Scan()
    local cats = RaidCheck.Enabled()
    local parsed = {}
    for _, c in ipairs(cats) do parsed[c.id] = parseMatch(c.match) end
    local now = GetTime()
    local rows, totals = {}, {}
    for _, c in ipairs(cats) do totals[c.id] = { have = 0, total = 0 } end
    for _, m in ipairs(ART.Compat.GroupRoster()) do
        local key = ART.Compat.NameKey(m.name)
        local auras = m.online and readAuras(m.unit) or nil
        local remote
        if not auras and m.online then
            auras = reportedAuras(key)
            remote = auras ~= nil
        end
        local report = reports[key]
        local row = { name = m.name, unit = m.unit, classFile = select(2, UnitClass(m.unit)), group = m.group,
            online = m.online, remote = remote, cells = {} }
        for _, c in ipairs(cats) do
            local cell
            local kind = c.kind or "aura"
            if kind == "ready" then
                local r = ready[key]
                if r == nil then cell = { state = "unknown", text = RaidCheck.running and "..." or "" }
                elseif r == "afk" then cell = { state = "no", text = "afk" }
                elseif r then cell = { state = "yes", text = "ok" }
                else cell = { state = "no", text = "no" } end
            elseif kind == "weapon" then
                if not report or report.mh == nil then cell = { state = "unknown", text = "?" }
                elseif report.mh then
                    local left = report.mhLeft and max(0, report.mhLeft - (now - report.t))
                    cell = { state = (left and left < 600) and "low" or "yes", text = left and ("%dm"):format(floor(left / 60)) or "ok" }
                else cell = { state = "no", text = "x" } end
            elseif kind == "durability" then
                if not report or not report.dur then cell = { state = "unknown", text = "?" }
                else
                    local d = report.dur
                    cell = { state = d < db().minDurability and "no" or (d < 80 and "low" or "yes"), text = d .. "%" }
                end
            elseif not auras then
                cell = { state = "unknown", text = m.online and "?" or "off" }
            elseif kind == "blessings" then
                local list, seen, found = {}, {}, {}
                for _, a in ipairs(auras) do
                    if matches(parsed[c.id], a.name, a.spellId) then
                        local s = blessShort(a.name)
                        if not seen[s] then
                            seen[s] = true
                            list[#list + 1] = s
                            found[#found + 1] = a
                        end
                    end
                end
                sort(list)
                cell = { state = #list > 0 and "yes" or "no", text = #list > 0 and table.concat(list, " ") or "x", auras = found }
            else
                local best
                for _, a in ipairs(auras) do
                    if matches(parsed[c.id], a.name, a.spellId) then
                        local left = a.expires and a.expires > 0 and max(0, a.expires - now) or nil
                        if not best or (left or math.huge) > (best.left or math.huge) then best = { left = left, aura = a } end
                    end
                end
                if best then
                    local left = best.left
                    cell = { state = (left and left < 600) and "low" or "yes", text = left and ("%dm"):format(floor(left / 60)) or "ok",
                        aura = best.aura, left = left }
                else
                    cell = { state = c.optional and "optional" or "no", text = "x" }
                end
            end
            row.cells[c.id] = cell
            local t = totals[c.id]
            if cell.state ~= "unknown" then
                t.total = t.total + 1
                if cell.state == "yes" or cell.state == "low" then t.have = t.have + 1 end
            end
        end
        rows[#rows + 1] = row
    end
    sort(rows, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)
    scan = { at = time(), rows = rows, totals = totals, cats = cats }
    changed()
    return scan
end

function RaidCheck.Last() return scan end

-- Names missing a required category: { { cat, names = { ... } } }.
function RaidCheck.Missing(result)
    result = result or scan
    local out = {}
    if not result then return out end
    for _, c in ipairs(result.cats) do
        if not c.optional and c.kind ~= "ready" then
            local names = {}
            for _, row in ipairs(result.rows) do
                local cell = row.cells[c.id]
                if cell and cell.state == "no" then names[#names + 1] = (row.name:match("^(%S+)") or row.name) end
            end
            if #names > 0 then out[#out + 1] = { cat = c, names = names } end
        end
    end
    return out
end

-- "Missing Flask (3): A, B, C", one chat line per category (split when too long).
function RaidCheck.PostMissing()
    local channel = ART.Compat.GroupChatChannel()
    if not channel then ART:Print("You are not in a group.") return end
    local lines = {}
    for _, m in ipairs(RaidCheck.Missing()) do
        local line = ("Missing %s (%d): "):format(m.cat.name, #m.names)
        for i, n in ipairs(m.names) do
            local add = (i > 1 and ", " or "") .. n
            if #line + #add > 250 then
                lines[#lines + 1] = line
                line = "  " .. n
            else
                line = line .. add
            end
        end
        lines[#lines + 1] = line
    end
    if #lines == 0 then lines[1] = "Raid check: nobody is missing anything." end
    for i, line in ipairs(lines) do
        C_Timer.After((i - 1) * 0.3, function() ART.Compat.SendChat(line, channel) end)
    end
end

-- ---------------------------------------------------------------------------
-- Self report (weapon enchant, durability) and ready check answers
-- ---------------------------------------------------------------------------

local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

-- Lowest durability % of the worn items, nil when unknown.
function RaidCheck.OwnDurability()
    if not GetInventoryItemDurability then return nil end
    local low
    for _, slot in ipairs(SLOTS) do
        local ok, cur, maxv = pcall(GetInventoryItemDurability, slot)
        cur, maxv = ok and safe(cur), ok and safe(maxv)
        if cur and maxv and maxv > 0 then
            local p = floor(cur / maxv * 100 + 0.5)
            if not low or p < low then low = p end
        end
    end
    return low
end

-- Main hand temporary enchant: has, seconds left.
function RaidCheck.OwnWeapon()
    if not GetWeaponEnchantInfo then return nil end
    local ok, has, expires = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    has, expires = safe(has), safe(expires)
    return has and true or false, expires and floor(expires / 1000) or nil
end

local function ownReport()
    local has, left = RaidCheck.OwnWeapon()
    return { dur = RaidCheck.OwnDurability(), mh = has, mhLeft = left, t = GetTime() }
end

-- Our own buffs as "spellId:secondsLeft,..." (0 = no end), so the leader sees them even
-- when we are too far away for the game to tell them.
local function ownAuraPayload()
    local list = {}
    local now = GetTime()
    for _, a in ipairs(readAuras("player") or {}) do
        if a.spellId then
            local left = a.expires and a.expires > 0 and floor(max(0, a.expires - now)) or 0
            list[#list + 1] = a.spellId .. ":" .. left
        end
    end
    return table.concat(list, ",")
end

local function sendReport(channel, target)
    local r = ownReport()
    local payload = ("%s|%s|%s"):format(r.dur or "", r.mh == nil and "" or (r.mh and "1" or "0"), r.mhLeft or "")
    ART.Comm.Send("RCR", payload, channel, target)
    ART.Comm.Send("RCA", ownAuraPayload(), channel, target)
end

ART.Comm.Register("RCA", function(sender, payload)
    local list = {}
    for id, left in payload:gmatch("(%d+):(%d+)") do
        list[#list + 1] = { id = tonumber(id), left = tonumber(left) }
    end
    auraReports[ART.Compat.NameKey(sender)] = { list = list, t = GetTime() }
    if scan then RaidCheck.Scan() end
end)

ART.Comm.Register("RCR", function(sender, payload)
    local dur, mh, left = payload:match("^(%d*)|(%d?)|(%d*)$")
    if not dur then return end
    local weapon -- nil = their client could not tell
    if mh == "1" then weapon = true elseif mh == "0" then weapon = false end
    reports[ART.Compat.NameKey(sender)] = { dur = tonumber(dur), mh = weapon, mhLeft = tonumber(left), t = GetTime() }
    if scan then RaidCheck.Scan() end
end)

-- The leader's "Scan" asks every ART user for a fresh report.
ART.Comm.Register("RCQ", function(_, _, channel)
    sendReport(channel)
end)

function RaidCheck.Refresh()
    reports[ART.Compat.NameKey(ART.Compat.PlayerName())] = ownReport()
    if IsInGroup() then ART.Comm.Send("RCQ", "") end
    RaidCheck.Scan()
    -- Reports arrive over the next seconds.
    C_Timer.After(3, function() ART:Call("raid check", RaidCheck.Scan) end)
end

-- Everyone answered "ready" (after the check, nobody unanswered).
function RaidCheck.AllReady()
    for _, m in ipairs(ART.Compat.GroupRoster()) do
        if ready[ART.Compat.NameKey(m.name)] ~= true then return false end
    end
    return true
end

-- A ready check: the ART ready check window shows everyone's consumables while it runs
-- (db.raidcheck.popup = "all", "lead" or "off"); our own report goes to the leader.
ART:RegisterEvent("READY_CHECK", function(_, initiator, timeLeft)
    wipe(ready)
    RaidCheck.running = true
    -- The initiator is ready by default.
    if initiator then ready[ART.Compat.NameKey(initiator)] = true end
    reports[ART.Compat.NameKey(ART.Compat.PlayerName())] = ownReport()
    if IsInGroup() then sendReport() end
    local popup = db().popup
    if popup == "all" or (popup == "lead" and ART.Compat.IsLeaderOrAssist()) then
        RaidCheck.Refresh()
        if ART.ReadyWindow then ART.ReadyWindow.Start(tonumber(timeLeft) or 30) end
    elseif scan then
        RaidCheck.Scan()
    end
end)

ART:RegisterEvent("READY_CHECK_CONFIRM", function(_, unit, isReady)
    local name = unit and ART.Compat.UnitFullName(unit)
    if name then ready[ART.Compat.NameKey(name)] = isReady and true or false end
    if scan then RaidCheck.Scan() end
end)

ART:RegisterEvent("READY_CHECK_FINISHED", function()
    RaidCheck.running = nil
    -- Who never answered was away.
    for _, m in ipairs(ART.Compat.GroupRoster()) do
        local key = ART.Compat.NameKey(m.name)
        if ready[key] == nil then ready[key] = "afk" end
    end
    if scan then RaidCheck.Scan() end
    if ART.ReadyWindow then ART.ReadyWindow.Finish(RaidCheck.AllReady()) end
end)

-- Buffs change during the check (people take their flask): scan again, at most twice a second.
local auraPending
ART:RegisterEvent("UNIT_AURA", function(_, unit)
    if auraPending or not (ART.ReadyWindow and ART.ReadyWindow.IsShown()) then return end
    if not unit or not (unit == "player" or unit:match("^raid%d") or unit:match("^party%d")) then return end
    auraPending = true
    C_Timer.After(0.5, function()
        auraPending = nil
        ART:Call("raid check", RaidCheck.Scan)
    end)
end)

-- ---------------------------------------------------------------------------
-- Tooltip for one cell: the game's own buff tooltip when possible.
-- ---------------------------------------------------------------------------

local function fmtLeft(left)
    if not left then return nil end
    if left >= 3600 then return ("%dh %dm left"):format(floor(left / 3600), floor(left % 3600 / 60)) end
    return ("%dm %ds left"):format(floor(left / 60), floor(left % 60))
end

function RaidCheck.ShowCellTooltip(owner, row, cat, cell)
    if not cell then return end
    local aura = cell.aura
    if aura and GameTooltip and row.unit then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        local ok = aura.id and GameTooltip.SetUnitBuffByAuraInstanceID
            and pcall(GameTooltip.SetUnitBuffByAuraInstanceID, GameTooltip, row.unit, aura.id, "HELPFUL")
        if not ok and aura.spellId and GameTooltip.SetSpellByID then ok = pcall(GameTooltip.SetSpellByID, GameTooltip, aura.spellId) end
        if not ok then GameTooltip:SetText(aura.name) end
        GameTooltip:AddLine(row.name .. (cell.left and (" \194\183 " .. fmtLeft(cell.left)) or ""), 0.6, 0.64, 0.68)
        if row.remote then GameTooltip:AddLine("Reported by ART (out of range)", 0.49, 0.52, 0.56) end
        GameTooltip:Show()
        return
    end
    local lines = { cat.name .. " \194\183 " .. row.name }
    if cell.auras then
        for _, a in ipairs(cell.auras) do lines[#lines + 1] = a.name end
    elseif cell.state == "unknown" then
        lines[#lines + 1] = (cat.kind == "weapon" or cat.kind == "durability") and "Unknown: no ART (or no report yet)."
            or "Unknown: out of range or offline."
    elseif cell.state == "no" or cell.state == "optional" then
        lines[#lines + 1] = cat.kind == "ready" and "Not ready" or "Missing"
    else
        lines[#lines + 1] = cell.text
    end
    if row.remote and cat.kind ~= "ready" and cat.kind ~= "weapon" and cat.kind ~= "durability" then
        lines[#lines + 1] = "Reported by ART (out of range)"
    end
    ART.Widgets.ShowTooltip(owner, lines)
end

function RaidCheck.HideCellTooltip()
    if GameTooltip then GameTooltip:Hide() end
    ART.Widgets.HideTooltip()
end

ART:AddSlashCommand("check", function()
    RaidCheck.Refresh()
    ART.Main.Toggle("raidcheck")
end, "raid check: consumables and buffs of the group")
