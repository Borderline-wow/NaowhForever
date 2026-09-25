local ns = _G.NaowhForever
local I, UI = ns.Integrations, ns.UI
local debuffSelection = {}
-- Whether the debuff editor is showing the raw Instance ID field instead of the dungeon
-- list. Page state, not saved: it is how you are editing right now, not part of the rule.
local debuffByID = false

-- The page is sized to the options window so it never scrolls: the ability list keeps its
-- own scrollbar and nothing else needs one. The editor fits by putting its three groups of
-- settings behind tabs rather than stacking them, the same shape the boss reminder editor
-- already uses. PANEL_H is what is left once the heading block is drawn.
local PANEL_H, BODY_H = 424, 336
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
    local label = Label(parent, title, 14, y, width)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetFontObject(GameFontHighlight)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y - 20)
    box:SetSize(width, 24)
    ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    ns.Border(box)
    -- Without an inset the caret and the first character sit on the border itself.
    box:SetTextInsets(7, 7, 0, 0)
    box:SetText(tostring(value or ""))
    return box, label
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

-- Picking a row IS a refresh, and a refresh rebuilds the page from scratch onto a brand
-- new scroll frame, so these lists jumped back to the top whenever you chose or switched
-- on a rule near the bottom of one. The offset outlives the frame here and goes back on
-- once the rows are in, which is the first moment there is a range to clamp it against.
--
-- Clamped by hand rather than left to SetVerticalScroll: the frame's own range is not
-- recomputed until it next draws, and an offset past it would land at the top -- which is
-- the very thing being fixed.
local listScroll = {}
local function KeepListScroll(scroll, key, contentHeight)
    scroll:HookScript("OnVerticalScroll", function(_, offset) listScroll[key] = offset end)
    local want = listScroll[key]
    if not want or want <= 0 then return end
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(want, math.max(0, contentHeight - scroll:GetHeight())))
end
local function Editor(parent, uid)
    local editedRules, editedSpec = I.Rules(true), I.Spec()
    -- Every control writes straight through, so there is no Save button to forget. Declared
    -- up here because the controls are built before Value() exists to read them; the
    -- closures capture this local and see it once it is assigned below.
    local AutoSave
    -- Text boxes commit when you leave them rather than on every keystroke: saving halfway
    -- through typing a spell id would be saving a different spell.
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
    -- Two columns, no tabs. Once the custom text field went, neither half was big enough to
    -- be worth hiding behind a click, and the tabs were where the last two bugs came from:
    -- switching one discarded unsaved edits, and the chosen tab outlived the rule it was
    -- chosen on. Nothing to switch, neither bug.
    --
    -- The debuff column is the tall one at roughly 332 against BODY_H. A field added to it
    -- will need the panel to grow, and growing it past 336 brings the page's own scrollbar
    -- back, so measure before adding one.
    local COL_W = 296
    local cast = Panel(parent, "Debuff Settings", 0, -66, COL_W, BODY_H)
    local test = Panel(parent, "Sound", COL_W + 12, -66, COL_W, BODY_H)
    -- One panel now holds what the Voice tab used to; kept as its own name so the controls
    -- below read the same either way.
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
    -- There is no "every dungeon or raid" choice: a debuff alert names the instance it
    -- belongs to. Zero still MEANS everywhere to the engine and an alert saved with it
    -- keeps firing everywhere -- it shows as "Instance 0" until rescoped, and can be
    -- typed back in through the id field by anyone who wants it.
    local mapValues = { [mapChoice] = "Instance " .. tostring(mapChoice),
        other = "Another instance (by ID)" }
    local mapOrder = { mapChoice, "other" }
    -- The id field costs a row, and four rows at the usual spacing already fill this
    -- column against BODY_H. Everything below tightens while it is showing rather than
    -- the panel growing, which would bring the page's own scrollbar back.
    --
    -- 42, not 48: a row is a 20px label over a 24px box, so the last of five sits at
    -- -120 - 4 * gap and ends 44 below that. At 48 it finished 20px past the panel's
    -- own border and over the status line underneath. 42 puts the fifth row's bottom
    -- exactly where the fourth sat before, which is the fit this column was built to.
    local gap = debuffByID and 42 or 56
    local yMap = -120 - gap
    Dropdown(cast, "Dungeon", mapValues, mapOrder,
        function() return debuffByID and "other" or mapChoice end,
        function(v)
            local wasByID = debuffByID
            if v == "other" then
                debuffByID = true
            else
                -- map is dropped with it: Value() prefers the box whenever one exists,
                -- and it still does until the rebuild, so leaving it would save the id
                -- last typed there instead of the dungeon just picked.
                debuffByID, mapChoice, map = false, v, nil
                AutoSave()
            end
            -- Only when the id field comes or goes. The dropdown repaints its own
            -- label, so an ordinary pick needs no rebuild, and rebuilding anyway threw
            -- away whatever was typed into an alert too incomplete to have saved yet.
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
    -- Named for whose voice it is, matching Naowh's other sound files. The keys are left
    -- alone: a saved rule and a shared pack both store the key, never the label, so
    -- renaming one of these can never orphan a rule somebody already made.
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
        -- The box wins while it is the control on screen; otherwise the list's pick does.
        if map then instanceID = tonumber(map:GetText())
        elseif mapChoice then instanceID = mapChoice end
        return { name = name:GetText(), enabled = enabled, healerReminder = healer or nil,
            trigger = { type = "auraSound", spellID = id, mapID = instanceID,
                auraEvent = auraEvent, target = target },
            -- No longer edited anywhere. A preset writes the spoken and shown line itself,
            -- and a blank line is what asks for one; only a rule saved while this page still
            -- had a text box carries any, and it keeps it.
            display = { type = d.type or "icon",
                text = d.text or "", sound = sound,
                spellID = d.spellID or id, dur = 3,
                -- Carried through untouched rather than dropped. Nothing writes or reads
                -- them any more, but a rule or a shared pack saved while the cast repeat
                -- existed still has them, and rewriting a rule should not quietly strip
                -- fields a future version might mean something by.
                castRepeat = d.castRepeat,
                castAudio = d.castAudio,
                tts = false } }
    end
    -- Refuses rather than writing a half-finished rule: a spell id mid-typing is a valid
    -- number for a spell nobody meant, and I.Save would happily store it. The last good
    -- version stays saved until this one is worth saving.
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
        -- A rule that did not exist a moment ago now does, so the list has to show it and
        -- the editor has to gain its Remove button. Every later edit updates in place and
        -- leaves the page alone, or typing would fight a rebuild for the keyboard.
        if not uid then
            uid = result
            debuffSelection, debuffByID = { uid = uid }, false
            UI:RefreshPage(true)
        end
    end

    local preview = ns.Button(parent, "Test", 120, 28, function()
        local r = Value()
        if I.ValidRule(r) then
            I.Preview(r)
            status:SetText("Sound preview requested.")
        else status:SetText("Check IDs and sound. A racial voice requires Unit: Me.") end
    end)
    -- Top right, on the tab row: the editor is a fixed height now and a button row under
    -- the body would put it back over the window's own edge. Both act on the whole rule
    -- rather than one group of its settings, so they stay reachable from every tab.
    preview:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -40)
    if uid then
        local remove = ns.Button(parent, "Remove", 120, 28, function()
            if I.Spec() ~= editedSpec or I.Rules(false) ~= editedRules then return end
            editedRules[uid] = nil
            debuffSelection, debuffByID = {}, false
            I.Refresh(); UI:RefreshPage(true)
        end)
        remove:SetPoint("RIGHT", preview, "LEFT", -8, 0)
    end
