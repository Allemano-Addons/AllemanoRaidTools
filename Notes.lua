-- Notes: raid notes written by the leader, sent to everyone with SRT and shown in the note
-- window. Receivers confirm, so the leader sees who has the note. Players who join later
-- ask for it. Every character also has a personal note shown under the raid note.
--
-- Note text supports:
--   {rt1}..{rt8} or {star} {circle} {diamond} {triangle} {moon} {square} {cross} {skull}
--   {spell:12345}                  spell icon
--   {p:Name, Other Name}...{/p}    only these players see the text
-- Names of group members are shown in their class color, your own name in the accent.
local _, SRT = ...

local Notes = {}
SRT.Notes = Notes

Notes.MAX_LETTERS = 5000
local REQUEST_MAX_AGE = 12 * 3600 -- a note older than this is not handed to late joiners

local ICONS = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, x = 7, skull = 8 }
Notes.ICONS = ICONS

local listeners = {}
-- fn() runs whenever notes, the active note or confirmations change.
function Notes.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do SRT:Call("notes listener", fn) end
end
Notes.Changed = changed

-- ---------------------------------------------------------------------------
-- Saved notes (the leader's library)
-- ---------------------------------------------------------------------------

local function db() return SRT.db.notes end

function Notes.List() return db().list end

function Notes.Get(id)
    for _, n in ipairs(db().list) do if n.id == id then return n end end
end

function Notes.Selected()
    return Notes.Get(db().selected) or db().list[1]
end

function Notes.Select(id)
    db().selected = id
    changed()
end

function Notes.New(title)
    local d = db()
    local n = { id = d.nextId, title = title or ("Note " .. d.nextId), text = "", updated = time() }
    d.nextId = d.nextId + 1
    tinsert(d.list, 1, n)
    d.selected = n.id
    changed()
    return n
end

function Notes.Delete(id)
    local list = db().list
    for i, n in ipairs(list) do
        if n.id == id then
            tremove(list, i)
            break
        end
    end
    if db().selected == id then db().selected = list[1] and list[1].id end
    changed()
end

-- Saves without telling the listeners (called on every key stroke by the editor).
function Notes.Save(id, title, text)
    local n = Notes.Get(id)
    if not n then return end
    n.title, n.text, n.updated = title, text:sub(1, Notes.MAX_LETTERS), time()
end

function Notes.Personal()
    local key = UnitGUID("player") or SRT.Compat.PlayerName()
    return SRT.db.personal[key] or ""
end

function Notes.SetPersonal(text)
    local key = UnitGUID("player") or SRT.Compat.PlayerName()
    SRT.db.personal[key] = text ~= "" and text:sub(1, Notes.MAX_LETTERS) or nil
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function hexColor(r, g, b)
    return ("ff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- Is the player one of the names in a {p:...} list?
local function listed(list)
    local me = strlower(SRT.Compat.PlayerName())
    local first = strlower((UnitName("player")))
    for entry in list:gmatch("[^,]+") do
        entry = strlower(strtrim(entry))
        if entry == me or entry == first then return true end
    end
    return false
end

-- Plain (not pattern) replace of every `needle` in text.
local function replacePlain(text, needle, repl)
    local out, pos = {}, 1
    while true do
        local s, e = text:find(needle, pos, true)
        if not s then break end
        out[#out + 1] = text:sub(pos, s - 1)
        out[#out + 1] = repl(text:sub(s, e))
        pos = e + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

-- Removes the {p:...}...{/p} blocks the player may not see; keeps the rest as typed.
function Notes.Visible(text)
    return (text:gsub("{[pP]:([^}]*)}(.-){/[pP]}", function(list, inner)
        return listed(list) and inner or ""
    end))
end

function Notes.Render(text)
    text = Notes.Visible(text or "")
    -- Colored names become placeholders first, so later steps never touch them.
    local held = {}
    local function hold(s)
        held[#held + 1] = s
        return "\001" .. #held .. "\002"
    end
    local meFull, meFirst = SRT.Compat.PlayerName(), UnitName("player")
    local accent = hexColor(SRT.Theme:Accent())
    local full, first = {}, {}
    for _, m in ipairs(SRT.Compat.GroupMembers()) do
        local _, class = UnitClass(m.unit)
        local r, g, b = SRT.Theme.ClassColor(class)
        local color = r and hexColor(r, g, b)
        if SRT.Compat.NameKey(m.name) == SRT.Compat.NameKey(meFull) then color = accent end
        if color then
            full[#full + 1] = { m.name, color }
            first[strlower(m.name:match("^(%S+)") or m.name)] = color
        end
    end
    first[strlower(meFirst or "")] = accent
    if not full[1] then full[1] = { meFull, accent } end
    for _, f in ipairs(full) do
        if f[1]:find(" ", 1, true) then
            text = replacePlain(text, f[1], function(s) return hold("|c" .. f[2] .. s .. "|r") end)
        end
    end
    text = text:gsub("[%w\128-\255]+", function(word)
        local color = first[strlower(word)]
        if color then return hold("|c" .. color .. word .. "|r") end
    end)
    text = text:gsub("{(%a+)(%d?)}", function(name, n)
        name = strlower(name)
        local i = (name == "rt" and tonumber(n)) or (n == "" and ICONS[name])
        if i and i >= 1 and i <= 8 then return ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:0|t"):format(i) end
    end)
    text = text:gsub("{spell:(%d+)}", function(id)
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(tonumber(id))
        return icon and ("|T%s:0|t"):format(icon) or ""
    end)
    return (text:gsub("\001(%d+)\002", function(i) return held[tonumber(i)] end))
end

-- ---------------------------------------------------------------------------
-- Sending and receiving
-- ---------------------------------------------------------------------------

-- Newlines and tabs are escaped: addon messages may not carry them.
local function escape(s) return (s:gsub("~", "~~"):gsub("\n", "~n"):gsub("\t", "~t")) end
local UNESCAPE = { ["~"] = "~", n = "\n", t = "\t" }
local function unescape(s) return (s:gsub("~(.)", UNESCAPE)) end
Notes.escape, Notes.unescape = escape, unescape

local function hashOf(title, text) return tostring(SRT.Comm.Checksum(title .. "\n" .. text)) end

local function payload(note)
    return note.hash .. "\t" .. escape(note.title) .. "\t" .. escape(note.text)
end

-- The note shown in the note window (received, or sent by us).
function Notes.Active() return SRT.db.active end

local function activate(title, text, sender, hash)
    SRT.db.active = { title = title, text = text, sender = sender, at = time(), hash = hash }
    changed()
    if SRT.NoteWindow and SRT.db.settings.noteAutoShow then SRT.NoteWindow.Show() end
end

function Notes.CanSend()
    return IsInGroup() and SRT.Compat.IsLeaderOrAssist()
end

-- Sends a saved note to the group. Solo it is only shown to yourself (for testing).
function Notes.Send(id)
    local n = Notes.Get(id)
    if not n then return end
    local hash = hashOf(n.title, n.text)
    activate(n.title, n.text, SRT.Compat.PlayerName(), hash)
    if not IsInGroup() then
        SRT:Print("Not in a group: the note is only shown to you.")
        return
    end
    if not SRT.Compat.IsLeaderOrAssist() then
        SRT:Print("Only the raid leader or an assistant can send notes.")
        return
    end
    SRT.db.lastSent = { title = n.title, hash = hash, at = time(), acks = {} }
    local parts = SRT.Comm.Send("NOTE", payload(SRT.db.active))
    SRT:Print(("Sending \"%s\" to the group (%d part%s)."):format(n.title, parts or 0, parts == 1 and "" or "s"))
    changed()
end

function Notes.Resend()
    local a = SRT.db.active
    if not a or not Notes.CanSend() then return end
    SRT.db.lastSent = { title = a.title, hash = a.hash, at = time(), acks = {} }
    SRT.Comm.Send("NOTE", payload(a))
    changed()
end

-- Who has the last note we sent: { title, at, have, total, missing = { { name, noSRT, offline } } }
function Notes.Status()
    local sent = SRT.db.lastSent
    if not sent or not IsInGroup() then return nil end
    local s = { title = sent.title, at = sent.at, have = 0, total = 0, missing = {} }
    local me = SRT.Compat.NameKey(SRT.Compat.PlayerName())
    for _, m in ipairs(SRT.Compat.GroupMembers()) do
        local key = SRT.Compat.NameKey(m.name)
        s.total = s.total + 1
        if key == me or sent.acks[key] then
            s.have = s.have + 1
        else
            s.missing[#s.missing + 1] = { name = m.name, noSRT = not SRT.Comm.seen[key], offline = not m.online }
        end
    end
    return s
end

-- Only the leader and assistants may change the raid's note.
local function fromLeader(sender)
    local unit = SRT.Compat.UnitForName(sender)
    return unit and SRT.Compat.IsLeaderOrAssist(unit)
end

SRT.Comm.Register("NOTE", function(sender, data)
    if not fromLeader(sender) then return end
    local hash, title, text = data:match("^(%d+)\t([^\t]*)\t(.*)$")
    if not hash then return end
    SRT.Comm.Send("NACK", hash, "WHISPER", sender)
    local a = SRT.db.active
    if a and a.hash == hash and a.sender == sender then return end -- already have it
    activate(unescape(title), unescape(text), sender, hash)
end)

SRT.Comm.Register("NACK", function(sender, hash)
    local sent = SRT.db.lastSent
    if not sent or sent.hash ~= hash then return end
    sent.acks[SRT.Compat.NameKey(sender)] = true
    changed()
end)

-- A late joiner asks; the leader or assistant who sent the note answers with a whisper.
SRT.Comm.Register("NREQ", function(sender)
    local a, sent = SRT.db.active, SRT.db.lastSent
    if not a or not sent or sent.hash ~= a.hash or time() - sent.at > REQUEST_MAX_AGE then return end
    if not SRT.Compat.IsLeaderOrAssist() then return end
    SRT.Comm.Send("NOTE", payload(a), "WHISPER", sender)
end)

local wasGrouped
local function askForNote()
    if IsInGroup() then SRT.Comm.Send("NREQ", "") end
end
SRT:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local grouped = IsInGroup()
    if grouped and wasGrouped == false then C_Timer.After(3, askForNote) end
    wasGrouped = grouped
    changed()
end)
SRT:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
    wasGrouped = IsInGroup()
    if (isLogin or isReload) and wasGrouped then C_Timer.After(5, askForNote) end
end)

-- ---------------------------------------------------------------------------
-- Raid chat: the visible lines, one message each ({rt1} icons work in chat too).
-- ---------------------------------------------------------------------------

function Notes.PostToChat(text)
    local channel = SRT.Compat.GroupChatChannel()
    if not channel then SRT:Print("You are not in a group.") return end
    local lines = {}
    text = Notes.Visible(text or ""):gsub("{spell:%d+}", "")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = strtrim(line)
        if line ~= "" then lines[#lines + 1] = line:sub(1, 250) end
    end
    for i, line in ipairs(lines) do
        C_Timer.After((i - 1) * 0.3, function() SRT.Compat.SendChat(line, channel) end)
    end
end
