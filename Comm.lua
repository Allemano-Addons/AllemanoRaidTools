-- Comm: addon messages between ART users. Long payloads are split into parts, sending
-- is paced so the client never throttles us, and the parts are joined again on the
-- other side before the handler for that message kind runs.
--
-- Wire format (one addon message, max 255 bytes):
--   <proto>|<kind>|<id>|<part>|<parts>|<data>
-- kind = short upper-case name ("VQ", "NOTE"...), id = per-sender message number.
local _, ART = ...

local Comm = {}
ART.Comm = Comm

Comm.PREFIX = "ART"
Comm.PROTO = 1
local MAX_MSG = 255
local BURST = 8          -- messages we may send at once
local RATE = 1           -- messages per second after the burst
local PART_TIMEOUT = 60  -- seconds an incomplete message is kept
local THROTTLED = { [3] = true, [8] = true, [9] = true } -- AddonMessageThrottle, ChannelThrottle, GeneralError

local handlers = {}
local queue = {}
local tokens, lastRefill = BURST, 0
local ticker
local nextId = 0
local incoming = {} -- [sender#id] = { parts = {}, got = n, total = n, t = time }

local function debug(fmt, ...)
    if ART.db and ART.db.settings.debugComm then ART:Print("|cff888888" .. fmt:format(...) .. "|r") end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    Comm.prefixResult = C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
end

-- handler(sender, payload, channel) runs for every complete message of that kind.
function Comm.Register(kind, handler)
    handlers[kind] = handler
end

local function refill()
    local now = GetTime()
    tokens = min(BURST, tokens + (now - lastRefill) * RATE)
    lastRefill = now
end

-- Sends queued messages while tokens last; returns when throttled or empty.
local function pump()
    refill()
    while queue[1] and tokens >= 1 do
        local m = queue[1]
        local result = C_ChatInfo.SendAddonMessage(Comm.PREFIX, m.text, m.channel, m.target)
        if THROTTLED[result] then
            tokens = 0
            debug("throttled (%s), retrying", tostring(result))
            break
        end
        tremove(queue, 1)
        tokens = tokens - 1
        if result ~= nil and result ~= 0 and result ~= true then
            debug("send failed (%s) on %s", tostring(result), tostring(m.channel))
        end
    end
    if queue[1] and not ticker then
        ticker = C_Timer.NewTicker(0.25, function() ART:Call("Comm pump", pump) end)
    elseif not queue[1] and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Sends payload (a string) to channel (default: the current group). target is the
-- player name for "WHISPER". Returns the number of parts, or nil and a reason.
function Comm.Send(kind, payload, channel, target)
    channel = channel or ART.Compat.GroupChannel()
    if not channel then return nil, "not in a group" end
    payload = tostring(payload or "")
    nextId = nextId % 9999 + 1
    -- The header grows with the part numbers, so size parts for the worst case.
    local headerMax = #("%d|%s|%d|%d|%d|"):format(Comm.PROTO, kind, nextId, 9999, 9999)
    local size = MAX_MSG - headerMax
    local total = max(1, ceil(#payload / size))
    for i = 1, total do
        local data = payload:sub((i - 1) * size + 1, i * size)
        queue[#queue + 1] = {
            text = ("%d|%s|%d|%d|%d|%s"):format(Comm.PROTO, kind, nextId, i, total, data),
            channel = channel, target = target,
        }
    end
    debug("send %s #%d (%d bytes, %d part%s) on %s", kind, nextId, #payload, total, total == 1 and "" or "s", channel)
    pump()
    return total
end

function Comm.QueueSize() return #queue end

-- [nameKey] = GetTime() of the last ART message from that player: who runs ART.
Comm.seen = {}

function Comm.IsSelf(sender)
    return ART.Compat.NameKey(sender) == ART.Compat.NameKey(ART.Compat.PlayerName())
end

local function purge(now)
    for key, m in pairs(incoming) do
        if now - m.t > PART_TIMEOUT then incoming[key] = nil end
    end
end

local function dispatch(kind, sender, payload, channel)
    local fn = handlers[kind]
    if not fn then
        debug("no handler for %s from %s", kind, tostring(sender))
        return
    end
    ART:Call("Comm " .. kind, fn, sender, payload, channel)
end

-- Comm.rawListener(text, channel, sender, target) sees every message with our prefix
-- before parsing (used by /art probe).
ART:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender, target)
    if prefix ~= Comm.PREFIX then return end
    if Comm.rawListener then Comm.rawListener(text, channel, sender, target) end
    local proto, kind, id, part, total, data = text:match("^(%d+)|([%w_]+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not proto then
        debug("unreadable message from %s", tostring(sender))
        return
    end
    if tonumber(proto) ~= Comm.PROTO then
        debug("%s uses protocol %s (we use %d), ignored", tostring(sender), proto, Comm.PROTO)
        return
    end
    if Comm.IsSelf(sender) then return end
    Comm.seen[ART.Compat.NameKey(sender)] = GetTime()
    part, total = tonumber(part), tonumber(total)
    if total == 1 then
        debug("got %s from %s", kind, tostring(sender))
        dispatch(kind, sender, data, channel)
        return
    end
    local now = GetTime()
    purge(now)
    local key = sender .. "#" .. id
    local m = incoming[key]
    if not m then
        m = { parts = {}, got = 0, total = total, t = now }
        incoming[key] = m
    end
    if not m.parts[part] then
        m.parts[part] = data
        m.got = m.got + 1
    end
    if m.got < m.total then return end
    incoming[key] = nil
    local payload = table.concat(m.parts, "", 1, m.total)
    debug("got %s from %s (%d bytes, %d parts)", kind, tostring(sender), #payload, m.total)
    dispatch(kind, sender, payload, channel)
end)

-- ---------------------------------------------------------------------------
-- Test tools: /art comm test <bytes> sends a long message the others check.
-- ---------------------------------------------------------------------------

local function checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum * 31 + s:byte(i)) % 65521 end
    return sum
end
Comm.Checksum = checksum

Comm.Register("ECHO", function(sender, payload)
    local len, sum, body = payload:match("^(%d+):(%d+):(.*)$")
    local ok = body and #body == tonumber(len) and checksum(body) == tonumber(sum)
    ART:Print(("Test message from %s: %d bytes, %s"):format(sender, body and #body or 0,
        ok and "|cff3fc77fintact|r" or "|cffe8483dbroken|r"))
end)

ART:AddSlashCommand("comm", function(arg)
    local sub, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    sub = strlower(sub or "")
    if sub == "test" then
        local n = min(20000, max(1, tonumber(rest) or 1000))
        local chars = {}
        for i = 1, n do chars[i] = string.char(97 + (i * 7) % 26) end
        local body = table.concat(chars)
        local parts, err = Comm.Send("ECHO", ("%d:%d:%s"):format(n, checksum(body), body))
        if parts then
            ART:Print(("Sending %d bytes in %d parts to the group."):format(n, parts))
        else
            ART:Print("Cannot send: " .. err)
        end
    elseif sub == "debug" then
        ART.db.settings.debugComm = not ART.db.settings.debugComm
        ART:Print("Addon message debug " .. (ART.db.settings.debugComm and "on" or "off") .. ".")
    else
        ART:Print("/art comm test <bytes> - send a test message the group checks")
        ART:Print("/art comm debug - print every addon message")
    end
end, "addon message tests (test, debug)")
