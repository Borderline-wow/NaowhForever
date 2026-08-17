-------------------------------------------------------------------------------
--  NaowhUI_TankReminder_Bosses.lua -- browse this season's bosses and every ability the
--  journal lists for them, labelled by who each one is aimed at.
--
--  Nothing here is shipped data. Every name, icon and tank marking is read out of the
--  player's own client at runtime, so it cannot go stale, it covers whatever season the
--  client is on, and the addon carries no encounter knowledge of its own.
--
--  The tank marking comes from the Encounter Journal, NOT from C_EncounterEvents. That is
--  deliberate and worth recording, because the other route looks tempting and is wrong:
--
--    * C_EncounterEvents carries the TankRole bit the live HUD uses, in the clear -- but it
--      has NO boss association in any form. No function takes an encounter ID, and no field
--      links a record back to one. Blizzard never calls the namespace from Lua at all; the
--      association lives C-side.
--    * Joining the two on spellID silently loses exactly the abilities we care about. The
--      journal's spellID is the DISPLAY spell (routinely the applied aura), while the event's
--      is the spell that TRIGGERS the cast. For a tank buster that casts one spell and applies
--      a stacking debuff -- which is most of them -- those are different IDs and the join
--      drops the ability. The docs also warn one spell may back several event records with
--      different masks, so the join is not even a function.
--
--  The journal's own Tank flag, by contrast, arrives already attached to its boss, from the
--  same walk that gives the name and icon. No join needed.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

-- GetSectionIconFlags returns INDICES into the flag list, not the enum values, so Tank (the
-- lowest bit, value 1) is index 0. Blizzard hardcodes the same 0 in its own role table.
--
-- EVERY ability is listed, not only tank-flagged ones: which abilities matter is the player's
-- call, and a healer or a damage dealer needs the same reference a tank does. The flags ride
-- along as labels so the list still says who each one is aimed at.
local FLAG_LABELS = {
    [0]  = "Tank",
    [1]  = "Dps",
    [2]  = "Healer",
    [3]  = "Heroic",
    [4]  = "Deadly",
    [5]  = "Important",
    [6]  = "Interruptible",
    [7]  = "Magic",
    [13] = "Bleed",
}

-------------------------------------------------------------------------------
--  Journal availability
-------------------------------------------------------------------------------
-- Blizzard_EncounterJournal is load-on-demand, so the EJ_ globals do not exist until
-- something has opened it. We load it ourselves rather than telling the user to go and open
-- the dungeon journal first.
local function EnsureJournal()
    if EJ_GetCurrentTier and C_EncounterJournal and C_EncounterJournal.GetSectionInfo then
        return true
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end
    return EJ_GetCurrentTier ~= nil and C_EncounterJournal ~= nil
        and C_EncounterJournal.GetSectionInfo ~= nil
end

-- EJ_SelectTier and EJ_SelectInstance mutate journal state that the Encounter Journal UI
-- reads back with no arguments, and it caches its own copy that will not resync. Scraping
-- underneath an open journal corrupts what the player is looking at. Blizzard evidently hit
-- this too -- there is a commented-out EJ_SelectInstance in their own content-tracking code.
local function JournalBusy()
    return EncounterJournal ~= nil and EncounterJournal:IsShown()
end

-------------------------------------------------------------------------------
--  The scrape
-------------------------------------------------------------------------------
-- In memory, built on first view and kept for the session. Nothing is scraped at login: a
-- player who never opens this page pays nothing for it.
local cache          -- { instances = { {id, name, isRaid, bosses = { {name, abilities} } } } }
local scrapeFailed
-- Stage-by-stage record of the last scrape, so an empty panel can say WHICH step produced
-- nothing rather than just looking broken. Read by /nutank bosses.
local diag = {}

