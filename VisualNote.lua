-- Visual note: a drawing (pen, lines, arrows, raid icons, text) on a background (none, a
-- game map, or a picture from AllemanoRaidTools\Images), shared with the raid.
-- Kept light on purpose: strokes are simplified and sent as 4 characters per point, the
-- whole note is a few kB like a text note; drawing happens only while a window shows it,
-- with a cap on how many lines are drawn.
--
-- A note: { title, bg = { kind = "none"/"map"/"image", ref = mapID or file name },
--           items = { item, ... } } with coordinates 0..4095 across the 2:1 canvas:
--   { k = "p", c, w, pts = { x1, y1, x2, y2, ... } }   pen stroke
--   { k = "l" / "a", c, w, x1, y1, x2, y2 }            line / arrow
--   { k = "i", n = 1..8, x, y }                        raid icon
--   { k = "t", c, x, y, s }                            text
local _, ART = ...

local VisualNote = {}
ART.VisualNote = VisualNote

VisualNote.MAX = 4095
VisualNote.MAX_SEGMENTS = 4000   -- line pieces drawn per canvas at most
VisualNote.MAX_POINTS = 200      -- per stroke
VisualNote.MAX_BYTES = 12000     -- a shared note at most
VisualNote.COLORS = { "E6E8EB", "E0564F", "E8A33D", "F2D64B", "3FC77F", "3FC7EB", "B57EDC", "111418" }
VisualNote.WIDTHS = { 2, 4, 7 }
VisualNote.IMAGE_PATH = "Interface\\AddOns\\AllemanoRaidTools\\Images\\"

local listeners = {}
function VisualNote.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do ART:Call("visual note listener", fn) end
end
VisualNote.Changed = changed

-- ---------------------------------------------------------------------------
-- Encoding: 64 safe characters, 2 per coordinate (12 bits).
-- ---------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, 64 do VALUE[ALPHABET:sub(i, i)] = i - 1 end
local function c1(n) return ALPHABET:sub(n + 1, n + 1) end
local function c2(n) return c1(floor(n / 64) % 64) .. c1(n % 64) end
local function clampCoord(v) return max(0, min(VisualNote.MAX, floor(v + 0.5))) end

