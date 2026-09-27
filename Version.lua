-- Version check: /srt version asks the group which SRT version everyone runs and
-- lists who is missing the addon. Any newer version seen is mentioned once.
local _, SRT = ...

local Version = {}
SRT.Version = Version

local WAIT = 3 -- seconds to collect replies

-- "0.10.2" > "0.9.7": compare number by number. Returns -1, 0 or 1.
function Version.Compare(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

local replies     -- [nameKey] = { name, version } while a check runs
local warnedNewer -- highest version already mentioned

local function noteVersion(sender, version)
    if replies then replies[SRT.Compat.NameKey(sender)] = { name = sender, version = version } end
    if Version.Compare(version, SRT.version) > 0 and (not warnedNewer or Version.Compare(version, warnedNewer) > 0) then
        warnedNewer = version
        SRT:Print(("%s runs a newer version (%s, you have %s). Update when you can."):format(sender, version, tostring(SRT.version)))
    end
end

SRT.Comm.Register("VQ", function(sender, payload, channel)
    noteVersion(sender, payload)
    SRT.Comm.Send("VR", SRT.version, channel)
end)

SRT.Comm.Register("VR", function(sender, payload)
    noteVersion(sender, payload)
end)

local function report()
    local members = SRT.Compat.GroupMembers()
    local byVersion, missing, offline = {}, {}, {}
    local own = SRT.Compat.NameKey(SRT.Compat.PlayerName())
    for _, m in ipairs(members) do
        local key = SRT.Compat.NameKey(m.name)
        local r = replies[key]
        if key == own then
            r = { version = SRT.version }
        end
        if r then
            byVersion[r.version] = byVersion[r.version] or {}
            tinsert(byVersion[r.version], m.name)
            replies[key] = nil
        elseif m.online then
            missing[#missing + 1] = m.name
        else
            offline[#offline + 1] = m.name
        end
    end
    -- Replies from names not found in the roster (name format surprises on Forever).
    for _, r in pairs(replies) do
        byVersion[r.version] = byVersion[r.version] or {}
        tinsert(byVersion[r.version], r.name .. "*")
    end
    replies = nil

    local versions = {}
    for v in pairs(byVersion) do versions[#versions + 1] = v end
    sort(versions, function(a, b) return Version.Compare(a, b) > 0 end)
    SRT:Print(("Version check (%d in group):"):format(#members))
    for _, v in ipairs(versions) do
        local names = byVersion[v]
        sort(names)
        SRT:Print(("  |cff3fc77f%s|r (%d): %s"):format(v, #names, table.concat(names, ", ")))
    end
    if #missing > 0 then
        sort(missing)
        SRT:Print(("  |cffe8483dno SRT|r (%d): %s"):format(#missing, table.concat(missing, ", ")))
    end
    if #offline > 0 then
        sort(offline)
        SRT:Print(("  |cff888888offline|r (%d): %s"):format(#offline, table.concat(offline, ", ")))
    end
end

function Version.Check()
    if replies then
        SRT:Print("A version check is already running.")
        return
    end
    local ok, err = SRT.Comm.Send("VQ", SRT.version)
    if not ok then
        SRT:Print("SlaughterRaidTools v" .. tostring(SRT.version) .. " (" .. err .. ", nobody to ask).")
        return
    end
    replies = {}
    SRT:Print("Asking the group...")
    C_Timer.After(WAIT, function() SRT:Call("version report", report) end)
end

SRT:AddSlashCommand("version", Version.Check, "show which SRT version everyone in the group runs")
