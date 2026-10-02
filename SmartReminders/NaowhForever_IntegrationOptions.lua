local ns = _G.NaowhForever
local I, UI = ns.Integrations, ns.UI
local debuffSelection = {}
-- Debuff editor shows the raw Instance ID field instead of the dungeon list. Not saved.
local debuffByID = false

-- Sized to the options window so the page never scrolls; only the ability list does.
local PANEL_H, BODY_H = 424, 336
-- A font's size is fixed when it is made, so it is part of the UI.Keep key.
local function Label(parent, text, x, y, width, size, color)
    local label = UI.KeepFont(parent, "label" .. (size or 12), size or 12, nil, color or ns.THEME.muted)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end
local function NewPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    ns.Solid(p, "BACKGROUND", ns.THEME.panel, 1):SetAllPoints()
    ns.Border(p)
    return p
end
local function Panel(parent, title, x, y, width, height)
    local p = UI.Keep(parent, "panel", NewPanel)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    p:SetSize(width, height)
    Label(p, title, 14, -12, width - 28, 14, ns.THEME.accent)
    return p
end
local function NewBox(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetFontObject(GameFontHighlight)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)
    ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    ns.Border(box)
    -- Without an inset the caret and the first character sit on the border itself.
    box:SetTextInsets(7, 7, 0, 0)
    return box
end
local function Box(parent, title, value, y, width)
    local label = Label(parent, title, 14, y, width)
    local box = UI.Keep(parent, "box", NewBox)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y - 20)
    box:SetSize(width, 24)
    box:SetText(tostring(value or ""))
    return box, label
end
local function Dropdown(parent, title, values, order, get, set, y, width)
    Label(parent, title, 14, y, width)
    local dd = UI.KeepDropdown(parent, "dd" .. width, width, values, order, get, set)
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y - 20)
    return dd
end
local function Toggle(parent, title, get, set, y, width)
    Label(parent, title, 14, y - 4, width - 54)
    local toggle = UI.KeepToggle(parent, "toggle", get, set)
    toggle:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, y)
end