function VisualNote.Encode(note)
    -- Fields are separated by "^" (tabs and newlines may not survive addon messages).
    local out = { "1", note.bg.kind, tostring(note.bg.ref or ""):gsub("[^%w_%-]", ""),
        ART.Notes.escape((note.title or ""):gsub("%^", "")) }
    local items = {}
    for _, it in ipairs(note.items) do
        if it.k == "p" then
            local n = floor(#it.pts / 2)
            local parts = { "p", c1(it.c - 1), c1(it.w - 1), c2(n) }
            for i = 1, n * 2 do parts[#parts + 1] = c2(clampCoord(it.pts[i])) end
            items[#items + 1] = table.concat(parts)
        elseif it.k == "l" or it.k == "a" then
            items[#items + 1] = it.k .. c1(it.c - 1) .. c1(it.w - 1) .. c2(clampCoord(it.x1)) .. c2(clampCoord(it.y1))
                .. c2(clampCoord(it.x2)) .. c2(clampCoord(it.y2))
        elseif it.k == "i" then
            items[#items + 1] = "i" .. c1(it.n - 1) .. c2(clampCoord(it.x)) .. c2(clampCoord(it.y))
        elseif it.k == "t" then
            local s = ART.Notes.escape(it.s or ""):sub(1, 200)
            items[#items + 1] = "t" .. c1(it.c - 1) .. c2(clampCoord(it.x)) .. c2(clampCoord(it.y)) .. c2(#s) .. s
        end
    end
    out[#out + 1] = table.concat(items)
    return table.concat(out, "^")
end

-- Returns the note, or nil for anything malformed (never errors on bad input).
function VisualNote.Decode(data)
    local version, kind, ref, title, body = (data or ""):match("^(%d+)%^(%a+)%^([^%^]*)%^([^%^]*)%^(.*)$")
    if version ~= "1" then return nil end
    local note = { title = ART.Notes.unescape(title), bg = { kind = kind, ref = tonumber(ref) or (ref ~= "" and ref or nil) }, items = {} }
    local pos, len = 1, #body
    local function take(n)
        if pos + n - 1 > len then error("short") end
        local s = body:sub(pos, pos + n - 1)
        pos = pos + n
        return s
    end
    local function n1() local v = VALUE[take(1)]; if not v then error("bad") end return v end
    local function n2() return n1() * 64 + n1() end
    local ok = pcall(function()
        while pos <= len do
            local k = take(1)
            if k == "p" then
                local it = { k = "p", c = n1() + 1, w = n1() + 1, pts = {} }
                local n = n2()
                for i = 1, n * 2 do it.pts[i] = n2() end
                note.items[#note.items + 1] = it
            elseif k == "l" or k == "a" then
                note.items[#note.items + 1] = { k = k, c = n1() + 1, w = n1() + 1, x1 = n2(), y1 = n2(), x2 = n2(), y2 = n2() }
            elseif k == "i" then
                note.items[#note.items + 1] = { k = "i", n = n1() + 1, x = n2(), y = n2() }
            elseif k == "t" then
                local it = { k = "t", c = n1() + 1, x = n2(), y = n2() }
                it.s = ART.Notes.unescape(take(n2()))
                note.items[#note.items + 1] = it
            else
                error("bad item")
            end
        end
    end)
    if not ok then return nil end
    return note
end

-- ---------------------------------------------------------------------------
-- Strokes: drop points that add nothing (Ramer-Douglas-Peucker), cap the count.
-- ---------------------------------------------------------------------------

local function simplifyRange(pts, first, last, eps, keep)
    local ax, ay, bx, by = pts[first * 2 - 1], pts[first * 2], pts[last * 2 - 1], pts[last * 2]
    local dx, dy = bx - ax, by - ay
    local lenSq = dx * dx + dy * dy
    local worst, worstI = 0, nil
    for i = first + 1, last - 1 do
        local px, py = pts[i * 2 - 1], pts[i * 2]
        local d
        if lenSq == 0 then
            d = (px - ax) ^ 2 + (py - ay) ^ 2
        else
            local cross = (px - ax) * dy - (py - ay) * dx
            d = cross * cross / lenSq
        end
        if d > worst then worst, worstI = d, i end
    end
    if worstI and worst > eps * eps then
        keep[worstI] = true
        simplifyRange(pts, first, worstI, eps, keep)
        simplifyRange(pts, worstI, last, eps, keep)
    end
end

function VisualNote.Simplify(pts, eps)
    local n = floor(#pts / 2)
    if n <= 2 then return pts end
    local keep = { [1] = true, [n] = true }
    simplifyRange(pts, 1, n, eps or 6, keep)
    local out = {}
    for i = 1, n do
        if keep[i] then
            out[#out + 1] = pts[i * 2 - 1]
            out[#out + 1] = pts[i * 2]
        end
    end
    -- Still too long: keep every k-th point.
    local count = #out / 2
    if count > VisualNote.MAX_POINTS then
        local step = count / VisualNote.MAX_POINTS
        local thin = {}
        for i = 0, VisualNote.MAX_POINTS - 1 do
            local j = floor(i * step) + 1
            thin[#thin + 1] = out[j * 2 - 1]
            thin[#thin + 1] = out[j * 2]
        end
        thin[#thin + 1] = out[#out - 1]
        thin[#thin + 1] = out[#out]
        out = thin
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Saved notes (the drawer's library) and the received one
-- ---------------------------------------------------------------------------

local function db() return ART.db.visual end

function VisualNote.New()
    return { title = "", bg = { kind = "none" }, items = {} }
end

-- The note being drawn (kept across sessions).
function VisualNote.Draft()
    local d = db()
    d.draft = d.draft or VisualNote.New()
    return d.draft
end

function VisualNote.SavedNames()
    local out = {}
    for name in pairs(db().saved) do out[#out + 1] = name end
    sort(out)
    return out
end

function VisualNote.Save(name)
    name = strtrim(name or "")
    if name == "" then return false end
    local draft = VisualNote.Draft()
    draft.title = name
    db().saved[name] = VisualNote.Encode(draft)
    changed()
    return true
end

function VisualNote.Load(name)
    local note = VisualNote.Decode(db().saved[name])
    if not note then return false end
    db().draft = note
    changed()
    return true
end

function VisualNote.Delete(name)
    db().saved[name] = nil
    changed()
end

function VisualNote.Received() return db().received and VisualNote.Decode(db().received.data), db().received end

-- ---------------------------------------------------------------------------
-- Sharing
-- ---------------------------------------------------------------------------

local function accepted(sender)
    local unit = ART.Compat.UnitForName(sender)
    if not unit then return false end
    if ART.db.settings.vnAcceptEveryone then return true end
    return ART.Compat.IsLeaderOrAssist(unit)
end

-- Sends the draft to the group; solo it is only shown to you.
function VisualNote.Send()
    local data = VisualNote.Encode(VisualNote.Draft())
    if #data > VisualNote.MAX_BYTES then
        ART:Print(("The drawing is too big to share (%d of %d bytes): remove some strokes."):format(#data, VisualNote.MAX_BYTES))
        return false
    end
    db().received = { data = data, sender = ART.Compat.PlayerName(), at = time() }
    changed()
    if ART.VisualViewer then ART.VisualViewer.Show() end
    if not IsInGroup() then
        ART:Print("Not in a group: the visual note is only shown to you.")
        return true
    end
    local parts = ART.Comm.Send("VN", data)
    ART:Print(("Sharing the visual note (%d bytes, %d part%s)."):format(#data, parts or 0, parts == 1 and "" or "s"))
    if not ART.Compat.IsLeaderOrAssist() then
        ART:Print("Only raiders who accept visual notes from everyone will see it (you are not leader or assistant).")
    end
    return true
end

ART.Comm.Register("VN", function(sender, data)
    if not accepted(sender) then return end
    if #data > VisualNote.MAX_BYTES or not VisualNote.Decode(data) then return end
    db().received = { data = data, sender = sender, at = time() }
    changed()
    if ART.db.settings.vnAutoShow and ART.VisualViewer then ART.VisualViewer.Show() end
end)

-- ---------------------------------------------------------------------------
-- Drawing a note into a canvas frame (editor and viewer share this).
-- ---------------------------------------------------------------------------

local function hexColor(i)
    return ART.Theme.Hex(VisualNote.COLORS[i] or VisualNote.COLORS[1])
end

-- A canvas: canvas.layer (frame the items are drawn on), pools of lines/icons/texts/tiles.
function VisualNote.CreateCanvas(parent)
    local c = CreateFrame("Frame", nil, parent)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(ART.Theme:Color("sidebar"))
    c.image = c:CreateTexture(nil, "BORDER")
    c.image:SetAllPoints()
    c.image:Hide()
    c.missing = ART.Widgets.Text(c, -1, "textFaint")
    c.missing:SetPoint("BOTTOM", 0, 8)
    c.tiles, c.lines, c.icons, c.texts, c.dots = {}, {}, {}, {}, {}
    c.used = { lines = 0, icons = 0, texts = 0, dots = 0 }
    return c
end

local function takeLine(c)
    c.used.lines = c.used.lines + 1
    local l = c.lines[c.used.lines]
    if not l then
        l = c:CreateLine(nil, "ARTWORK")
        c.lines[c.used.lines] = l
    end
    l:Show()
    return l
end

local function takeIcon(c)
    c.used.icons = c.used.icons + 1
    local t = c.icons[c.used.icons]
    if not t then
        t = c:CreateTexture(nil, "OVERLAY")
        c.icons[c.used.icons] = t
    end
    t:Show()
    return t
end

local function takeText(c)
    c.used.texts = c.used.texts + 1
    local fs = c.texts[c.used.texts]
    if not fs then
        fs = c:CreateFontString(nil, "OVERLAY")
        c.texts[c.used.texts] = fs
    end
    fs:Show()
    return fs
end

-- Map art: the map's tiles, fitted (letterboxed) into the canvas.
local function drawMap(c, mapID, w, h)
    for _, t in ipairs(c.tiles) do t:Hide() end
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return false end
    local okL, layers = pcall(C_Map.GetMapArtLayers, mapID)
    local layer = okL and type(layers) == "table" and layers[1]
    if not layer then return false end
    local okT, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not okT or type(files) ~= "table" or #files == 0 then return false end
    local lw, lh, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
    if not (lw and lh and tw and th) or lw <= 0 or lh <= 0 then return false end
    local scale = min(w / lw, h / lh)
    local ox, oy = (w - lw * scale) / 2, (h - lh * scale) / 2
    local cols = ceil(lw / tw)
    for i, file in ipairs(files) do
        local t = c.tiles[i]
        if not t then
            t = c:CreateTexture(nil, "BORDER")
            c.tiles[i] = t
        end
        local col, row = (i - 1) % cols, floor((i - 1) / cols)
        t:SetTexture(file)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", c, "TOPLEFT", ox + col * tw * scale, -(oy + row * th * scale))
        t:SetSize(tw * scale, th * scale)
        t:Show()
    end
    return true
end

local function segment(c, x1, y1, x2, y2, r, g, b, thick, sx, sy)
    if c.used.lines >= VisualNote.MAX_SEGMENTS then return end
    local l = takeLine(c)
    l:SetColorTexture(r, g, b, 1)
    l:SetThickness(thick)
    l:SetStartPoint("TOPLEFT", c, x1 * sx, -y1 * sy)
    l:SetEndPoint("TOPLEFT", c, x2 * sx, -y2 * sy)
end

-- A round joint (hides the notches where two thick pieces meet).
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function joint(c, x, y, r, g, b, thick, sx, sy)
    if c.used.dots >= VisualNote.MAX_SEGMENTS then return end
    c.used.dots = c.used.dots + 1
    local t = c.dots[c.used.dots]
    if not t then
        t = c:CreateTexture(nil, "ARTWORK")
        t:SetTexture(ROUND)
        c.dots[c.used.dots] = t
    end
    t:SetVertexColor(r, g, b, 1)
    t:SetSize(thick, thick)
    t:ClearAllPoints()
    t:SetPoint("CENTER", c, "TOPLEFT", x * sx, -y * sy)
    t:Show()
end

-- Rounds a stroke's corners for drawing (Chaikin): nothing more is sent, every client
-- smooths the same points itself. Only strokes with far-apart points need it: a densely
-- drawn stroke already looks round, and smoothing would double its pieces for nothing.
local SMOOTH_SPACING = 60 -- note units (about 12 px on an 800 px canvas)
local function smooth(p)
    local n = #p / 2
    if n < 3 then return p end
    local total = 0
    for i = 1, n - 1 do
        local dx, dy = p[i * 2 + 1] - p[i * 2 - 1], p[i * 2 + 2] - p[i * 2]
        total = total + math.sqrt(dx * dx + dy * dy)
    end
    if total / (n - 1) < SMOOTH_SPACING then return p end
    local out = { p[1], p[2] }
    for i = 1, n - 1 do
        local ax, ay, bx, by = p[i * 2 - 1], p[i * 2], p[i * 2 + 1], p[i * 2 + 2]
        out[#out + 1] = ax * 0.75 + bx * 0.25
        out[#out + 1] = ay * 0.75 + by * 0.25
        out[#out + 1] = ax * 0.25 + bx * 0.75
        out[#out + 1] = ay * 0.25 + by * 0.75
    end
    out[#out + 1] = p[#p - 1]
    out[#out + 1] = p[#p]
    return out
end
VisualNote.Smooth = smooth

-- Draws the note; returns the number of line segments used. skip = an item index to leave
-- out (the item being moved is drawn on its own layer meanwhile).
function VisualNote.Render(c, note, skip)
    for _, l in ipairs(c.lines) do l:Hide() end
    for _, t in ipairs(c.icons) do t:Hide() end
    for _, fs in ipairs(c.texts) do fs:Hide() end
    for _, t in ipairs(c.dots) do t:Hide() end
    c.used.lines, c.used.icons, c.used.texts, c.used.dots = 0, 0, 0, 0
    local w, h = c:GetWidth(), c:GetHeight()
    if not note or w <= 0 or h <= 0 then return 0 end
    local sx, sy = w / VisualNote.MAX, h / VisualNote.MAX
    local scale = w / 800 -- widths and icons grow with the canvas

    -- Background.
    c.image:Hide()
    c.missing:SetText("")
    for _, t in ipairs(c.tiles) do t:Hide() end
    local bg = note.bg or {}
    if bg.kind == "map" and bg.ref then
        if not drawMap(c, bg.ref, w, h) then c.missing:SetText("This map has no picture.") end
    elseif bg.kind == "image" and bg.ref then
        local ok = c.image:SetTexture(VisualNote.IMAGE_PATH .. bg.ref)
        if ok == false then
            c.missing:SetText(("Picture \"%s\" is missing: put %s.tga in AllemanoRaidTools\\Images and restart WoW."):format(bg.ref, bg.ref))
        else
            c.image:Show()
        end
    end

    for index, it in ipairs(note.items) do
        local r, g, b = hexColor(it.c)
        local thick = (VisualNote.WIDTHS[it.w or 1] or 2) * scale
        if index == skip then -- luacheck: ignore 542
            -- drawn elsewhere
        elseif it.k == "p" then
            local p = smooth(it.pts)
            local round = thick >= 3
            for i = 1, #p / 2 - 1 do
                segment(c, p[i * 2 - 1], p[i * 2], p[i * 2 + 1], p[i * 2 + 2], r, g, b, thick, sx, sy)
                if round then joint(c, p[i * 2 - 1], p[i * 2], r, g, b, thick, sx, sy) end
            end
            if round then joint(c, p[#p - 1], p[#p], r, g, b, thick, sx, sy) end
            if #p == 2 then joint(c, p[1], p[2], r, g, b, max(thick, 3), sx, sy) end
        elseif it.k == "l" or it.k == "a" then
            segment(c, it.x1, it.y1, it.x2, it.y2, r, g, b, thick, sx, sy)
            if it.k == "a" then
                -- Arrow head: two short lines at the end, in screen space so they keep their shape.
                local dx, dy = (it.x2 - it.x1) * sx, (it.y2 - it.y1) * sy
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0 then
                    local ux, uy = dx / len, dy / len
                    local head = min(len * 0.4, 14 * scale + thick * 2)
                    for _, s in ipairs({ 1, -1 }) do
                        local hx = it.x2 * sx - head * (ux * 0.866 - s * uy * 0.5)
                        local hy = it.y2 * sy - head * (uy * 0.866 + s * ux * 0.5)
                        segment(c, it.x2, it.y2, hx / sx, hy / sy, r, g, b, thick, sx, sy)
                    end
                end
            end
        elseif it.k == "i" then
            local t = takeIcon(c)
            local size = 26 * scale
            t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (it.n or 8))
            t:SetSize(size, size)
            t:ClearAllPoints()
            t:SetPoint("CENTER", c, "TOPLEFT", it.x * sx, -it.y * sy)
        elseif it.k == "t" then
            local fs = takeText(c)
            fs:SetFont(ART.Theme:FontPath(), max(8, floor(14 * scale + 0.5)), "OUTLINE")
            fs:SetTextColor(r, g, b)
            fs:SetText(it.s or "")
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", c, "TOPLEFT", it.x * sx, -it.y * sy)
        end
    end
    return c.used.lines
end

-- One more piece of a pen stroke while drawing (the whole note is drawn again when the
-- stroke ends).
function VisualNote.DrawSegment(c, it, x1, y1, x2, y2)
    local w, h = c:GetWidth(), c:GetHeight()
    if w <= 0 or h <= 0 then return end
    local r, g, b = hexColor(it.c)
    segment(c, x1, y1, x2, y2, r, g, b, (VisualNote.WIDTHS[it.w or 1] or 2) * w / 800, w / VisualNote.MAX, h / VisualNote.MAX)
end

-- Moves an item by (dx, dy), keeping it on the canvas.
function VisualNote.MoveItem(it, dx, dy)
    local M = VisualNote.MAX
    -- Shrink the move so no point leaves the canvas.
    local function limit(values, d)
        for _, v in ipairs(values) do
            if v + d < 0 then d = -v end
            if v + d > M then d = M - v end
        end
        return d
    end
    local xs, ys = {}, {}
    if it.k == "p" then
        for i = 1, #it.pts, 2 do xs[#xs + 1], ys[#ys + 1] = it.pts[i], it.pts[i + 1] end
    elseif it.k == "l" or it.k == "a" then
        xs, ys = { it.x1, it.x2 }, { it.y1, it.y2 }
    else
        xs, ys = { it.x }, { it.y }
    end
    dx, dy = limit(xs, dx), limit(ys, dy)
    if it.k == "p" then
        for i = 1, #it.pts, 2 do
            it.pts[i], it.pts[i + 1] = it.pts[i] + dx, it.pts[i + 1] + dy
        end
    elseif it.k == "l" or it.k == "a" then
        it.x1, it.y1, it.x2, it.y2 = it.x1 + dx, it.y1 + dy, it.x2 + dx, it.y2 + dy
    else
        it.x, it.y = it.x + dx, it.y + dy
    end
end

-- The item under canvas point (x, y) in note coordinates (for the eraser), or nil.
function VisualNote.HitTest(note, x, y, radius)
    radius = radius or 90
    local r2 = radius * radius
    local function near(px, py) return (px - x) ^ 2 + (py - y) ^ 2 <= r2 end
    local function nearSeg(ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        local len2 = dx * dx + dy * dy
        local t = len2 > 0 and max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / len2)) or 0
        return near(ax + t * dx, ay + t * dy)
    end
    for i = #note.items, 1, -1 do
        local it = note.items[i]
        if it.k == "p" then
            local p = it.pts
            if #p == 2 and near(p[1], p[2]) then return i end
            for j = 1, #p / 2 - 1 do
                if nearSeg(p[j * 2 - 1], p[j * 2], p[j * 2 + 1], p[j * 2 + 2]) then return i end
            end
        elseif it.k == "l" or it.k == "a" then
            if nearSeg(it.x1, it.y1, it.x2, it.y2) then return i end
        elseif (it.k == "i" or it.k == "t") and near(it.x, it.y) then
            return i
        end
    end
end

ART:AddSlashCommand("vn", function() if ART.VisualViewer then ART.VisualViewer.Toggle() end end, "show or hide the visual note")
