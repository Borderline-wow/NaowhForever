-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Note.lua -- the Custom Reminders tab and the MRT note
--  format behind it.
--
--  A note line is the wire format raid leaders already share:
--      {time:MM:SS[,pN]} - <reminder>  <reminder>
--  where each reminder is load conditionals ({everyone}, class:MAGE, role:HEALER,
--  spec:PALADIN:1, group:3, or a player name) followed by {text}...{/text} or
--  {spell:12345}, and reminders on one line are separated by TWO spaces. p1 is the
--  pull itself; pN for N >= 2 is boss phase N, anchored on the boss mods' stage
--  reports. Parsed lines become ordinary raid reminder entries tagged fromNote, so
--  every existing fire/target/display path runs them; Apply replaces only
--  note-born entries and never touches hand-authored ones.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

local NOTE_LEAD = 5   -- fire this early with a matching display dur, so the text counts
                      -- down TO the noted moment rather than starting at it

-------------------------------------------------------------------------------
--  Parsing
-------------------------------------------------------------------------------
local ROLE_WORDS = {
    TANK = "TANK", TANKS = "TANK", T = "TANK",
    HEALER = "HEALER", HEALERS = "HEALER", HEAL = "HEALER", H = "HEALER",
    DAMAGER = "DAMAGER", DPS = "DAMAGER", DAMAGE = "DAMAGER", D = "DAMAGER",
}

local function StripCosmetics(line)
    line = line:gsub("||?c%x%x%x%x%x%x%x%x", ""):gsub("||?r", "")
    line = line:gsub("{[Ss][Tt][Aa][Rr]}", ""):gsub("{[Cc][Ii][Rr][Cc][Ll][Ee]}", "")
    line = line:gsub("{[Dd][Ii][Aa][Mm][Oo][Nn][Dd]}", ""):gsub("{[Tt][Rr][Ii][Aa][Nn][Gg][Ll][Ee]}", "")
    line = line:gsub("{[Mm][Oo][Oo][Nn]}", ""):gsub("{[Ss][Qq][Uu][Aa][Rr][Ee]}", "")
    line = line:gsub("{[Cc][Rr][Oo][Ss][Ss]}", ""):gsub("{[Ss][Kk][Uu][Ll][Ll]}", "")
    line = line:gsub("{[Rr][Tt][1-8]}", "")
    return line
end

-- -> seconds, stage|nil, restOfLine  |  nil, warnReason (no tag = nil, nil)
local function ParseTimeTag(line)
    local mm, ss, opts, rest = line:match("^%s*{time:(%d+):([%d%.]+)(.-)}(.*)$")
    if not mm then return nil end
    local t = (tonumber(mm) or 0) * 60 + (tonumber(ss) or 0)
    local stage
    if opts ~= "" then
        local p = opts:match("^,p(%d+)$")
        if not p then return nil, "unsupported time options '" .. opts .. "'" end
        local n = tonumber(p)
        if n and n >= 2 then stage = n end   -- p1 is the pull
    end
    return t, stage, rest
end

