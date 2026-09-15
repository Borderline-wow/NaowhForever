local ns = _G.NaowhUITankReminder
local I, UI = ns.Integrations, ns.UI
local selection = { dungeon = "saved" }
local function Label(parent, text, x, y, width, size, color)
    local label = ns.Font(parent, size or 12, nil, color or ns.THEME.muted)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end
local function Panel(parent, title, x, y, width, height)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    p:SetSize(width, height)
    ns.Solid(p, "BACKGROUND", ns.THEME.panel, 1):SetAllPoints()
    ns.Border(p)
    Label(p, title, 14, -12, width - 28, 14, ns.THEME.accent)
    return p
end
local function Box(parent, title, value, y, width)
    Label(parent, title, 14, y, width)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetFontObject(GameFontHighlight)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y - 20)
    box:SetSize(width, 24)
    ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    ns.Border(box)
    box:SetText(tostring(value or ""))
    return box
end
local function Dropdown(parent, title, values, order, get, set, y, width)
    Label(parent, title, 14, y, width)
    local dd = UI.BuildDropdownControl(parent, width, parent:GetFrameLevel() + 2, values, order, get, set)
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y - 20)
    return dd
end
local function Toggle(parent, title, get, set, y, width)
    Label(parent, title, 14, y - 4, width - 54)
    local toggle = UI.BuildToggleControl(parent, parent:GetFrameLevel() + 2, get, set)
    toggle:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, y)
