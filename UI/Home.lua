-- Home: one card per tool with tonight's summary. Cards fill in as the tools are built;
-- until then they say what they will show.
local _, SRT = ...

local W = SRT.Widgets
local Main = SRT.Main

local PAD, GAP = 26, 16

Main.RegisterPage("home", function(page)
    local function go(id) return function() Main.Show(id) end end

    local readiness = W.Card(page, "Raid readiness", "Open raid check", go("raidcheck"))
    readiness:SetPoint("TOPLEFT", PAD, -24)
    readiness:SetPoint("RIGHT", page, "CENTER", -GAP / 2, 0)
    readiness:SetHeight(190)
    readiness.body:SetText("Flasks, food, buffs and durability for everyone, straight from the ready check, "
        .. "with who is missing what.\n\n|cff7c858fArrives with Raid check.|r")

    local note = W.Card(page, "Note", "Edit note", go("notes"))
    note:SetPoint("TOPLEFT", page, "TOP", GAP / 2, -24)
    note:SetPoint("RIGHT", -PAD, 0)
    note:SetHeight(190)
    note.body:SetText("The note you sent tonight, how many have it and who is missing it (with or without SRT).\n\n"
        .. "|cff7c858fArrives with Notes.|r")

    local pulls = W.Card(page, "Pulls tonight", "Pull log", go("pulllog"))
    pulls:SetPoint("TOPLEFT", readiness, "BOTTOMLEFT", 0, -GAP)
    pulls:SetPoint("TOPRIGHT", readiness, "BOTTOMRIGHT", 0, -GAP)
    pulls:SetHeight(160)
    pulls.body:SetText("Every boss pull with its duration and wipe or kill.\n\n|cff7c858fArrives with Pull log.|r")

    local attendance = W.Card(page, "Attendance", "Export", go("attendance"))
    attendance:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -GAP)
    attendance:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -GAP)
    attendance:SetHeight(160)
    attendance.body:SetText("In raid, bench and late arrivals, with an export.\n\n|cff7c858fArrives with Attendance.|r")

    local cds = W.Card(page, "Cooldowns & battle res", nil, nil, true)
    cds:SetPoint("TOPLEFT", pulls, "BOTTOMLEFT", 0, -GAP)
    cds:SetPoint("RIGHT", -PAD, 0)
    cds:SetHeight(76)
    cds.body:ClearAllPoints()
    cds.body:SetPoint("TOPLEFT", 18, -40)
    cds.body:SetPoint("RIGHT", -150, 0)
    cds.body:SetTextColor(SRT.Theme:Color("text"))
    local probeBtn = W.Button(cds, "Run probe", nil, function()
        SRT.Probe.ArmCombat()
        Main.Refresh()
    end)
    probeBtn:SetPoint("RIGHT", -18, 0)

    return function()
        local state = SRT.Probe.CombatState()
        if state == "armed" then
            cds.body:SetText("Combat probe is armed: fight something in a dungeon, then /reload and send the SavedVariables file.")
        elseif state == "done" then
            cds.body:SetText("Combat probe recorded. /reload and send the SavedVariables file to see what Forever allows.")
        else
            cds.body:SetText("Waiting for probe results. Run the probe, then fight something in a dungeon.")
        end
        probeBtn:SetDisabled(state == "armed" and "The probe is already waiting for combat." or nil)
    end
end)