local function WalkSections(rootID, out, depth, seen)
    -- Depth-capped: the section tree is authored data and a malformed cycle would otherwise
    -- hang the client rather than produce a bad list.
    if not rootID or depth > 12 then return end
    seen = seen or {}
    local id = rootID
    local guard = 0
    while id and guard < 200 do
        guard = guard + 1
        local info = C_EncounterJournal.GetSectionInfo(id)
        if not info then break end

        local flags = C_EncounterJournal.GetSectionIconFlags(id)
        local extras
        if flags then
            for i = 1, #flags do
                local lbl = FLAG_LABELS[flags[i]]
                if lbl then extras = extras and (extras .. ", " .. lbl) or lbl end
            end
        end

        -- A real ability, not a section header. The journal groups its advice under headers
        -- like "Tanks" and "Healers", and those carry the tank icon flag too -- but they have
        -- no spell behind them, which is what tells the two apart.
        local isAbility = info.spellID and info.spellID > 0
        if isAbility and info.title and info.title ~= "" then
            -- One row per spell. The journal repeats the same ability under its overview,
            -- its per-role advice and its stage sections, and rendering each occurrence
            -- made every boss look like it had twice the abilities it does. Later
            -- occurrences only contribute role labels the first one lacked.
            local prior = seen[info.spellID]
            if prior then
                if extras and extras ~= "" then
                    if not prior.extras or prior.extras == "" then
                        prior.extras = extras
                    elseif not prior.extras:find(extras, 1, true) then
                        prior.extras = prior.extras .. ", " .. extras
                    end
                end
            else
                local entry = {
                    title   = info.title,
                    spellID = info.spellID,
                    icon    = info.abilityIcon,
                    extras  = extras,
                }
                seen[info.spellID] = entry
                out[#out + 1] = entry
            end
        end

        WalkSections(info.firstChildSectionID, out, depth + 1, seen)
        id = info.siblingSectionID
    end
end

local function ScrapeInstance(instanceID, name, isRaid)
    local entry = { id = instanceID, name = name, isRaid = isRaid, bosses = {} }

    EJ_SelectInstance(instanceID)
    for i = 1, 40 do
        local bossName, _, bossID = EJ_GetEncounterInfoByIndex(i)
        if not bossName then break end
        if bossID then
            -- Return 7 is dungeonEncounterID: the same id ENCOUNTER_START reports, which is
            -- what makes a list set up here fire on the right boss.
            local _, _, _, rootSectionID, _, _, dungeonEncounterID = EJ_GetEncounterInfo(bossID)
            local abilities = {}
            WalkSections(rootSectionID, abilities, 1)
            entry.bosses[#entry.bosses + 1] = {
                name = bossName,
                encounterID = dungeonEncounterID,
                abilities = abilities,
            }
        end
    end
    return entry
end

function ns.ScrapeBosses(force)
    if cache and not force then return cache end
    if not EnsureJournal() then scrapeFailed = "journal" return nil end
    if JournalBusy() then scrapeFailed = "busy" return nil end
    scrapeFailed = nil

    -- Put the journal back exactly as we found it. The UI keeps its own copy of the
    -- selection and will not notice ours, so leaving it moved is a real bug for anyone who
    -- opens the journal afterwards.
    local priorTier = EJ_GetCurrentTier and EJ_GetCurrentTier()

    local out = { instances = {} }
    wipe(diag)
    diag.tier = priorTier

    -- Mythic+ pool: this is the live season list, the same call Blizzard's own keystone UI
    -- uses, so it needs no season constant of ours and updates itself.
    if C_ChallengeMode and C_ChallengeMode.GetMapTable and C_EncounterJournal.GetInstanceForGameMap then
        local maps = C_ChallengeMode.GetMapTable()
        diag.mapCount = maps and #maps or 0
        diag.mapped = 0
        for i = 1, (maps and #maps or 0) do
            local mapName, _, _, _, _, gameMapID = C_ChallengeMode.GetMapUIInfo(maps[i])
            local journalID = gameMapID and C_EncounterJournal.GetInstanceForGameMap(gameMapID)
            if journalID then
                diag.mapped = diag.mapped + 1
                out.instances[#out.instances + 1] = ScrapeInstance(journalID, mapName or "?", false)
            end
        end
    else
        diag.mapCount = -1   -- the API itself was unavailable
    end

    -- Current raid. There is no "give me the latest raid" API, so this is the current tier's
    -- raid list, newest last, which is the same heuristic the journal itself leans on.
    diag.raids = 0
    if EJ_SelectTier and EJ_GetInstanceByIndex and priorTier then
        EJ_SelectTier(priorTier)
        for i = 1, 20 do
            local instanceID, rname = EJ_GetInstanceByIndex(i, true)
            if not instanceID then break end
            diag.raids = diag.raids + 1
            out.instances[#out.instances + 1] = ScrapeInstance(instanceID, rname or "?", true)
        end
    end

    diag.instances = #out.instances
    diag.bosses = 0
    for i = 1, #out.instances do diag.bosses = diag.bosses + #out.instances[i].bosses end

    if priorTier and EJ_SelectTier then EJ_SelectTier(priorTier) end

    cache = out
    return cache
end

-------------------------------------------------------------------------------
--  The tree page
-------------------------------------------------------------------------------
-- Dungeons and raids as a collapsed tree: click an instance to open it, click a boss to set
-- a priority just for that boss. Everything renders through EllesmereUI's widget factory, so
-- this is a real options page rather than a custom window pretending to be one, and it
-- inherits the suite's look and its search indexing for free.
--
-- State is page-local and deliberately not saved: which node you last had open is not a
-- setting, and persisting it would make the page open somewhere surprising.
-- Sets rather than one selection: this is a tree, and comparing two bosses side by side is
-- the normal thing to want. Page-local and deliberately unsaved -- which node you last had
-- open is not a setting.
local expandedInst, expandedBoss = {}, {}

local function InstanceOf(data, id)
    for i = 1, #data.instances do
        if data.instances[i].id == id then return data.instances[i] end
    end
end

-- One editor, used for the spec default and for every per-boss override.
--
-- Enabled entries sit at the top in priority order, each with a grab handle you drag to
-- reorder. Disabled ones fall to the bottom, greyed, and a checkbox moves an entry between
-- the two halves. The automatic set comes from Blizzard's own defensive classification; the
-- Add by Spell ID row is the escape hatch for anything it misses.
--
-- "Call for an External" is pinned below everything and cannot be moved or switched off: it
-- is what happens when nothing above it is up, so by definition it is last.

-- Rebuilt on every render. The drop target is worked out by comparing the cursor against
-- these rows' real screen bounds, which is why they have to be captured rather than assumed.
local dragRows, dragging = {}, nil

local function DropIndexFromCursor()
    local _, cy = GetCursorPosition()
    for i = 1, #dragRows do
        local r = dragRows[i]
        local f = r.frame
        if f and f:IsShown() then
            local scale = f:GetEffectiveScale()
            local top, bottom = f:GetTop(), f:GetBottom()
            if top and bottom and cy <= top * scale and cy >= bottom * scale then
                return r.index
            end
        end
    end
    return nil
end

-- Extra controls chain leftward from a row's main widget through _lastInline, which is the
-- same slot EllesmereUI's own cogs and swatches use -- so ours line up with theirs.
local function AttachInline(rgn, text, width, onClick, tipTitle, tipBody)
    if not rgn then return end
    local btn = ns.Button(rgn, text, width or 46, 20, onClick)
    btn:SetPoint("RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -8, 0)
    rgn._lastInline = btn
    if tipTitle then ns.Tooltip(btn, tipTitle, tipBody) end
    return btn
end

-- A small x on the row, left of the label. Takes the ability out of the choices entirely,
-- as opposed to the checkbox which only moves it between in-play and not-in-play.
local function AttachRemove(row, entry, specID, EUI, onGone)
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(14, 14)
    btn:SetPoint("LEFT", row, "LEFT", 22, 0)
    btn:SetFrameLevel(row:GetFrameLevel() + 6)

    local a = ns.Solid(btn, "OVERLAY", ns.THEME.muted, 0.85)
    a:SetSize(10, 2); a:SetPoint("CENTER"); a:SetRotation(math.rad(45))
    local b = ns.Solid(btn, "OVERLAY", ns.THEME.muted, 0.85)
    b:SetSize(10, 2); b:SetPoint("CENTER"); b:SetRotation(math.rad(-45))

    btn:SetScript("OnEnter", function()
        a:SetColorTexture(1, 0.35, 0.35, 1); b:SetColorTexture(1, 0.35, 0.35, 1)
        local EUIg = _G.EllesmereUI
        if EUIg and EUIg.ShowWidgetTooltip then
            EUIg.ShowWidgetTooltip(btn, "Remove",
                entry.userAdded and "Deletes this spell you added."
                or "Takes this out of your choices. Restore them with the button at the bottom.")
        end
    end)
    btn:SetScript("OnLeave", function()
        local c = ns.THEME.muted
        a:SetColorTexture(c.r, c.g, c.b, 0.85); b:SetColorTexture(c.r, c.g, c.b, 0.85)
        local EUIg = _G.EllesmereUI
        if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
    end)
    btn:SetScript("OnClick", function()
        if onGone then onGone() end
        EUI:RefreshPage(true)
    end)
    return btn
end

local function AttachGrabber(row, spellID, index, specID, encounterID, EUI)
    local grab = CreateFrame("Button", nil, row)
    grab:SetSize(14, 22)
    grab:SetPoint("LEFT", row, "LEFT", 4, 0)
    grab:SetFrameLevel(row:GetFrameLevel() + 6)

    -- Six dots: the conventional "pick me up" affordance, drawn rather than textured so it
    -- follows the theme.
    for c = 0, 1 do
        for r2 = 0, 2 do
            local d = ns.Solid(grab, "OVERLAY", ns.THEME.muted, 0.85)
            d:SetSize(3, 3)
            d:SetPoint("TOPLEFT", grab, "TOPLEFT", 3 + c * 5, -(4 + r2 * 6))
        end
    end

    grab:RegisterForDrag("LeftButton")
    grab:SetScript("OnDragStart", function()
        dragging = { spellID = spellID, from = index }
        row:SetAlpha(0.5)
    end)
    grab:SetScript("OnDragStop", function()
        row:SetAlpha(1)
        local d = dragging
        dragging = nil
        if not d then return end
        local dest = DropIndexFromCursor()
        if dest and dest ~= d.from then
            ns.MoveOnList(specID, encounterID, d.spellID, dest)
            EUI:RefreshPage(true)
        end
    end)
    ns.Tooltip(grab, "Drag to reorder", "Drag this onto another enabled ability to change the "
        .. "order it is called out in.")
    return grab
end

function ns.RenderPriorityEditor(parent, y, W, EUI, specID, encounterID)
    local _, h, row
    local list = ns.EffectiveListFor(specID, encounterID) or {}
    local auto = ns.AllDefensives(specID, encounterID)

    wipe(dragRows)

    -- Everything the player could choose from: Blizzard's set plus their own additions.
    local hidden = ns.HiddenSpells(specID)
    local function IsHidden(id) return hidden ~= nil and hidden[tostring(id)] == true end

    local pool, seen = {}, {}
    for i = 1, #auto do
        if not IsHidden(auto[i].id) then
            pool[#pool + 1] = auto[i]
            seen[auto[i].id] = true
        end
    end
    local custom = ns.CustomSpells(specID)
    if custom then
        for key in pairs(custom) do
            local sid = tonumber(key)
            if sid and not seen[sid] and not IsHidden(sid) then
                seen[sid] = true
                local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                pool[#pool + 1] = {
                    id = sid, name = (si and si.name) or ("Spell " .. sid),
                    icon = si and si.iconID, cd = 0, userAdded = true,
                }
            end
        end
    end

    -- Enabled, in priority order, draggable.
    for i = 1, #list do
        local spellID = list[i]
        local idx = i
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        local name = (info and info.name) or ("Spell " .. spellID)
        local label = ("      %d.  %s"):format(idx, name)
        if not ns.IsSpellAvailable(spellID) then label = label .. "  (not talented)" end

        row, h = W:DualRow(parent, y,
            { type = "toggle", text = label,
              tooltip = ("Spell ID %d. Untick to drop it to the bottom of the list."):format(spellID),
              getValue = function() return true end,
              setValue = function()
                  ns.SetSpellOnList(specID, encounterID, spellID, false)
                  EUI:RefreshPage(true)
              end },
            { type = "toggle", text = "Audio",
              tooltip = "Speaks this one when it is the defensive to press. Switch it off to "
              .. "keep it in your priority order but stay silent for it -- the icon and text "
              .. "still show.",
              getValue = function() return not ns.IsAudioOff(spellID) end,
              setValue = function(v)
                  ns.SetAudioOff(spellID, not v)
                  EUI:RefreshPage(true)
              end }
        ); y = y - h

        -- The wording is only worth reaching when it will actually be spoken.
        if row and not ns.IsAudioOff(spellID) then
            AttachInline(row._rightRegion, "Edit", 46, function()
                ns.ShowCalloutEditor(("Audio callout for %s"):format(name),
                    ns.CalloutFor(spellID, name), function(text)
                        ns.SetCallout(spellID, text)
                        EUI:RefreshPage(true)
                    end, spellID)
            end, "Edit the callout", "What is spoken, and what the text alert shows, for this ability.")
        end

        if row then
            dragRows[#dragRows + 1] = { frame = row, spellID = spellID, index = idx }
            AttachGrabber(row, spellID, idx, specID, encounterID, EUI)
            AttachRemove(row, { id = spellID, userAdded = false }, specID, EUI, function()
                ns.SetSpellOnList(specID, encounterID, spellID, false)
                ns.HideSpell(specID, spellID)
            end)
        end
    end

    -- Disabled, at the bottom, greyed.
    local spare = {}
    for i = 1, #pool do
        if not ns.ListIndexOf(list, pool[i].id) then spare[#spare + 1] = pool[i] end
    end
    table.sort(spare, function(a, b) return a.name < b.name end)

    for i = 1, #spare do
        local c = spare[i]
        row, h = W:DualRow(parent, y,
            { type = "toggle", text = "      |cff8a99b5" .. c.name .. "|r",
              tooltip = ("Spell ID %d. Tick to put it into your priority order."):format(c.id),
              getValue = function() return false end,
              setValue = function()
                  ns.SetSpellOnList(specID, encounterID, c.id, true)
                  EUI:RefreshPage(true)
              end },
            { type = "label", text = c.userAdded and "added by you" or "" }
        ); y = y - h

        if row then
            AttachRemove(row, c, specID, EUI, function()
                if c.userAdded then ns.RemoveCustomSpell(specID, c.id)
                else ns.HideSpell(specID, c.id) end
                ns.SetSpellOnList(specID, encounterID, c.id, false)
            end)
        end
    end

    if #list == 0 and #spare == 0 then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "      No major defensives found for this specialization." },
            { type = "label", text = "" }
        ); y = y - h
    end

    -- Restoring what was removed. Only offered when there is something to restore.
    if hidden and next(hidden) ~= nil then
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "      Restore Removed Abilities",
              tooltip = "Brings back everything you removed from the choices for this spec.",
              getValue = function() return false end,
              setValue = function()
                  ns.UnhideAll(specID)
                  EUI:RefreshPage(true)
              end },
            { type = "label", text = "" }
        ); y = y - h
    end

    -- The spell ID entry. The widget factory has no text input, so the box and its button are
    -- built here and laid over the row's right half; the left slot carries the label so the
    -- row still reads like every other one.
    local db = ns.DB()
    row, h = W:DualRow(parent, y,
        { type = "label", text = "      Add an Ability by Spell ID" },
        { type = "label", text = "" }   -- overlaid below with the entry box and Add button
    ); y = y - h

    if row and row._rightRegion then
        local rgn = row._rightRegion

        local add = ns.Button(rgn, "Add", 54, 22, nil)
        add:SetPoint("RIGHT", rgn, "RIGHT", -14, 0)

        local box = CreateFrame("EditBox", nil, rgn)
        box:SetPoint("LEFT", rgn, "LEFT", 6, 0)
        box:SetPoint("RIGHT", add, "LEFT", -8, 0)
        box:SetHeight(24)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(9)
        box:SetFontObject("GameFontHighlight")
        box:SetTextInsets(6, 6, 0, 0)
        local well = ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1)
        well:SetAllPoints()
        ns.Border(box)

        local placeholder = ns.Font(box, 12, nil, ns.THEME.muted)
        placeholder:SetPoint("LEFT", box, "LEFT", 8, 0)
        placeholder:SetText("Enter SpellID")

        -- Sits under the box: the resolved name, or why the ID is refused. Feedback as you
        -- type is what stops a wrong ID being added and only failing later.
        local feedback = ns.Font(rgn, 10, nil, ns.THEME.muted)
        feedback:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -1)
        feedback:SetPoint("RIGHT", add, "LEFT", -8, 0)
        feedback:SetJustifyH("LEFT")

        local function Commit()
            local sid = ns.ResolveSpell(box:GetText())
            if not sid then return end                  -- the gate: invalid never adds
            if ns.AddCustomSpell(specID, sid) then
                box:SetText("")
                box:ClearFocus()
                EUI:RefreshPage(true)
            end
        end

        local function Validate()
            local text = box:GetText()
            placeholder:SetShown(text == nil or text == "")
            local sid, info = ns.ResolveSpell(text)
            if sid then
                add:Enable()
                add:SetAlpha(1)
                feedback:SetText("|cff6DD09A" .. (info.name or "") .. "|r")
            else
                add:Disable()
                add:SetAlpha(0.35)
                feedback:SetText((text ~= "" and text ~= nil) and "|cffff6060Not a spell ID|r" or "")
            end
        end

        add:SetScript("OnClick", Commit)
        box:SetScript("OnTextChanged", Validate)
        box:SetScript("OnEnterPressed", Commit)
        box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
        Validate()
    end

    row, h = W:DualRow(parent, y,
        { type = "toggle",
          text = ("      |cffF0A830Last:  %s|r"):format(db.voiceNone or "Call for an External"),
          tooltip = "The final step, used when nothing on your list is up. Switch it off to say "
          .. "and show nothing at all in that case.",
          getValue = function() return db.fallbackOn ~= false end,
          setValue = function(v)
              db.fallbackOn = v
              ns.RefreshRuntime()
              EUI:RefreshPage(true)
          end },
        { type = "toggle", text = "Audio",
          tooltip = "Speaks the fallback line when nothing on your list is up. This step is "
          .. "always last and cannot be moved, but it can be silenced.",
          disabled = function() return db.fallbackOn == false end,
          disabledTooltip = "Switch the last step back on to use this.",
          getValue = function() return db.fallbackOn ~= false and not ns.IsAudioOff(0) end,
          setValue = function(v)
              if db.fallbackOn == false then return end
              ns.SetAudioOff(0, not v)
              EUI:RefreshPage(true)
          end }
    ); y = y - h

    if row and db.fallbackOn ~= false and not ns.IsAudioOff(0) then
        AttachInline(row._rightRegion, "Edit", 46, function()
            ns.ShowCalloutEditor("Said and shown when nothing on the list is up",
                db.voiceNone, function(v)
                    db.voiceNone = v
                    ns.RefreshRuntime()
                    EUI:RefreshPage(true)
                end, 0)
        end, "Edit the fallback", "What is spoken and shown when every defensive is down.")
    end

    return y
end

local function RenderBoss(parent, y, W, EUI, inst, boss, specID)
    local _, h
    local encounterID = boss.encounterID

    -- Every DAMAGING ability the journal lists for this fight, with who it is aimed at.
    -- Reference only: see the options text for why these cannot each carry their own switch.
    --
    -- The journal itself does not say what hurts, so the damage set derived from the public
    -- classification sheet decides. When the sheet knows this boss, only abilities that
    -- damage somebody are shown; a boss the sheet has never heard of shows its full list,
    -- because an empty reference reads as broken rather than unclassified.
    local shown = {}
    for a = 1, #boss.abilities do
        local ab = boss.abilities[a]
        local sid = ab.spellID
        if sid and ((ns.DAMAGE_ABILITIES and ns.DAMAGE_ABILITIES[sid])
            or (ns.TANK_ABILITIES and ns.TANK_ABILITIES[sid])) then
            shown[#shown + 1] = ab
        end
    end
    if #shown == 0 then shown = boss.abilities end

    if #shown == 0 then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "         The journal lists no abilities for this boss." },
            { type = "label", text = "" }
        ); y = y - h
    else
        for a = 1, #shown do
            local ab = shown[a]
            _, h = W:DualRow(parent, y,
                { type = "label", text = "         |cffF0A830" .. ab.title .. "|r" },
                { type = "label", text = ab.extras or "" }
            ); y = y - h
        end
    end

    if not encounterID then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "         This boss has no encounter id, so it cannot hold a list." },
            { type = "label", text = "" }
        ); y = y - h
        return y
    end

    -- Per-boss switch. This one IS enforceable: the game tells us which encounter we are in,
    -- even though it will not tell us which ability is incoming.
    local db = ns.DB()
    local off = db.bossOff and db.bossOff[tostring(encounterID)]
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "         Remind Me on This Boss",
          tooltip = "Switch off to stay silent for this encounter without losing its list.",
          getValue = function() return not off end,
          setValue = function(v)
              if type(db.bossOff) ~= "table" then db.bossOff = {} end
              db.bossOff[tostring(encounterID)] = (not v) or nil
              if next(db.bossOff) == nil then db.bossOff = nil end
              ns.RefreshRuntime()
              EUI:RefreshPage(true)
          end },
        { type = "toggle", text = "Use My Spec Default",
          tooltip = "Clears this boss's own order so it follows your normal list again.",
          getValue = function()
              local bl = ns.BossList(specID, encounterID, false)
              return not (bl and #bl > 0)
          end,
          setValue = function()
              ns.ClearBossList(specID, encounterID)
              ns.RefreshRuntime()
              EUI:RefreshPage(true)
          end }
    ); y = y - h

    y = ns.RenderPriorityEditor(parent, y, W, EUI, specID, encounterID)
    return y