-- Everything after the time tag: an optional "AbilityName - " prefix, then reminders
-- separated by two spaces. The trailing two spaces are appended defensively -- notes
-- written by hand usually forget them on the last reminder.
local function SplitChunks(rest)
    local after = rest:match("^%s*.-%s%-%s(.+)$") or rest
    after = after .. "  "
    local chunks = {}
    for chunk in after:gmatch("(.-)  ") do
        chunk = chunk:match("^%s*(.-)%s*$")
        if chunk ~= "" then chunks[#chunks + 1] = chunk end
    end
    return chunks
end

local function ClassIndexToSpecID(classToken, idx)
    for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
        local _, token = GetClassInfo(classID)
        if token == classToken then
            local specID = GetSpecializationInfoForClassID
                and GetSpecializationInfoForClassID(classID, idx)
            if specID then return specID end
            return nil, "no spec " .. idx .. " for " .. classToken
        end
    end
    return nil, "unknown class " .. tostring(classToken)
end

-- One reminder chunk -> proto { target, displayType, text, spellID } | nil, warn.
-- Conditionals accumulate into one target table (a superset of MRT's one-per-reminder,
-- harmless since the target matcher already ANDs categories).
local function ParseChunk(chunk)
    local target = {}
    local warn

    while true do
        chunk = chunk:match("^%s*(.-)%s*$")
        if chunk:match("^{[Ee][Vv][Ee][Rr][Yy][Oo][Nn][Ee]}") then
            target.all = true
            chunk = chunk:gsub("^{[Ee][Vv][Ee][Rr][Yy][Oo][Nn][Ee]}", "", 1)
        elseif chunk:match("^[Cc][Ll][Aa][Ss][Ss]:%a+") then
            local tok = chunk:match("^[Cc][Ll][Aa][Ss][Ss]:(%a+)")
            target.classes = target.classes or {}
            target.classes[tok:upper()] = true
            chunk = chunk:gsub("^[Cc][Ll][Aa][Ss][Ss]:%a+", "", 1)
        elseif chunk:match("^[Rr][Oo][Ll][Ee]:%a+") then
            local word = chunk:match("^[Rr][Oo][Ll][Ee]:(%a+)")
            local role = ROLE_WORDS[word:upper()]
            if not role then return nil, "unknown role '" .. word .. "'" end
            target.roles = target.roles or {}
            target.roles[role] = true
            chunk = chunk:gsub("^[Rr][Oo][Ll][Ee]:%a+", "", 1)
        elseif chunk:match("^[Gg][Rr][Oo][Uu][Pp]:%d+") then
            local n = tonumber(chunk:match("^[Gg][Rr][Oo][Uu][Pp]:(%d+)"))
            if not n or n < 1 or n > 8 then return nil, "group must be 1-8" end
            target.subgroups = target.subgroups or {}
            target.subgroups[n] = true
            chunk = chunk:gsub("^[Gg][Rr][Oo][Uu][Pp]:%d+", "", 1)
        elseif chunk:match("^[Ss][Pp][Ee][Cc]:%a+:%d+") then
            local tok, idx = chunk:match("^[Ss][Pp][Ee][Cc]:(%a+):(%d+)")
            local specID, err = ClassIndexToSpecID(tok:upper(), tonumber(idx))
            if not specID then return nil, err end
            target.specs = target.specs or {}
            target.specs[specID] = true
            chunk = chunk:gsub("^[Ss][Pp][Ee][Cc]:%a+:%d+", "", 1)
        elseif chunk:match("^[Tt][Yy][Pp][Ee]:%a+") then
            return nil, "position targeting (type:) is not supported"
        elseif chunk:match("^{[Tt][Ee][Xx][Tt]}") or chunk:match("^{[Ss][Pp][Ee][Ll][Ll]:") then
            break
        elseif chunk == "" then
            return nil, "no {text} or {spell:} display"
        else
            local word = chunk:match("^([^%s{@]+)")
            if not word then return nil, "could not read '" .. chunk:sub(1, 20) .. "'" end
            if word:find(":") then
                return nil, "unknown conditional '" .. word .. "'"
            end
            local name = word:match("^([^%-]+)") or word   -- strip -Realm
            target.names = target.names or {}
            target.names[name] = true
            chunk = chunk:sub(#word + 1)
        end
    end

    local proto
    local text = chunk:match("^{[Tt][Ee][Xx][Tt]}(.-){/[Tt][Ee][Xx][Tt]}")
    if text and text ~= "" then
        proto = { displayType = "text", text = text }
        chunk = chunk:gsub("^{[Tt][Ee][Xx][Tt]}.-{/[Tt][Ee][Xx][Tt]}", "", 1)
    else
        local sid = tonumber(chunk:match("^{[Ss][Pp][Ee][Ll][Ll]:(%d+)}"))
        if not sid then return nil, "no readable {text} or {spell:} display" end
        proto = { displayType = "icon", spellID = sid }
        chunk = chunk:gsub("^{[Ss][Pp][Ee][Ll][Ll]:%d+}", "", 1)
    end

    if chunk:match("@") then
        warn = "glow targets (@) are not supported yet and were ignored"
    end

    if not next(target) then target.all = true end
    proto.target = target
    return proto, warn
end

-- -> protos, warnings   |   nil, { hardError }
function ns.ParseMRTNote(text)
    if type(text) ~= "string" or text:match("^%s*$") then return {}, {} end
    if text:match("{[Ee]:%d+}") then
        return nil, { "this is a multi-boss note ({e:} sections) -- paste one boss's "
            .. "section, the boxes here are per boss" }
    end
    local protos, warnings = {}, {}
    local lineNo = 0
    for line in text:gmatch("[^\r\n]+") do
        lineNo = lineNo + 1
        line = StripCosmetics(line)
        local t, stage, rest = ParseTimeTag(line)
        if t == nil and stage ~= nil then
            warnings[#warnings + 1] = ("line %d: %s"):format(lineNo, stage)
        elseif t ~= nil then
            for _, chunk in ipairs(SplitChunks(rest)) do
                local proto, warn = ParseChunk(chunk)
                if warn then
                    warnings[#warnings + 1] = ("line %d: %s"):format(lineNo, warn)
                end
                if proto then
                    proto.t, proto.stage = t, stage
                    protos[#protos + 1] = proto
                end
            end
        end
        -- lines with no {time:} tag are prose; notes are full of it
    end
    return protos, warnings
end

function ns.ApplyNoteToBoss(encounterID, text)
    local protos, warnings = ns.ParseMRTNote(text)
    if not protos then return nil, warnings end

    local set = ns.RaidRemindersTable(true, encounterID)
    for uid, r in pairs(set) do
        if r.fromNote then set[uid] = nil end
    end

    local stamp = math.floor(GetTime() * 1000)
    for i, p in ipairs(protos) do
        local trig
        if p.stage then
            trig = { type = "stage", stage = p.stage, delay = p.t, leadTime = NOTE_LEAD }
        else
            trig = { type = "pull", delay = p.t, leadTime = NOTE_LEAD }
        end
        local name
        if p.displayType == "icon" then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(p.spellID)
            name = (info and info.name) or ("Spell " .. p.spellID)
        else
            name = p.text
            if #name > 40 then name = name:sub(1, 37) .. "..." end
        end
        set["nt" .. stamp .. i] = {
            name = name, enabled = true, fromNote = true,
            trigger = trig, target = p.target,
            display = (p.displayType == "icon")
                and { type = "icon", spellID = p.spellID, dur = NOTE_LEAD }
                or { type = "text", text = p.text, dur = NOTE_LEAD },
        }
    end

    local db = ns.DB()
    if type(db.bossNotes) ~= "table" then db.bossNotes = {} end
    db.bossNotes[tostring(encounterID)] = text
    ns.RefreshRuntime()
    return #protos, warnings
end

-------------------------------------------------------------------------------
--  Encoding
-------------------------------------------------------------------------------
-- One conditional per reminder is all the wire format can say; a target using several
-- categories encodes its highest-priority one and the caller is warned.
local function EncodeTarget(target)
    target = target or {}
    if target.all then return "{everyone}" end
    local cats = 0
    for _, k in ipairs({ "names", "classes", "roles", "subgroups", "specs" }) do
        if type(target[k]) == "table" and next(target[k]) then cats = cats + 1 end
    end
    local function firstKey(t)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        return keys[1], #keys
    end
    local warn = (cats > 1) and "targeting simplified on export" or nil
    if type(target.names) == "table" and next(target.names) then
        local name, n = firstKey(target.names)
        if n > 1 then warn = "targeting simplified on export" end
        return name, warn
    elseif type(target.classes) == "table" and next(target.classes) then
        local tok, n = firstKey(target.classes)
        if n > 1 then warn = "targeting simplified on export" end
        return "class:" .. tok, warn
    elseif type(target.roles) == "table" and next(target.roles) then
        local role, n = firstKey(target.roles)
        if n > 1 then warn = "targeting simplified on export" end
        return "role:" .. role, warn
    elseif type(target.subgroups) == "table" and next(target.subgroups) then
        local g, n = firstKey(target.subgroups)
        if n > 1 then warn = "targeting simplified on export" end
        return "group:" .. g, warn
    elseif type(target.specs) == "table" and next(target.specs) then
        local specID, n = firstKey(target.specs)
        if n > 1 then warn = "targeting simplified on export" end
        for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
            local _, token = GetClassInfo(classID)
            if token then
                for idx = 1, 4 do
                    if GetSpecializationInfoForClassID
                        and GetSpecializationInfoForClassID(classID, idx) == specID then
                        return ("spec:%s:%d"):format(token, idx), warn
                    end
                end
            end
        end
        return nil, "spec id " .. tostring(specID) .. " could not be encoded"
    end
    return "{everyone}", warn
end

local function FormatTimeTag(t, stage)
    local mm = math.floor(t / 60)
    local ss = t - mm * 60
    local tag
    if ss == math.floor(ss) then
        tag = ("{time:%d:%02d"):format(mm, ss)
    else
        tag = ("{time:%d:%04.1f"):format(mm, ss)
    end
    if stage then tag = tag .. ",p" .. stage end
    return tag .. "}"
end

-- Note-born entries only: the canonical, normalized form of what Apply understood.
function ns.EncodeMRTNote(encounterID)
    local set = ns.RaidRemindersTable(false, encounterID)
    local warnings = {}
    if not set then return "", warnings end

    local groups, order = {}, {}
    for _, r in pairs(set) do
        if r.fromNote and r.trigger then
            local cond, warn = EncodeTarget(r.target)
            if warn then warnings[#warnings + 1] = (r.name or "?") .. ": " .. warn end
            local part
            if cond then
                local d = r.display or {}
                if d.type == "icon" and d.spellID then
                    part = cond .. " {spell:" .. d.spellID .. "}"
                elseif d.text and d.text ~= "" then
                    part = cond .. " {text}" .. d.text .. "{/text}"
                else
                    warnings[#warnings + 1] = (r.name or "?") .. ": no encodable display"
                end
            end
            if part then
                local key = (r.trigger.stage or 0) .. ":" .. (r.trigger.delay or 0)
                if not groups[key] then
                    groups[key] = { t = r.trigger.delay or 0, stage = r.trigger.stage,
                        parts = {} }
                    order[#order + 1] = key
                end
                local parts = groups[key].parts
                parts[#parts + 1] = part
            end
        end
    end

    table.sort(order, function(a, b)
        local ga, gb = groups[a], groups[b]
        local sa, sb = ga.stage or 0, gb.stage or 0
        if sa ~= sb then return sa < sb end
        return ga.t < gb.t
    end)

    local lines = {}
    for _, key in ipairs(order) do
        local g = groups[key]
        table.sort(g.parts)
        lines[#lines + 1] = FormatTimeTag(g.t, g.stage) .. " - "
            .. table.concat(g.parts, "  ") .. "  "
    end
    return table.concat(lines, "\n"), warnings
end

-------------------------------------------------------------------------------
--  The tab page
-------------------------------------------------------------------------------
local selInstIdx = 1
local selBossIdx = {}   -- keyed by instance id

function ns.BuildCustomRemindersPage(parent, yOffset)
    local EUI = ns.UI
    local W = EUI.Widgets
    if EUI.ClearContentHeader then EUI:ClearContentHeader() end
    local y = yOffset or -6
    local PADX = EUI.CONTENT_PAD or 45

    local pageHead = ns.Font(parent, 14, nil, ns.THEME.accent)
    pageHead:SetPoint("TOP", parent, "TOP", 0, y)
    pageHead:SetText("CUSTOM REMINDERS")
    y = y - 24

    local hint = ns.Font(parent, 11, nil, ns.THEME.muted)
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", PADX, y)
    hint:SetPoint("RIGHT", parent, "RIGHT", -PADX, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("Reminders for the selected boss, plus an MRT-style note. Apply Note "
        .. "replaces only note-born entries (tagged [note]); hand-made ones are never "
        .. "touched. Phase lines ({time:...,p2}) need BigWigs or DBM and only fire on "
        .. "bosses whose module announces phases.")
    y = y - 44

    local data = ns.ScrapeBosses and ns.ScrapeBosses()
    if not (data and data.instances and #data.instances > 0) then
        local wait = ns.Font(parent, 12, nil, ns.THEME.muted)
        wait:SetPoint("TOPLEFT", parent, "TOPLEFT", PADX, y)
        wait:SetText("The Dungeon Journal has not answered yet -- reopen this tab in a moment.")
        return y - 24
    end

    -- All journal instances, plus one synthetic bucket for encounters that only exist in
    -- saved data (an old season's boss with reminders still stored).
    local instList = {}
    for i = 1, #data.instances do instList[#instList + 1] = data.instances[i] end
    do
        local known = {}
        for _, inst in ipairs(instList) do
            for _, b in ipairs(inst.bosses) do known[tostring(b.encounterID)] = true end
        end
        local db = ns.DB()
        local extras = {}
        for _, field in ipairs({ "raidReminders", "customReminders", "bossNotes" }) do
            if type(db[field]) == "table" then
                for encStr in pairs(db[field]) do
                    if not known[encStr] and tonumber(encStr) and tonumber(encStr) > 0 then
                        extras[encStr] = true
                    end
                end
            end
        end
        local extraBosses = {}
        for encStr in pairs(extras) do
            extraBosses[#extraBosses + 1] =
                { name = "Encounter " .. encStr, encounterID = tonumber(encStr) }
        end
        table.sort(extraBosses, function(a, b) return a.encounterID < b.encounterID end)
        if #extraBosses > 0 then
            instList[#instList + 1] =
                { id = "savedOnly", name = "Saved (not in journal)", bosses = extraBosses }
        end
    end

    if selInstIdx > #instList then selInstIdx = 1 end
    local inst = instList[selInstIdx]
    local bIdx = selBossIdx[inst.id] or 1
    if bIdx > #inst.bosses then bIdx = 1 end
    local boss = inst.bosses[bIdx]

    local instValues, instOrder = {}, {}
    for i = 1, #instList do instValues[i] = instList[i].name; instOrder[i] = i end
    local bossValues, bossOrder = {}, {}
    for i = 1, #inst.bosses do bossValues[i] = inst.bosses[i].name; bossOrder[i] = i end

    local _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Instance", width = 220,
          values = instValues, order = instOrder,
          getValue = function() return selInstIdx end,
          setValue = function(v)
              selInstIdx = v
              EUI:RefreshPage(true)
          end },
        { type = "dropdown", text = "Boss", width = 220,
          values = bossValues, order = bossOrder,
          getValue = function() return bIdx end,
          setValue = function(v)
              selBossIdx[inst.id] = v
              EUI:RefreshPage(true)
          end }
    ); y = y - h - 6

    if not boss then return y end
    local encID = boss.encounterID
    local isRaid = inst.isRaid or false

    -- The same sections the boss cog shows, rendered inline.
    local listBox = CreateFrame("Frame", nil, parent)
    listBox:SetPoint("TOPLEFT", parent, "TOPLEFT", PADX, y)
    listBox:SetPoint("RIGHT", parent, "RIGHT", -PADX, 0)
    local okSec, usedY = pcall(ns.BuildBossReminderSections, listBox, encID, isRaid, 0,
        { EUI = EUI, onChanged = function() EUI:RefreshPage(true) end })
    if not okSec then
        local errText = ns.Font(listBox, 11, nil, { r = 1, g = 0.35, b = 0.35 })
        errText:SetPoint("TOPLEFT", listBox, "TOPLEFT", 0, 0)
        errText:SetText("Failed to build the reminder lists: " .. tostring(usedY))
        usedY = -24
    end
    listBox:SetHeight(math.abs(usedY) + 4)
    y = y + usedY - 10

    _, h = W:SectionHeader(parent, "MRT NOTE", y); y = y - h

    local noteBox = CreateFrame("Frame", nil, parent)
    noteBox:SetPoint("TOPLEFT", parent, "TOPLEFT", PADX - 14, y)
    noteBox:SetPoint("RIGHT", parent, "RIGHT", -(PADX - 14), 0)
    noteBox:SetHeight(200)
    local box = ns.MakeMultilineBox(noteBox, 0, 200)
    y = y - 208

    local feedback = ns.Font(parent, 11, nil, ns.THEME.muted)
    feedback:SetPoint("TOPLEFT", parent, "TOPLEFT", PADX, y)
    feedback:SetPoint("RIGHT", parent, "RIGHT", -PADX, 0)
    feedback:SetJustifyH("LEFT")
    feedback:SetWordWrap(true)
    y = y - 56

    local applyBtn, exportBtn, clearBtn
    local lastParse

    local function Revalidate()
        local text = box:GetText() or ""
        local protos, warnings = ns.ParseMRTNote(text)
        lastParse = protos
        if not protos then
            feedback:SetTextColor(1, 0.38, 0.38, 1)
            feedback:SetText(warnings[1] or "could not read the note")
        elseif #protos == 0 then
            feedback:SetTextColor(ns.THEME.muted.r, ns.THEME.muted.g, ns.THEME.muted.b, 1)
            feedback:SetText(text:match("^%s*$") and "Paste or type note lines above."
                or "No reminder lines found ({time:MM:SS} - {everyone} {text}...{/text}).")
        else
            local hasStage = false
            for i = 1, #protos do
                if protos[i].stage then hasStage = true break end
            end
            local msg = ("%d reminder%s ready."):format(#protos, #protos == 1 and "" or "s")
            if hasStage then
                msg = msg .. " Includes phase lines (they need BigWigs or DBM)."
            end
            for i = 1, math.min(#warnings, 3) do
                msg = msg .. "\n" .. warnings[i]
            end
            if #warnings > 3 then
                msg = msg .. ("\n(+%d more warnings)"):format(#warnings - 3)
            end
            feedback:SetTextColor(ns.THEME.muted.r, ns.THEME.muted.g, ns.THEME.muted.b, 1)
            feedback:SetText(msg)
        end
        local can = lastParse and #lastParse > 0
        if applyBtn then
            applyBtn:SetAlpha(can and 1 or 0.35)
            applyBtn:EnableMouse(can and true or false)
        end
    end
    box:SetScript("OnTextChanged", Revalidate)

    applyBtn = ns.Button(parent, "Apply Note", 110, 24, function()
        local count, warnings = ns.ApplyNoteToBoss(encID, box:GetText() or "")
        if count then
            ns.Print(("note applied: %d reminder(s) for %s."):format(count, boss.name))
        else
            ns.Print("|cffff6060" .. ((warnings and warnings[1]) or "the note could not be applied") .. "|r")
        end
        EUI:RefreshPage(true)
    end)
    applyBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", PADX, y)
    ns.Tooltip(applyBtn, "Apply Note",
        "Parses the note and replaces this boss's note-born reminders with it. The note "
        .. "text is saved with your profile.")

    exportBtn = ns.Button(parent, "Export From Saved", 140, 24, function()
        local text, warnings = ns.EncodeMRTNote(encID)
        box:SetText(text or "")
        if warnings and warnings[1] then
            ns.Print(warnings[1] .. (warnings[2] and (" (+" .. (#warnings - 1) .. " more)") or ""))
        end
    end)
    exportBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    ns.Tooltip(exportBtn, "Export From Saved",
        "Regenerates note lines from this boss's note-born reminders, in canonical form, "
        .. "ready to copy and share.")

    clearBtn = ns.Button(parent, "Clear Note", 100, 24, function()
        local dimmer, panel = ns.MakeModal(340, 130, "noteClearConfirm")
        local head = ns.Font(panel, 14, "OUTLINE")
        head:SetPoint("TOP", panel, "TOP", 0, -16)
        head:SetText("Clear the note for " .. (boss.name or "?") .. "?")
        local sub = ns.Font(panel, 11, nil, ns.THEME.muted)
        sub:SetPoint("TOP", head, "BOTTOM", 0, -8)
        sub:SetText("Removes its note-born reminders too. Cannot be undone.")
        local yes = ns.Button(panel, "Clear", 100, 24, function()
            local set = ns.RaidRemindersTable(false, encID)
            if set then
                for uid, r in pairs(set) do
                    if r.fromNote then set[uid] = nil end
                end
            end
            local db = ns.DB()
            if type(db.bossNotes) == "table" then db.bossNotes[tostring(encID)] = nil end
            ns.RefreshRuntime()
            dimmer:Hide()
            EUI:RefreshPage(true)
        end)
        yes:SetPoint("BOTTOM", panel, "BOTTOM", -56, 14)
        local no = ns.Button(panel, "Cancel", 100, 24, function() dimmer:Hide() end)
        no:SetPoint("BOTTOM", panel, "BOTTOM", 56, 14)
        dimmer:Show()
    end)
    clearBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    y = y - 34

    -- Preload AFTER the handlers exist so the feedback line reflects it immediately.
    local db = ns.DB()
    local saved = type(db.bossNotes) == "table" and db.bossNotes[tostring(encID)]
    if saved and saved ~= "" then
        box:SetText(saved)
    else
        local encoded = ns.EncodeMRTNote(encID)
        if encoded ~= "" then box:SetText(encoded) end
    end
    Revalidate()

    return y
end