-- Picking a row rebuilds the page onto a new scroll frame, which jumped the list to the
-- top. Clamped by hand: the new frame's range is not recomputed until it next draws, and
-- SetVerticalScroll past it lands at the top.
local listScroll = {}
local function KeepListScroll(scroll, key, contentHeight)
    scroll._scrollKey = key
    if not scroll._scrollHooked then
        scroll._scrollHooked = true
        scroll:HookScript("OnVerticalScroll", function(self, offset) listScroll[self._scrollKey] = offset end)
    end
    local want = listScroll[key]
    if not want or want <= 0 then return end
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(want, math.max(0, contentHeight - scroll:GetHeight())))
end
local function Editor(parent, uid)
    local editedRules, editedSpec = I.Rules(true), I.Spec()
    local AutoSave
    -- Commit on focus loss: saving mid-typing a spell id would save a different spell.
    local function Commit(box)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEditFocusLost", function() AutoSave() end)
        return box
    end
    local old = uid and editedRules[uid]
    local t, d = old and old.trigger or {}, old and old.display or {}
    local spellID = t.spellID
    local mapID = t.mapID or 0
    local mapChoice = mapID
    Label(parent, old and old.name or "New Debuff Sound", 0, 0, 420, 16, ns.THEME.fg)
    Label(parent, "Rules belong to the current profile and specialization.", 0, -20, 420)
    -- Two columns, no tabs: the tabs discarded unsaved edits and outlived their rule.
    -- The debuff column is ~332 of BODY_H; past 336 the page's own scrollbar comes back.
    local COL_W = 296
    local cast = Panel(parent, "Debuff Settings", 0, -66, COL_W, BODY_H)
    local test = Panel(parent, "Sound", COL_W + 12, -66, COL_W, BODY_H)
    local voice = test
    local healer = old and old.healerReminder == true
    local enabled = not old or old.enabled ~= false
    Toggle(cast, "Enabled", function() return enabled end,
        function(v) enabled = v; AutoSave() end, -42, 268)
    Toggle(cast, "Healer Reminder", function() return healer end,
        function(v) healer = v; AutoSave() end, -78, 268)
    local name = Commit(Box(test, "Reminder name", old and old.name or "Debuff alert", -44, 268))
    local map
    local auraEvent, target = t.auraEvent or "Added", t.target or "player"
    local spell = Commit(Box(cast, "Debuff spell ID", spellID, -120, 268))
    -- No "everywhere" choice in the list, but mapID 0 still means everywhere to the engine;
    -- old alerts show as "Instance 0" and it can be typed into the id field.
    local mapValues = { [mapChoice] = "Instance " .. tostring(mapChoice),
        other = "Another instance (by ID)" }
    local mapOrder = { mapChoice, "other" }
    -- The id field adds a fifth row, so the rows tighten instead of the panel growing.
    -- 42, not 48: at 48 the fifth row ran 20px past the border over the status line.
    local gap = debuffByID and 42 or 56
    local yMap = -120 - gap
    Dropdown(cast, "Dungeon", mapValues, mapOrder,
        function() return debuffByID and "other" or mapChoice end,
        function(v)
            local wasByID = debuffByID
            if v == "other" then
                debuffByID = true
            else
                -- Value() prefers the box until the rebuild, so drop it or the old id saves.
                debuffByID, mapChoice, map = false, v, nil
                AutoSave()
            end
            -- A rebuild on every pick threw away typing in an alert not yet valid to save.
            if wasByID ~= debuffByID then UI:RefreshPage(true) end
        end, yMap, 268)
    local yWhen = yMap - gap
    if debuffByID then
        map = Commit(Box(cast, "Instance ID (0 = every dungeon or raid)",
            mapChoice, yWhen, 268))
        yWhen = yWhen - gap
    end
    Dropdown(cast, "When", { Added = "Applied", ApplicationsIncreased = "Stack increased", Removed = "Removed" },
        { "Added", "ApplicationsIncreased", "Removed" }, function() return auraEvent end,
        function(v) auraEvent = v; AutoSave() end, yWhen, 268)
    Dropdown(cast, "Unit", { player = "Me", party = "Party members" }, { "player", "party" },
        function() return target end, function(v) target = v; AutoSave() end, yWhen - gap, 268)
    Label(test, "Use the debuff's aura spell ID. The Stoneform and Shadowmeld voices require Unit: Me and stay silent while that racial is on cooldown, unknown or unusable.\n\nChanges apply after combat and encounter restrictions end. Test previews the voice regardless of cooldown.", 14, -200, 268)
    local sound = d.sound or "none"
    local paths, names, order = UI.BuildAlertSoundTables()
    UI.AppendSharedMediaSounds(paths, names, order)
    -- Rules and packs store the key, never the label, so only the labels may be renamed.
    names["voice:stoneform-ready"] = "Stoneform - Naowh"
    order[#order + 1] = "voice:stoneform-ready"
    names["voice:shadowmeld-ready"] = "Shadowmeld - Naowh"
    order[#order + 1] = "voice:shadowmeld-ready"
    Dropdown(voice, "Sound", names, order, function() return sound end,
        function(v) sound = v; AutoSave() end, -100, 268)
    local status = Label(parent, "Changes save as you make them. Test previews your current choices.", 0, -66 - BODY_H - 10, 604)
    local function Value()
        local id, instanceID = spellID, mapID
        if spell then id = tonumber(spell:GetText()) end
        if map then instanceID = tonumber(map:GetText())
        elseif mapChoice then instanceID = mapChoice end
        return { name = name:GetText(), enabled = enabled, healerReminder = healer or nil,
            trigger = { type = "auraSound", spellID = id, mapID = instanceID,
                auraEvent = auraEvent, target = target },
            -- text is no longer edited; blank asks the preset for its line, old rules keep theirs.
            display = { type = d.type or "icon",
                text = d.text or "", sound = sound,
                spellID = d.spellID or id, dur = 3,
                -- Unused since cast repeat went; carried through so saving does not strip them.
                castRepeat = d.castRepeat,
                castAudio = d.castAudio,
                tts = false } }
    end
    -- An invalid rule is not saved; the last good version stays.
    AutoSave = function()
        if I.Spec() ~= editedSpec or I.Rules(false) ~= editedRules then
            status:SetText("Profile or specialization changed. Select the reminder again.")
            return
        end
        local value = Value()
        if not I.ValidRule(value) then
            status:SetText("|cffF0A830Not saved:|r check IDs, timing and sound. "
                .. "A racial voice requires Unit: Me.")
            return
        end
        local ok, result = I.Save(uid, value)
        if not ok then status:SetText(result); return end
        status:SetText("Saved.")
        -- Rebuild only on create; later edits stay in place so typing keeps focus.
        if not uid then
            uid = result
            debuffSelection, debuffByID = { uid = uid }, false
            UI:RefreshPage(true)
        end
    end

    local preview = UI.KeepButton(parent, "test", "Test", 120, 28, function()
        local r = Value()
        if I.ValidRule(r) then
            I.Preview(r)
            status:SetText("Sound preview requested.")
        else status:SetText("Check IDs and sound. A racial voice requires Unit: Me.") end
    end)
    -- Top right: a button row under the body would overrun the window's edge.
    preview:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -40)
    if uid then
        local remove = UI.KeepButton(parent, "remove", "Remove", 120, 28, function()
            if I.Spec() ~= editedSpec or I.Rules(false) ~= editedRules then return end
            editedRules[uid] = nil
            debuffSelection, debuffByID = {}, false
            I.Refresh(); UI:RefreshPage(true)
        end)
        remove:SetPoint("RIGHT", preview, "LEFT", -8, 0)
    end
end
function ns.ShowCopyTrashRulesPopup(callerEUI, kind)
    local EUI = callerEUI or ns.UI
    local noun = kind == "auraSound" and "debuff alerts" or "trash rules"
    local specs = I.SpecsWithRules(kind)
    -- Provisional: resized to the measured content once the wrapped hint is laid out.
    local dimmer, panel = ns.MakeModal(430, 150 + math.max(1, #specs) * 30, "copyTrashRules")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(kind == "auraSound" and "Copy Debuff Alerts From" or "Copy Trash Rules From")

    local y = -46
    if #specs == 0 then
        local none = UI.KeepFont(panel, "none", 12, nil, ns.THEME.muted)
        none:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
        none:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
        none:SetJustifyH("LEFT")
        none:SetWordWrap(true)
        none:SetText(("No other spec has any %s saved yet."):format(noun))
    else
        local hint = UI.KeepFont(panel, "hint", 11, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
        hint:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        hint:SetText("Anything this spec already has is left alone. A rule calls out one of "
            .. "your own spells, so copying from another class brings rules for spells this "
            .. "spec cannot cast.")
        hint:SetHeight(math.max(16, hint:GetStringHeight() + 4))
        y = y - hint:GetHeight() - 12

        for i = 1, #specs do
            local s = specs[i]
            local btn = UI.KeepButton(panel, "spec", s.name, 210, 24, function()
                local copied, skipped = I.CopyRulesFromSpec(s.key, kind)
                ns.Print(("copied " .. ns.Color("accent", "%d") .. " %s from %s%s."):format(
                    copied, noun, s.name,
                    skipped > 0 and (", left " .. skipped .. " already here alone") or ""))
                dimmer:Hide()
                if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
            end)
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
            local count = UI.KeepFont(panel, "count", 11, nil, ns.THEME.muted)
            count:SetPoint("LEFT", btn, "RIGHT", 10, 0)
            count:SetText(("%d saved"):format(s.total))
            y = y - 30
        end
    end

    panel:SetHeight(math.max(150, -y + 58))
    UI.KeepButton(panel, "cancel", "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)
    dimmer:Show()
end

local ROW_H, ICON = 26, 20

-- Switching on a row with nothing saved creates the rule, like the boss ability rows.
local function NewListRow(list)
    local row = ns.Button(list, "", 10, ROW_H)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 64, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.toggle = UI.BuildToggleControl(row, row:GetFrameLevel() + 2,
        function() return row.on end, function(v) row.onToggle(v) end, 26, 13)
    row.toggle:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.holder = CreateFrame("Frame", nil, row)
    row.holder:SetSize(ICON, ICON)
    row.holder:SetPoint("LEFT", row, "LEFT", 38, 0)
    row.tex = row.holder:CreateTexture(nil, "ARTWORK")
    row.tex:SetAllPoints()
    row.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(row.holder, { r = 0, g = 0, b = 0 }, 1)
    row.activeBorder = ns.Border(row, ns.THEME.accent)
    return row
end

local function ListRow(list, ly, width, text, icon, rule, active, onClick, onCreate, indent)
    local row = UI.Keep(list, "row", NewListRow)
    row:SetSize(width, ROW_H)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", indent or 0, -ly)
    ns.SetButtonText(row, text)
    row._onClick = onClick

    row.on = rule ~= nil and rule.enabled ~= false
    row.onToggle = function(v)
        row.on = v and true or false
        if rule then
            rule.enabled = row.on
            I.Refresh()
        elseif row.on and onCreate then
            onCreate()
        end
    end
    row.toggle._refreshValue()

    row.holder:SetShown(icon ~= nil)
    row.tex:SetTexture(icon)
    row.activeBorder._frame:SetShown(active == true)
    return row
end

-- Folded groups by instance id. Outlives the page rebuild a header click causes; not saved.
local debuffCollapsed = {}

local function NewGroupHeader(list)
    local row = ns.Button(list, "", 10, ROW_H)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetTextColor(ns.THEME.accent.r, ns.THEME.accent.g, ns.THEME.accent.b, 1)
    return row
end

local function GroupHeader(list, ly, width, name, count, collapsed, onClick)
    local row = UI.Keep(list, "group", NewGroupHeader)
    row:SetSize(width, ROW_H)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -ly)
    ns.SetButtonText(row, ("%s  %s  (%d)"):format(collapsed and "+" or "-", name, count))
    row._onClick = onClick
    return row
end

local function StatusLines(parent, y)
    local function AuraStatus()
        return (I.auraStatus or "") .. (I.racialStatus and ("  " .. I.racialStatus) or "")
    end
    local auraStatus = Label(parent, AuraStatus(), 20, y - 26, 900)
    -- No IsVisible() guard: nothing re-runs this on show, so a hidden page came back stale.
    I.OnStatusChanged = function() auraStatus:SetText(AuraStatus()) end
end

function ns.BuildDebuffsPage(parent, y)
    I.Refresh()
    Label(parent, "Debuff Alerts", 20, y - 4, 900, 16, ns.THEME.accent)

    local others = I.SpecsWithRules and I.SpecsWithRules("auraSound") or {}
    if #others > 0 then
        local copy = UI.KeepButton(parent, "copy", "Copy From Spec", 160, 24, function()
            ns.ShowCopyTrashRulesPopup(UI, "auraSound")
        end)
        copy:SetPoint("TOPLEFT", parent, "TOPLEFT", 160, y)
        ns.Tooltip(copy, "Copy From Spec",
            "Brings another spec's debuff alerts over to this one. They are saved per spec, "
            .. "and anything already here is left alone.")
    end
    StatusLines(parent, y)

    local side = Panel(parent, "Saved Debuff Alerts", 20, y - 68, 280, PANEL_H)
    local add = UI.KeepButton(side, "add", "+ Debuff Alert", 252, 26, function()
        debuffSelection, debuffByID = { newAura = true }, false; UI:RefreshPage(true)
    end)
    add:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -42)

    local scroll = UI.Keep(side, "scroll", function(p)
        local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        sf.list = CreateFrame("Frame", nil, sf)
        sf.list:SetWidth(240)
        sf:SetScrollChild(sf.list)
        return sf
    end)
    scroll:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -78)
    scroll:SetSize(240, PANEL_H - 90)
    local list = scroll.list
    UI.BeginReusableRows(list)

    local rules = I.Rules(false) or {}
    local rows = {}
    for uid, r in pairs(rules) do
        if r.trigger.type == "auraSound" then rows[#rows + 1] = { uid = uid, rule = r } end
    end
    table.sort(rows, function(a, b) return a.uid < b.uid end)

    local groups, byMap = {}, {}
    for _, entry in ipairs(rows) do
        local mapID = entry.rule.trigger.mapID or 0
        local group = byMap[mapID]
        if not group then
            group = { mapID = mapID, entries = {},
                name = mapID == 0 and "Every dungeon or raid" or ("Instance " .. tostring(mapID)) }
            byMap[mapID] = group
            groups[#groups + 1] = group
        end
        group.entries[#group.entries + 1] = entry
    end
    table.sort(groups, function(a, b)
        if (a.mapID == 0) ~= (b.mapID == 0) then return b.mapID == 0 end
        return a.name < b.name
    end)

    local chosen, ly = nil, 0
    for _, group in ipairs(groups) do
        local key = tostring(group.mapID)
        local collapsed = debuffCollapsed[key] == true
        GroupHeader(list, ly, 236, group.name, #group.entries, collapsed, function()
            debuffCollapsed[key] = (not collapsed) or nil
            UI:RefreshPage(true)
        end)
        ly = ly + ROW_H + 1
        for _, entry in ipairs(group.entries) do
            local rule = entry.rule
            local active = not debuffSelection.newAura and entry.uid == debuffSelection.uid
            -- Found even when folded: folding must not blank the editor.
            if active then chosen = entry end
            if not collapsed then
                local icon = C_Spell and C_Spell.GetSpellTexture
                    and C_Spell.GetSpellTexture(rule.trigger.spellID)
                local row = ListRow(list, ly, 224, rule.name or "Debuff alert", icon, rule,
                    active,
                    function()
                        debuffSelection, debuffByID = { uid = entry.uid }, false
                        UI:RefreshPage(true)
                    end,
                    nil, 12)
                ns.Tooltip(row, rule.name or "Debuff alert",
                    ("Aura %s on %s, when %s."):format(tostring(rule.trigger.spellID),
                        rule.trigger.target == "party" and "a party member" or "you",
                        (rule.trigger.auraEvent or "Added"):lower()))
                ly = ly + ROW_H + 1
            end
        end
    end
    if #rows == 0 then
        Label(list, "None yet. Add one with the button above.", 4, 0, 230)
        ly = 40
    end
    list:SetHeight(math.max(1, ly))
    KeepListScroll(scroll, "debuff", math.max(1, ly))

    local right = UI.Keep(parent, "right", function(p) return CreateFrame("Frame", nil, p) end)
    right:SetPoint("TOPLEFT", parent, "TOPLEFT", 320, y - 68)
    right:SetSize(604, PANEL_H)
    if debuffSelection.newAura then Editor(right, nil)
    elseif chosen then Editor(right, chosen.uid)
    else
        Label(right, "A debuff sound plays when an aura is applied, stacks or falls off.", 0, 0, 604, 14)
        Label(right, "Use the debuff's own aura spell ID. These apply wherever you set them, not to one dungeon. Changes save as you make them.", 0, -40, 604)
    end
    return y - (68 + PANEL_H + 8)
end