end

function ns.BuildTreeSection(parent, y)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local _, h
    local specID = ns.CurrentSpec()
    local db = ns.DB()

    _, h = W:SectionHeader(parent, "WHERE IT RUNS", y); y = y - h

    -- The two master switches, side by side: dungeons on the left, raids on the right.
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "All Dungeons",
          tooltip = "Turn the reminder off for every Mythic+ and dungeon boss without changing "
          .. "any of your priority lists.",
          getValue = function() return db.inDungeons ~= false end,
          setValue = function(v) db.inDungeons = v; ns.RefreshRuntime() end },
        { type = "toggle", text = "All Raids",
          tooltip = "Turn the reminder off for every raid boss without changing any of your "
          .. "priority lists.",
          getValue = function() return db.inRaids ~= false end,
          setValue = function(v) db.inRaids = v; ns.RefreshRuntime() end }
    ); y = y - h

    _, h = W:SectionHeader(parent, "DUNGEONS AND RAIDS", y); y = y - h

    local data = ns.ScrapeBosses(false)
    if not data or #data.instances == 0 then
        local why = (scrapeFailed == "busy")
            and "Close the Dungeon Journal and reopen this page."
            or "Nothing found yet. Open the Adventure Guide once, then use Refresh below."
        _, h = W:DualRow(parent, y,
            { type = "label", text = why },
            { type = "label", text = "Run /nutank bosses to see which step came back empty." }
        ); y = y - h
        _, h = W:Button(parent, "Refresh From the Dungeon Journal", y, function()
            ns.ScrapeBosses(true)
            EUI:RefreshPage(true)
        end)
        return y - h
    end

    local dungeons, raids = {}, {}
    for i = 1, #data.instances do
        local inst = data.instances[i]
        if inst.isRaid then raids[#raids + 1] = inst else dungeons[#dungeons + 1] = inst end
    end

    -- Level 1: the instance. A plus opens it, a minus closes it.
    local function InstanceSlot(inst)
        if not inst then return { type = "label", text = "" } end
        local open = expandedInst[inst.id] == true
        local marked = 0
        for b = 1, #inst.bosses do
            local eid = inst.bosses[b].encounterID
            local cl = eid and ns.BossList(specID, eid, false)
            if cl and #cl > 0 then marked = marked + 1 end
        end
        return { type = "toggle",
            text = ("%s  %s"):format(open and "-" or "+", inst.name),
            tooltip = ("%d bosses%s. Click to open."):format(
                #inst.bosses, marked > 0 and (", " .. marked .. " with their own list") or ""),
            getValue = function() return open end,
            setValue = function()
                expandedInst[inst.id] = (not open) or nil
                EUI:RefreshPage(true)
            end }
    end

    -- Levels 2 and 3: each boss gets its own plus, and opening it reveals that fight's
    -- its abilities and its priority editor.
    local function RenderInstanceBody(inst)
        if not inst then return end
        for b = 1, #inst.bosses do
            local boss = inst.bosses[b]
            local eid = boss.encounterID
            local bOpen = eid ~= nil and expandedBoss[eid] == true
            local custom = eid and ns.BossList(specID, eid, false)
            local state = (custom and #custom > 0) and "own list" or "spec default"

            _, h = W:DualRow(parent, y,
                { type = "toggle",
                  text = ("      %s  %s"):format(bOpen and "-" or "+", boss.name),
                  tooltip = ("%d abilities in the journal."):format(#boss.abilities),
                  getValue = function() return bOpen end,
                  setValue = function()
                      if not eid then return end
                      expandedBoss[eid] = (not bOpen) or nil
                      EUI:RefreshPage(true)
                  end },
                { type = "label", text = state }
            ); y = y - h

            if bOpen then
                y = RenderBoss(parent, y, W, EUI, inst, boss, specID)
            end
        end
    end

    local rows = math.max(#dungeons, #raids)
    for i = 1, rows do
        local d, r = dungeons[i], raids[i]
        _, h = W:DualRow(parent, y, InstanceSlot(d), InstanceSlot(r)); y = y - h

        -- Expanded bodies render under the row that owns them, left column first, so a pair
        -- opened at once still reads in a sensible order.
        if d and expandedInst[d.id] then RenderInstanceBody(d) end
        if r and expandedInst[r.id] then RenderInstanceBody(r) end
    end

    _, h = W:Button(parent, "Refresh From the Dungeon Journal", y, function()
        ns.ScrapeBosses(true)
        EUI:RefreshPage(true)
    end)
    y = y - h

    return y
end

-- Kept so the old chain point still resolves; the tree replaced the standalone panel.
function ns.BuildBossSection(parent, y)
    return ns.BuildTreeSection(parent, y)
end

-------------------------------------------------------------------------------
--  Diagnostics
-------------------------------------------------------------------------------
-- Coverage check. The journal's Tank flag is an editorial annotation and may not perfectly
-- match the TankRole bit the live HUD uses, and neither dataset is in the client source --
-- both are DB2 tables. This prints the totals so the two can be compared against a boss
-- whose abilities you already know.
function ns.PrintBossSummary()
    local data = ns.ScrapeBosses(false)
    if not data then
        ns.Print("could not read the journal (" .. tostring(scrapeFailed) .. ").")
        return
    end

    -- Stage report first: an empty list is almost always one of these returning nothing,
    -- and knowing which turns a guessing game into a one-line fix.
    ns.Print(("stages: tier=%s  challengeMaps=%s  mappedToJournal=%s  raidInstances=%s")
        :format(tostring(diag.tier), tostring(diag.mapCount),
                tostring(diag.mapped), tostring(diag.raids)))
    if diag.mapCount == -1 then
        ns.Print("|cffff6060C_ChallengeMode.GetMapTable is unavailable|r -- no dungeons can be listed.")
    elseif diag.mapCount == 0 then
        ns.Print("|cffff6060The keystone map table is empty|r -- open the Mythic+ UI once, then Refresh.")
    elseif (diag.mapped or 0) == 0 then
        ns.Print("|cffff6060No dungeon mapped to a journal instance|r -- GetInstanceForGameMap returned nothing.")
    end
    if (diag.raids or 0) == 0 then
        ns.Print("|cffff6060No raid found for the current tier|r -- open the Adventure Guide once, then Refresh.")
    end
    local instCount, bossCount, abilCount, emptyBosses = 0, 0, 0, 0
    for i = 1, #data.instances do
        local inst = data.instances[i]
        instCount = instCount + 1
        for b = 1, #inst.bosses do
            bossCount = bossCount + 1
            local n = #inst.bosses[b].abilities
            abilCount = abilCount + n
            if n == 0 then emptyBosses = emptyBosses + 1 end
        end
        ns.Print(("%s%s: %d bosses"):format(inst.isRaid and "[raid] " or "", inst.name, #inst.bosses))
    end
    ns.Print(("total: %d instances, %d bosses, %d abilities, %d bosses with none")
        :format(instCount, bossCount, abilCount, emptyBosses))
end