end
local function Editor(parent, uid, kind, ability, dungeon)
    local editedRules, editedSpec = I.Rules(true), I.Spec()
    local old = uid and editedRules[uid]
    kind = old and old.trigger.type or kind
    local t, d = old and old.trigger or {}, old and old.display or {}
    local spellID = t.spellID or (ability and ability.spellID)
    local mapID = t.mapID or (dungeon and dungeon.id) or 0
    Label(parent, old and old.name or (ability and ability.name) or "New Debuff Sound",
        0, 0, 590, 18, ns.THEME.fg)
    Label(parent, ability and (ability.mob .. "  |  Spell " .. spellID)
        or "Rules belong to the current profile and specialization.", 0, -28, 590)
    local cast = Panel(parent, kind == "exboss" and "Cast Settings" or "Debuff Settings", 0, -60, 296, 352)
    local test = Panel(parent, "Text & Test Settings", 308, -60, 296, 352)
    local voice = Panel(parent, "Voice Settings", 0, -424, 604, 164)
    local enabled, healer = not old or old.enabled ~= false, old and old.healerReminder == true
    Toggle(cast, "Enabled", function() return enabled end, function(v) enabled = v end, -42, 268)
    Toggle(cast, "Healer Reminder", function() return healer end, function(v) healer = v end, -78, 268)
    local name = Box(test, "Reminder name", old and old.name or (ability and ability.name) or "Debuff sound", -44, 268)
    local duration
    local lead, spell, map, text
    local auraEvent, target = t.auraEvent or "Added", t.target or "player"
    if kind == "exboss" then
        duration = Box(test, "Display duration (1-15 seconds)", d.dur or 3, -100, 268)
        lead = Box(cast, "Warn before readiness (0-30 seconds)", t.timeleft or 5, -124, 268)
        Label(cast, "Timing predicts ability readiness. It does not confirm a cast or its target.", 14, -184, 268)
        text = Box(test, "Callout text", d.text or "Use a defensive", -156, 268)
    else
        spell = Box(cast, "Debuff spell ID", spellID, -120, 268)
        map = Box(cast, "Instance ID (0 = every dungeon / raid)", mapID, -176, 268)
        Dropdown(cast, "When", { Added = "Applied", ApplicationsIncreased = "Stack increased", Removed = "Removed" },
            { "Added", "ApplicationsIncreased", "Removed" }, function() return auraEvent end,
            function(v) auraEvent = v end, -232, 268)
        Dropdown(cast, "Unit", { player = "Me", party = "Party members" }, { "player", "party" },
            function() return target end, function(v) target = v end, -288, 268)
        Label(test, "Use the debuff's aura spell ID. Stoneform voice requires Unit: Me and stays silent while the racial is unavailable.\n\nChanges apply after combat and encounter restrictions end. Test previews the voice regardless of cooldown.", 14, -160, 268)
    end
    local preset = old and old.preset or "none"
    if kind == "exboss" then
        local values, order = { none = "Custom text" }, { "none" }
        for _, p in ipairs(ns.ListPresets(I.Spec())) do
            values[p.key] = p.name; order[#order + 1] = p.key
        end
        if preset ~= "none" and not values[preset] then
            values[preset] = "Missing preset: " .. preset; order[#order + 1] = preset
        end
        Dropdown(cast, "Defensive preset", values, order, function() return preset end,
            function(v) preset = v end, -242, 268)
    end
    local sound, tts = d.sound or "none", d.tts == true
    local paths, names, order = UI.BuildAlertSoundTables()
    UI.AppendSharedMediaSounds(paths, names, order)
    if kind == "auraSound" then
        names["voice:stoneform-ready"] = "Stoneform - only when ready (English)"
        order[#order + 1] = "voice:stoneform-ready"
    end
    Dropdown(voice, "Sound", names, order, function() return sound end,
        function(v) sound = v end, -44, 268)
    if kind == "exboss" then
        Toggle(voice, "Speak callout", function() return tts end, function(v) tts = v end, -112, 576)
    end
    local status = Label(parent, "Select settings, then Save. Test previews your current choices.", 0, -604, 604)
    local function Value()
        local id, instanceID = spellID, mapID
        if spell then id = tonumber(spell:GetText()) end
        if map then instanceID = tonumber(map:GetText()) end
        return { name = name:GetText(), enabled = enabled, healerReminder = healer or nil,
            preset = kind == "exboss" and preset ~= "none" and preset or nil,
            trigger = { type = kind, spellID = id, mapID = instanceID,
                timeleft = lead and tonumber(lead:GetText()) or nil, auraEvent = auraEvent, target = target },
            display = { type = d.type or "icon", text = text and text:GetText() or "", sound = sound,
                spellID = d.spellID or id, dur = kind == "exboss" and tonumber(duration:GetText()) or 3,
                tts = kind == "exboss" and tts or false } }
    end
    local preview = ns.Button(test, "Test Reminder", 268, 28, function()
        local r = Value()
        if I.ValidRule(r) then
            I.Preview(r)
            if kind == "exboss" and not r.display.tts and r.display.sound == "none" then
                status:SetText("Visual test only. Enable Speak Callout or select a Sound for audio.")
            elseif kind == "exboss" and r.display.tts then
                status:SetText("TTS uses Voice and Voice Volume in Setup. Check chat for any playback errors.")
            else
                status:SetText("Sound preview requested. Save to keep these settings.")
            end
        else status:SetText("Check IDs and sound. Stoneform voice requires Unit: Me.") end
    end)
    preview:SetPoint("BOTTOMLEFT", test, "BOTTOMLEFT", 14, 16)
    local save = ns.Button(parent, "Save", 120, 28, function()
        if I.Spec() ~= editedSpec or I.Rules(false) ~= editedRules then
            status:SetText("Profile or specialization changed. Select the reminder again."); return
        end
        local ok, result = I.Save(uid, Value())
        if not ok then status:SetText(result); return end
        selection.uid = result or uid
        if kind == "auraSound" then selection.dungeon = "saved" end
        selection.newAura = nil
        UI:RefreshPage(true)
    end)
    save:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -646)
    if uid then
        local remove = ns.Button(parent, "Remove", 120, 28, function()
            if I.Spec() ~= editedSpec or I.Rules(false) ~= editedRules then return end
            editedRules[uid] = nil; selection.uid = nil; selection.spellID = nil
            I.Refresh(); UI:RefreshPage(true)
        end)
        remove:SetPoint("LEFT", save, "RIGHT", 12, 0)
    end
end
function ns.BuildIntegrationsPage(parent, y)
    I.Refresh()
    Label(parent, "Trash & Debuff Alerts", 20, y - 6, 900, 16, ns.THEME.accent)
    local status = Label(parent, I.trashStatus or "", 20, y - 34, 900)
    local function AuraStatus()
        return (I.auraStatus or "") .. (I.stoneformStatus and ("  " .. I.stoneformStatus) or "")
    end
    local auraStatus = Label(parent, AuraStatus(), 20, y - 56, 900)
    I.OnStatusChanged = function()
        status:SetText(I.trashStatus or ""); auraStatus:SetText(AuraStatus())
    end
    local catalogue, values, order, selected = I.Catalogue(), { saved = "Saved reminders" }, { "saved" }
    for _, dungeon in ipairs(catalogue) do
        values[dungeon.id] = dungeon.name; order[#order + 1] = dungeon.id
        if dungeon.id == selection.dungeon then selected = dungeon end
    end
    if not values[selection.dungeon] then selection.dungeon = "saved" end
    local side = Panel(parent, "Select a Dungeon", 20, y - 90, 280, 684)
    Dropdown(side, "Dungeon", values, order, function() return selection.dungeon end, function(v)
        selection = { dungeon = v }; UI:RefreshPage(true)
    end, -42, 252)
    local add = ns.Button(side, "+ Debuff Sound", 252, 26, function()
        selection.uid = nil; selection.spellID = nil; selection.newAura = true; UI:RefreshPage(true)
    end)
    add:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -104)
    Label(side, selected and "Select an Ability" or "Saved Reminders", 14, -148, 252, 14, ns.THEME.fg)
    local scroll = CreateFrame("ScrollFrame", nil, side, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -178)
    scroll:SetSize(240, 486)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetWidth(240); scroll:SetScrollChild(list)
    local rules, rows = I.Rules(false) or {}, {}
    if selected then
        for _, ability in ipairs(selected.abilities) do
            rows[#rows + 1] = { ability = ability }
            -- Existing duplicate rules stay separately editable under Saved reminders.
            local ids = {}
            for uid, r in pairs(rules) do
                if r.trigger.type == "exboss" and r.trigger.mapID == selected.id
                    and r.trigger.spellID == ability.spellID then ids[#ids + 1] = uid end
            end
            table.sort(ids); rows[#rows].uid = ids[1]
        end
    else
        for uid, r in pairs(rules) do rows[#rows + 1] = { uid = uid, name = r.name } end
        table.sort(rows, function(a, b) return a.uid < b.uid end)
    end
    local chosen
    for index, row in ipairs(rows) do
        local ability = row.ability
        local active = not selection.newAura and ((ability and ability.spellID == selection.spellID)
            or (selection.uid and row.uid == selection.uid))
        if active then chosen = row end
        local label = (row.uid and "[Saved] " or "") .. (ability and ability.name or row.name)
        local button = ns.Button(list, label, 236, 44, function()
            selection.uid = row.uid; selection.spellID = ability and ability.spellID
            selection.newAura = nil; UI:RefreshPage(true)
        end)
        button:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * 50)
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", ability and 42 or 8, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        button.label:SetJustifyH("LEFT")
        button.label:SetWordWrap(false)
        if ability and ability.icon then
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("LEFT", button, "LEFT", 6, 0)
            icon:SetSize(30, 30); icon:SetTexture(ability.icon)
        end
        ns.Tooltip(button, label, ability and (ability.mob .. "\nSpell " .. ability.spellID) or "Edit this saved reminder.")
        if active then ns.Border(button, ns.THEME.accent) end
    end
    list:SetHeight(math.max(1, #rows * 50))
    local right = CreateFrame("Frame", nil, parent)
    right:SetPoint("TOPLEFT", parent, "TOPLEFT", 320, y - 90)
    right:SetSize(604, 684)
    if selection.newAura then Editor(right, nil, "auraSound", nil, selected)
    elseif chosen then Editor(right, chosen.uid, "exboss", chosen.ability, selected)
    else
        Label(right, "Choose a dungeon, then select an ability to set up its callout.", 0, 0, 604, 14)
        Label(right, #catalogue == 0 and "The trash ability catalogue is unavailable. Enable the trash timer engine and its data addon, then reopen this page. Existing rules are still available under Saved reminders."
            or "Saved reminders keeps your existing rules, including debuff sounds and rules that apply to every dungeon. Changes are saved only when you click Save.", 0, -40, 604)
    end
    return y - 800
end