end
-- Trash rules are saved per spec, so a second spec starts with nothing and rebuilding a
-- dungeon's worth of them by hand is the same ask the boss pages answer with their own Copy
-- From Spec. Deliberately plain next to that one: there is no boss to scope to and no
-- every-boss choice to offer, so the panel is the spec list and nothing else.
function ns.ShowCopyTrashRulesPopup(callerEUI, kind)
    local EUI = callerEUI or ns.UI
    local noun = kind == "auraSound" and "debuff alerts" or "trash rules"
    local specs = I.SpecsWithRules(kind)
    -- Provisional: the hint below wraps to a line count no arithmetic here can know, so the
    -- panel is resized to whatever the content measured once it is laid out.
    local dimmer, panel = ns.MakeModal(430, 150 + math.max(1, #specs) * 30, "copyTrashRules")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(kind == "auraSound" and "Copy Debuff Alerts From" or "Copy Trash Rules From")

    local y = -46
    if #specs == 0 then
        local none = ns.Font(panel, 12, nil, ns.THEME.muted)
        none:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
        none:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
        none:SetJustifyH("LEFT")
        none:SetWordWrap(true)
        none:SetText(("No other spec has any %s saved yet."):format(noun))
    else
        local hint = ns.Font(panel, 11, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
        hint:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        -- The class warning is the one thing worth saying up front: a rule names a spell YOU
        -- cast, so taking one from another class lands rules for spells this spec does not
        -- have. Said rather than prevented -- the same curator who wants it knows why.
        hint:SetText("Anything this spec already has is left alone. A rule calls out one of "
            .. "your own spells, so copying from another class brings rules for spells this "
            .. "spec cannot cast.")
        hint:SetHeight(math.max(16, hint:GetStringHeight() + 4))
        y = y - hint:GetHeight() - 12

        for i = 1, #specs do
            local s = specs[i]
            local btn = ns.Button(panel, s.name, 210, 24, function()
                local copied, skipped = I.CopyRulesFromSpec(s.key, kind)
                ns.Print(("copied |cff0091ed%d|r %s from %s%s."):format(
                    copied, noun, s.name,
                    skipped > 0 and (", left " .. skipped .. " already here alone") or ""))
                dimmer:Hide()
                if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
            end)
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
            local count = ns.Font(panel, 11, nil, ns.THEME.muted)
            count:SetPoint("LEFT", btn, "RIGHT", 10, 0)
            count:SetText(("%d saved"):format(s.total))
            y = y - 30
        end
    end

    -- Cancel anchors to the panel's own bottom, so fitting the panel to the content moves
    -- it with them rather than leaving it floating under a short list.
    panel:SetHeight(math.max(150, -y + 58))
    ns.Button(panel, "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)
    dimmer:Show()
end

-- Shared by both list pages: a row that is the spell icon, the name, and a switch when
-- there is a saved rule behind it to switch. Deliberately tight -- the whole list used to
-- be two scrollbars deep on a dungeon with a dozen abilities.
local ROW_H, ICON = 26, 20

-- Every row carries a switch, reading off until a reminder exists behind it, so the list
-- says at a glance what is set up. Turning one on for an ability with nothing saved writes
-- the rule the editor would have written and opens it, which is the same "create on demand"
-- the boss ability rows already do rather than a second Add button.
local function ListRow(list, ly, width, text, icon, rule, active, onClick, onCreate, indent)
    local row = ns.Button(list, text, width, ROW_H, onClick)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", indent or 0, -ly)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 64, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    local on = rule ~= nil and rule.enabled ~= false
    local toggle = UI.BuildToggleControl(row, row:GetFrameLevel() + 2,
        function() return on end,
        function(v)
            on = v and true or false
            if rule then
                rule.enabled = on
                I.Refresh()
            elseif on and onCreate then
                onCreate()
            end
        end, 26, 13)
    toggle:SetPoint("LEFT", row, "LEFT", 6, 0)

    if icon then
        local holder = CreateFrame("Frame", nil, row)
        holder:SetSize(ICON, ICON)
        holder:SetPoint("LEFT", row, "LEFT", 38, 0)
        local tex = holder:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ns.Border(holder, { r = 0, g = 0, b = 0 }, 1)
    end
    if active then ns.Border(row, ns.THEME.accent) end
    return row
end

-- Which dungeon groups are folded shut, keyed by instance id. Outside the page for the
-- same reason the scroll offset is: clicking a header rebuilds the page and the state has
-- to outlive that. Not saved to the profile, since which group you last had open is not a
-- setting and reopening the window somewhere unexpected is worse than starting open.
local debuffCollapsed = {}

-- Plus and minus rather than a drawn chevron: it is the tree idiom the game itself uses,
-- and it costs no geometry to get right at two sizes.
local function GroupHeader(list, ly, width, name, count, collapsed, onClick)
    local row = ns.Button(list, ("%s  %s  (%d)"):format(collapsed and "+" or "-", name, count),
        width, ROW_H, onClick)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -ly)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetTextColor(ns.THEME.accent.r, ns.THEME.accent.g, ns.THEME.accent.b, 1)
    return row
end

local function StatusLines(parent, y)
    local function AuraStatus()
        return (I.auraStatus or "") .. (I.racialStatus and ("  " .. I.racialStatus) or "")
    end
    local auraStatus = Label(parent, AuraStatus(), 20, y - 26, 900)
    -- Deliberately unguarded. An IsVisible() test here looked free and was not: nothing
    -- re-runs this when the page is shown again, so a hidden page came back carrying
    -- whatever it had when it was hidden. The cost this would have saved is two SetText
    -- calls, and the event storm that made them add up is already stopped upstream by
    -- UpdateRacial's unchanged-reason early return.
    I.OnStatusChanged = function() auraStatus:SetText(AuraStatus()) end
end

-- Debuff alerts answer to an aura, not to a dungeon, so they get their own page rather than
-- a bucket at the bottom of the trash list where they had no dungeon to be filed under.
function ns.BuildDebuffsPage(parent, y)
    I.Refresh()
    Label(parent, "Debuff Alerts", 20, y - 4, 900, 16, ns.THEME.accent)

    -- Its own copy, of its own kind: these answer to an aura rather than a dungeon, and the
    -- trash page's button no longer reaches them.
    local others = I.SpecsWithRules and I.SpecsWithRules("auraSound") or {}
    if #others > 0 then
        local copy = ns.Button(parent, "Copy From Spec", 160, 24, function()
            ns.ShowCopyTrashRulesPopup(UI, "auraSound")
        end)
        copy:SetPoint("TOPLEFT", parent, "TOPLEFT", 160, y)
        ns.Tooltip(copy, "Copy From Spec",
            "Brings another spec's debuff alerts over to this one. They are saved per spec, "
            .. "and anything already here is left alone.")
    end
    StatusLines(parent, y)

    local side = Panel(parent, "Saved Debuff Alerts", 20, y - 68, 280, PANEL_H)
    local add = ns.Button(side, "+ Debuff Alert", 252, 26, function()
        debuffSelection, debuffByID = { newAura = true }, false; UI:RefreshPage(true)
    end)
    add:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -42)

    local scroll = CreateFrame("ScrollFrame", nil, side, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -78)
    scroll:SetSize(240, PANEL_H - 90)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetWidth(240); scroll:SetScrollChild(list)

    local rules = I.Rules(false) or {}
    local rows = {}
    for uid, r in pairs(rules) do
        if r.trigger.type == "auraSound" then rows[#rows + 1] = { uid = uid, rule = r } end
    end
    table.sort(rows, function(a, b) return a.uid < b.uid end)

    -- Grouped by the instance each alert is set for. An alert set for everywhere has no
    -- instance to file under, so it goes last.
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
            -- Found whether or not its group is open: folding a group away is not the same
            -- as deselecting what is inside it, and the editor on the right must not blank.
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

    local right = CreateFrame("Frame", nil, parent)
    right:SetPoint("TOPLEFT", parent, "TOPLEFT", 320, y - 68)
    right:SetSize(604, PANEL_H)
    if debuffSelection.newAura then Editor(right, nil)
    elseif chosen then Editor(right, chosen.uid)
    else
        Label(right, "A debuff sound plays when an aura is applied, stacks or falls off.", 0, 0, 604, 14)
        Label(right, "Use the debuff's own aura spell ID. These apply wherever you set them, not to one dungeon. Changes save as you make them.", 0, -40, 604)
    end
    -- Measured rather than guessed: the wrapper adds its own padding on top of this,
    -- and a fixed number claimed room the page never used.
    return y - (68 + PANEL_H + 8)
end