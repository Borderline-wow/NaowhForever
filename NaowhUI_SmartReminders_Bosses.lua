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
        -- Casts only. The journal also lists passives -- auras that empower the boss's
        -- melee, say -- and a passive is never an event: nothing announces it, nothing can
        -- warn about it, and a reference list is for things a tank can react to. The spell
        -- record itself knows, which beats any name list and covers every boss.
        if isAbility and C_Spell and C_Spell.IsSpellPassive then
            local okP, passive = pcall(C_Spell.IsSpellPassive, info.spellID)
            if okP and passive == true then isAbility = false end
        end
        if isAbility and info.title and info.title ~= "" then
            -- One row per spell. The journal repeats the same ability under its overview,
            -- its per-role advice and its stage sections, and rendering each occurrence
            -- made every boss look like it had twice the abilities it does. Later
            -- occurrences only contribute role labels the first one lacked.
            local prior = seen[info.spellID]
            if prior then
                if (not prior.description or prior.description == "")
                    and info.description and info.description ~= "" then
                    prior.description = info.description
                end
                if extras and extras ~= "" then
                    if not prior.extras or prior.extras == "" then
                        prior.extras = extras
                    elseif not prior.extras:find(extras, 1, true) then
                        prior.extras = prior.extras .. ", " .. extras
                    end
                end
            else
                local entry = {
                    title       = info.title,
                    spellID     = info.spellID,
                    icon        = info.abilityIcon,
                    extras      = extras,
                    -- The journal's own explanation of what the ability does, for the
                    -- hover tooltip. Blizzard's text, not ours.
                    description = info.description,
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
-- Instance expansion state used to live here; instances open as modals now.

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

-- The house cog on any row region: 26px, shared art, dim until hovered, anchored left of
-- the region's control -- the same geometry as every cog in the suite.
local function AttachRowCog(rgn, onClick, tipTitle, tipBody)
    if not rgn then return end
    local cog = CreateFrame("Button", nil, rgn)
    cog:SetSize(26, 26)
    cog:SetPoint("RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -8, 0)
    rgn._lastInline = cog
    cog:SetFrameLevel(rgn:GetFrameLevel() + 5)
    cog:SetAlpha(0.4)
    local tex = cog:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    local EUIg = _G.EllesmereUI
    if EUIg and EUIg.COGS_ICON then tex:SetTexture(EUIg.COGS_ICON) end
    cog:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
        if EUIg and EUIg.ShowWidgetTooltip and tipTitle then
            EUIg.ShowWidgetTooltip(self, tipBody and (tipTitle .. ": " .. tipBody) or tipTitle)
        end
    end)
    cog:SetScript("OnLeave", function(self)
        self:SetAlpha(0.4)
        if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
    end)
    cog:SetScript("OnClick", function() if onClick then onClick() end end)
    return cog
end

-------------------------------------------------------------------------------
--  Preset list editor: the spec-default page, one preset picker on the left
--  and its condensed ability list on the right.
-------------------------------------------------------------------------------

local function ShowAddPresetPopup(specID, EUI)
    local dimmer, panel = ns.MakeModal(340, 150)
    dimmer:SetFrameStrata("TOOLTIP")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("New Preset")

    local box = CreateFrame("EditBox", nil, panel)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -50)
    box:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    box:SetHeight(26)
    box:SetAutoFocus(true)
    box:SetMaxLetters(40)
    box:SetFontObject("GameFontHighlight")
    box:SetTextInsets(6, 6, 0, 0)
    ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    ns.Border(box)
    box:SetText(ns.NextPresetName(specID))
    box:HighlightText()

    local function Commit()
        ns.AddPreset(specID, box:GetText())
        dimmer:Hide()
        EUI:RefreshPage(true)
    end
    box:SetScript("OnEnterPressed", Commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); dimmer:Hide() end)

    ns.Button(panel, "Create", 90, 26, Commit):SetPoint("BOTTOM", panel, "BOTTOM", -50, 16)
    ns.Button(panel, "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 50, 16)

    dimmer:Show()
end

-- Audio settings for one ability. The cog is designed to grow -- text options and whatever
-- else makes sense later -- so its content lives in its own small modal rather than crowding
-- the row.
local function ShowAbilitySettingsPopup(specID, spellID, name, EUI)
    local W = EUI.Widgets
    local dimmer, panel = ns.MakeModal(360, 130)
    dimmer:SetFrameStrata("TOOLTIP")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(name)

    local editBtn
    local y = -46
    local _, h = W:DualRow(panel, y,
        { type = "toggle", text = "Audio",
          tooltip = "Speaks this one when it is the defensive to press. Switch it off to "
          .. "keep it in your priority order but stay silent for it -- the icon and text "
          .. "still show.",
          getValue = function() return not ns.IsAudioOff(spellID) end,
          setValue = function(v)
              ns.SetAudioOff(spellID, not v)
              if editBtn then editBtn:SetShown(v) end
          end }
    ); y = y - h

    editBtn = ns.Button(panel, "Edit Callout", 120, 24, function()
        ns.ShowCalloutEditor(("Audio callout for %s"):format(name),
            ns.CalloutFor(spellID, name), function(text)
                ns.SetCallout(spellID, text)
                if EUI.RefreshPage then EUI:RefreshPage(true) end
            end, spellID)
    end)
    editBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - 6)
    editBtn:SetShown(not ns.IsAudioOff(spellID))

    ns.Button(panel, "Close", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)

    dimmer:Show()
end

-- Same shape as the ability popup above, but the fallback step stores its audio flag under
-- spellID 0 and its text directly on db.voiceNone rather than through the callout table, so
-- it cannot share ShowAbilitySettingsPopup's storage calls.
local function ShowFallbackSettingsPopup(EUI)
    local W = EUI.Widgets
    local db = ns.DB()
    local dimmer, panel = ns.MakeModal(360, 130)
    dimmer:SetFrameStrata("TOOLTIP")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("Call for an External")

    local editBtn
    local y = -46
    local _, h = W:DualRow(panel, y,
        { type = "toggle", text = "Audio",
          tooltip = "Speaks the fallback line when nothing on your list is up. This step is "
          .. "always last and cannot be moved, but it can be silenced.",
          disabled = function() return db.fallbackOn == false end,
          disabledTooltip = "Switch the last step back on to use this.",
          getValue = function() return db.fallbackOn ~= false and not ns.IsAudioOff(0) end,
          setValue = function(v)
              if db.fallbackOn == false then return end
              ns.SetAudioOff(0, not v)
              if editBtn then editBtn:SetShown(v) end
          end }
    ); y = y - h

    editBtn = ns.Button(panel, "Edit Callout", 120, 24, function()
        ns.ShowCalloutEditor("Said and shown when nothing on the list is up",
            db.voiceNone, function(v)
                db.voiceNone = v
                ns.RefreshRuntime()
            end, 0)
    end)
    editBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - 6)
    editBtn:SetShown(db.fallbackOn ~= false and not ns.IsAudioOff(0))

    ns.Button(panel, "Close", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)

    dimmer:Show()
end

-- A left-column entry: click to switch presets, x to delete. Hand-drawn rather than a
-- DualRow toggle since it needs the active highlight and the delete affordance a checkbox
-- row does not have.
local function BuildPresetRow(leftPane, ly, rowW, rowH, specID, p, isActive, canDelete, EUI)
    local prow = CreateFrame("Button", nil, leftPane)
    prow:SetSize(rowW, rowH)
    prow:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, ly)

    if isActive then
        local bg = ns.Solid(prow, "BACKGROUND", ns.THEME.gold, 0.15)
        bg:SetAllPoints()
    end

    local lbl = ns.Font(prow, 13, nil, isActive and ns.THEME.fg or ns.THEME.muted)
    lbl:SetPoint("LEFT", prow, "LEFT", 8, 0)
    lbl:SetPoint("RIGHT", prow, "RIGHT", canDelete and -24 or -8, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetText(p.name)

    prow:SetScript("OnClick", function()
        ns.SelectPreset(specID, p.key)
        EUI:RefreshPage(true)
    end)

    if canDelete then
        local del = CreateFrame("Button", nil, prow)
        del:SetSize(14, 14)
        del:SetPoint("RIGHT", prow, "RIGHT", -6, 0)
        local a = ns.Solid(del, "OVERLAY", ns.THEME.muted, 0.85)
        a:SetSize(10, 2); a:SetPoint("CENTER"); a:SetRotation(math.rad(45))
        local b = ns.Solid(del, "OVERLAY", ns.THEME.muted, 0.85)
        b:SetSize(10, 2); b:SetPoint("CENTER"); b:SetRotation(math.rad(-45))
        del:SetScript("OnEnter", function(self)
            a:SetColorTexture(1, 0.35, 0.35, 1); b:SetColorTexture(1, 0.35, 0.35, 1)
            local EUIg = _G.EllesmereUI
            if EUIg and EUIg.ShowWidgetTooltip then
                EUIg.ShowWidgetTooltip(self,
                    "|cffF0A830Delete Preset|r\nRemoves this preset and its list. Cannot be undone.")
            end
        end)
        del:SetScript("OnLeave", function()
            local c = ns.THEME.muted
            a:SetColorTexture(c.r, c.g, c.b, 0.85); b:SetColorTexture(c.r, c.g, c.b, 0.85)
            local EUIg = _G.EllesmereUI
            if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
        end)
        del:SetScript("OnClick", function()
            ns.DeletePreset(specID, p.key)
            EUI:RefreshPage(true)
        end)
    end

    return prow
end

-- The spec-default page: a preset picker on the left, and the active preset's list -- every
-- row condensed to one column, with a settings cog where the old layout had a second column
-- -- on the right. Per-boss overrides still go through ns.RenderPriorityEditor unchanged.
function ns.RenderPresetListEditor(parent, y, W, EUI, specID)
    local _, h, row
    local topY = y

    if #ns.ListPresets(specID) == 0 then
        ns.AddPreset(specID, "Default")
    end
    local presets = ns.ListPresets(specID)
    local activeKey = ns.ActivePresetKey(specID)

    local PRESET_ROW_H = 34
    local LEFT_W = 190
    local GAP = 16
    local totalW = parent:GetWidth() - EUI.CONTENT_PAD * 2
    local rightW = totalW - LEFT_W - GAP

    local leftPane = CreateFrame("Frame", nil, parent)
    leftPane:SetSize(LEFT_W, 10)
    leftPane:SetPoint("TOPLEFT", parent, "TOPLEFT", EUI.CONTENT_PAD, topY)

    local rightPane = CreateFrame("Frame", nil, parent)
    rightPane:SetSize(rightW, 10)
    rightPane:SetPoint("TOPLEFT", parent, "TOPLEFT", EUI.CONTENT_PAD + LEFT_W + GAP, topY)

    -- Left column: one row per preset, then the add-preset row.
    local ly = 0
    for i = 1, #presets do
        local p = presets[i]
        BuildPresetRow(leftPane, ly, LEFT_W, PRESET_ROW_H, specID, p,
            p.key == activeKey, #presets > 1, EUI)
        ly = ly - PRESET_ROW_H
    end

    local addRow = CreateFrame("Button", nil, leftPane)
    addRow:SetSize(LEFT_W, PRESET_ROW_H)
    addRow:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, ly)
    local addLbl = ns.Font(addRow, 13, nil, ns.THEME.muted)
    addLbl:SetPoint("LEFT", addRow, "LEFT", 8, 0)
    addLbl:SetText("+ Add Preset")
    addRow:SetScript("OnEnter", function()
        local c = ns.THEME.fg
        addLbl:SetTextColor(c.r, c.g, c.b, 1)
    end)
    addRow:SetScript("OnLeave", function()
        local c = ns.THEME.muted
        addLbl:SetTextColor(c.r, c.g, c.b, 1)
    end)
    addRow:SetScript("OnClick", function() ShowAddPresetPopup(specID, EUI) end)
    ly = ly - PRESET_ROW_H

    -- Right column: the active preset's list, condensed to one control per row.
    local ry = 0
    local list = ns.EffectiveListFor(specID, nil) or {}
    local auto = ns.AllDefensives(specID, nil)

    wipe(dragRows)

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

    for i = 1, #list do
        local spellID = list[i]
        local idx = i
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        local name = (info and info.name) or ("Spell " .. spellID)
        local label = ("      %d.  %s"):format(idx, name)
        if not ns.IsSpellAvailable(spellID) then label = label .. "  (not talented)" end

        row, h = W:DualRow(rightPane, ry,
            { type = "toggle", text = label,
              tooltip = ("Spell ID %d. Untick to drop it to the bottom of the list."):format(spellID),
              getValue = function() return true end,
              setValue = function()
                  ns.SetSpellOnList(specID, nil, spellID, false)
                  EUI:RefreshPage(true)
              end }
        ); ry = ry - h

        if row then
            dragRows[#dragRows + 1] = { frame = row, spellID = spellID, index = idx }
            AttachGrabber(row, spellID, idx, specID, nil, EUI)
            AttachRemove(row, { id = spellID, userAdded = false }, specID, EUI, function()
                ns.SetSpellOnList(specID, nil, spellID, false)
                ns.HideSpell(specID, spellID)
            end)
            -- The row is single-column (no rightCfg), so the toggle lives in the LEFT
            -- region -- chain the cog off that region's control, not the empty right one,
            -- or it would anchor off in the dead space past the toggle.
            AttachRowCog(row._leftRegion, function()
                ShowAbilitySettingsPopup(specID, spellID, name, EUI)
            end, "Settings", "Audio, and anything added later.")
        end
    end

    local spare = {}
    for i = 1, #pool do
        if not ns.ListIndexOf(list, pool[i].id) then spare[#spare + 1] = pool[i] end
    end
    table.sort(spare, function(a, b) return a.name < b.name end)

    for i = 1, #spare do
        local c = spare[i]
        row, h = W:DualRow(rightPane, ry,
            { type = "toggle",
              text = "      |cff8a99b5" .. c.name .. (c.userAdded and " (added by you)" or "") .. "|r",
              tooltip = ("Spell ID %d. Tick to put it into your priority order."):format(c.id),
              getValue = function() return false end,
              setValue = function()
                  ns.SetSpellOnList(specID, nil, c.id, true)
                  EUI:RefreshPage(true)
              end }
        ); ry = ry - h

        if row then
            AttachRemove(row, c, specID, EUI, function()
                if c.userAdded then ns.RemoveCustomSpell(specID, c.id)
                else ns.HideSpell(specID, c.id) end
                ns.SetSpellOnList(specID, nil, c.id, false)
            end)
        end
    end

    if #list == 0 and #spare == 0 then
        _, h = W:DualRow(rightPane, ry,
            { type = "label", text = "      No major defensives found for this specialization." }
        ); ry = ry - h
    end

    if hidden and next(hidden) ~= nil then
        _, h = W:DualRow(rightPane, ry,
            { type = "toggle", text = "      Restore Removed Abilities",
              tooltip = "Brings back everything you removed from the choices for this spec.",
              getValue = function() return false end,
              setValue = function()
                  ns.UnhideAll(specID)
                  EUI:RefreshPage(true)
              end }
        ); ry = ry - h
    end

    -- The fallback step, condensed like everything above it: its own toggle plus a cog for
    -- audio and text, matching the shape of an ability row even though it is not one.
    local db = ns.DB()
    row, h = W:DualRow(rightPane, ry,
        { type = "toggle",
          text = ("      |cffF0A830Last:  %s|r"):format(db.voiceNone or "Call for an External"),
          tooltip = "The final step, used when nothing on your list is up. Switch it off to say "
          .. "and show nothing at all in that case.",
          getValue = function() return db.fallbackOn ~= false end,
          setValue = function(v)
              db.fallbackOn = v
              ns.RefreshRuntime()
              EUI:RefreshPage(true)
          end }
    ); ry = ry - h
    if row then
        AttachRowCog(row._leftRegion, function() ShowFallbackSettingsPopup(EUI) end,
            "Settings", "Audio, and anything added later.")
    end

    -- The spell ID entry, last: the widget factory has no text input, so the box and its
    -- button are built here and laid over the row's right half.
    row, h = W:DualRow(rightPane, ry,
        { type = "label", text = "      Add an Ability by Spell ID" },
        { type = "label", text = "" }   -- overlaid below with the entry box and Add button
    ); ry = ry - h

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

        local feedback = ns.Font(rgn, 10, nil, ns.THEME.muted)
        feedback:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -1)
        feedback:SetPoint("RIGHT", add, "LEFT", -8, 0)
        feedback:SetJustifyH("LEFT")

        local function Commit()
            local sid = ns.ResolveSpell(box:GetText())
            if not sid then return end
            if ns.AddCustomSpell(specID, sid) then
                ns.SetSpellOnList(specID, nil, sid, true)
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

    return topY + math.min(ly, ry)
end

local function RenderBoss(parent, y, W, EUI, inst, boss, specID, ui)
    local _, h
    local encounterID = boss.encounterID

    if not encounterID then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "         This boss has no encounter id, so it cannot hold a list." },
            { type = "label", text = "" }
        ); y = y - h
        return y
    end

    -- The whole boss as one hierarchy, tester-specified:
    --   Enable This Boss           (off = nothing below, no alerts of any kind)
    --     > ability (accordion)    (collapsed row per timeline event)
    --         Alert on This Ability     (off = that event stays quiet)
    --           Use My Spec Default / Custom Alert with its cog
    --           (spec default off -> that ability's own defensives editor)
    -- Ability enablement maps onto the runtime's existing marks and mutes -- enabling a
    -- non-buster writes a player mark, disabling a shipped buster writes a mute -- so the
    -- UI and the filter can never tell different stories.
    local db = ns.DB()
    local st = ui and (ui[encounterID] or {}) or {}
    if ui then ui[encounterID] = st end
    st.expanded = st.expanded or {}

    local bossOn = not (db.bossOff and db.bossOff[tostring(encounterID)])
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable This Boss",
          tooltip = "Off means this boss makes no alerts at all -- no defensives, no "
          .. "reminders, nothing -- and its options below disappear until it is back on.",
          getValue = function() return bossOn end,
          setValue = function(v)
              if type(db.bossOff) ~= "table" then db.bossOff = {} end
              db.bossOff[tostring(encounterID)] = (not v) or nil
              if next(db.bossOff) == nil then db.bossOff = nil end
              ns.RefreshRuntime()
              EUI:RefreshPage(true)
          end },
        { type = "label", text = "" }
    ); y = y - h

    if not bossOn then return y end

    local function AbilityEnabled(fp)
        local sh = ns.ShippedMarksFor and ns.ShippedMarksFor(encounterID)
        local pmk = ns.MarksTable(false, encounterID)
        local covered = (sh and sh[fp] == true) or (pmk and pmk[fp] == true)
        if not covered then return false end
        local m = ns.MutedTable(false, encounterID)
        return not (m and m[fp] == true)
    end

    local function SetAbilityEnabled(fp, on)
        local sh = ns.ShippedMarksFor and ns.ShippedMarksFor(encounterID)
        local shipped = sh and sh[fp] == true
        if on then
            if not shipped then ns.MarksTable(true, encounterID)[fp] = true end
            local m = ns.MutedTable(false, encounterID)
            if m then m[fp] = nil end
        else
            if shipped then
                ns.MutedTable(true, encounterID)[fp] = true
            else
                local pmk = ns.MarksTable(false, encounterID)
                if pmk then pmk[fp] = nil end
                local m = ns.MutedTable(false, encounterID)
                if m then m[fp] = nil end
            end
        end
        ns.RefreshRuntime()
    end

    -- Every known event, GROUPED BY ABILITY: one ability can own several fingerprints
    -- (a late-cast variant is a second duration of the same spell), and listing one row
    -- per fingerprint doubled names in the accordion. Every control on a group applies to
    -- all of its fingerprints at once.
    local groups, byName = {}, {}
    local function AddFp(fp)
        local nm = ns.EventNameFor(encounterID, fp)
        local disp = (nm == fp) and ("event " .. fp) or nm
        local g = byName[disp]
        if not g then
            g = { name = disp, fps = {}, first = tonumber(fp) or 0 }
            byName[disp] = g
            groups[#groups + 1] = g
        end
        g.fps[#g.fps + 1] = fp
        local n = tonumber(fp) or 0
        if n < g.first then g.first = n end
    end
    local named = ns.EVENT_NAMES and ns.EVENT_NAMES[encounterID]
    local seen = {}
    if named then
        for fp in pairs(named) do
            seen[fp] = true
            AddFp(fp)
        end
    end
    local pmarks = ns.MarksTable and ns.MarksTable(false, encounterID)
    if pmarks then
        for fp in pairs(pmarks) do
            if not seen[fp] then AddFp(fp) end
        end
    end
    table.sort(groups, function(x, z) return x.first < z.first end)

    if #groups == 0 then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "No timeline data for this boss yet. Learning mode "
              .. "and /nutank tank are how it gets some." },
            { type = "label", text = "" }
        ); y = y - h
        return y
    end

    local GRID_H = 28
    for i = 1, #groups do
        local g = groups[i]
        local disp = g.name
        local open = st.expanded[disp] == true

        local function AnyEnabled()
            for k = 1, #g.fps do
                if AbilityEnabled(g.fps[k]) then return true end
            end
            return false
        end

        -- Accordion header: hand-built (the factory rows misrender in this scroll child),
        -- whole row clickable, arrow and name, description on hover.
        local head = CreateFrame("Button", nil, parent)
        head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        head:SetSize(parent:GetWidth() > 0 and parent:GetWidth() or 600, GRID_H)
        ns.Solid(head, "BACKGROUND", ns.THEME.line, open and 0.35 or 0.18):SetAllPoints()

        local arrow = ns.Font(head, 13, nil, ns.THEME.gold)
        arrow:SetPoint("LEFT", head, "LEFT", 10, 0)
        arrow:SetText(open and "-" or "+")

        local name = ns.Font(head, 13, nil)
        name:SetPoint("LEFT", head, "LEFT", 26, 0)
        name:SetPoint("RIGHT", head, "RIGHT", -10, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local dim = not AnyEnabled()
        name:SetText(dim and ("|cff8a99b5" .. disp .. "|r") or disp)

        head:SetScript("OnClick", function()
            st.expanded[disp] = (not open) or nil
            EUI:RefreshPage(true)
        end)
        -- No hover description, by request: the names carry enough.
        y = y - GRID_H

        if open then
            local enabled = AnyEnabled()
            _, h = W:DualRow(parent, y,
                { type = "toggle", text = "Alert on This Ability",
                  tooltip = "Off keeps this ability silent: no defensive callout, no "
                  .. "reminder. On alerts every cast of it.",
                  getValue = function() return enabled end,
                  setValue = function(v)
                      for k = 1, #g.fps do SetAbilityEnabled(g.fps[k], v) end
                      EUI:RefreshPage(true)
                  end }
                -- Full width, matching Alert Type below: mixed half and full rows in one
                -- stack is what read as disjointed.
            ); y = y - h

            if enabled then
                local akey = tostring(encounterID) .. "#" .. disp
                local custom = ns.BossList(specID, akey, false)
                local r = ns.RemindersTable(false, encounterID)
                local function RawEntry()
                    if not r then return nil end
                    if r[disp] ~= nil then return r[disp] end
                    for k = 1, #g.fps do
                        if r[g.fps[k]] ~= nil then return r[g.fps[k]] end
                    end
                    return nil
                end
                local isCustom = RawEntry() ~= nil

                -- One alert type, never both, per the tester's design: Defensive picks
                -- from a priority list and names what to press; Custom says a line the
                -- player wrote instead. The mode is whether reminder state exists, so
                -- packs and exports carry it with no extra field.
                _, h = W:DualRow(parent, y,
                    { type = "dropdown", text = "Alert Type",
                      values = { defensive = "Defensive", custom = "Custom" },
                      order = { "defensive", "custom" },
                      tooltip = "Defensive calls the right cooldown from a priority "
                      .. "list. Custom says a line you write instead. One or the other, "
                      .. "never both.",
                      getValue = function() return isCustom and "custom" or "defensive" end,
                      setValue = function(v)
                          local rw = ns.RemindersTable(true, encounterID)
                          -- One entry per ability, keyed by name; any fingerprint keys
                          -- from before the grouping are folded in and cleared.
                          if v == "custom" then
                              rw[disp] = RawEntry() or true
                          else
                              rw[disp] = nil
                          end
                          for k = 1, #g.fps do rw[g.fps[k]] = nil end
                          if next(rw) == nil then
                              local db2 = ns.DB()
                              if type(db2.reminders) == "table" then
                                  db2.reminders[tostring(encounterID)] = nil
                              end
                          end
                          ns.RefreshRuntime()
                          EUI:RefreshPage(true)
                      end }
                    -- nil right config = full-width row in the factory, right for a
                    -- control that owns the whole decision.
                ); y = y - h

                if isCustom then
                    -- The custom line, edited IN PLACE, dressed as a table row: factory
                    -- row height and label metrics, faint row stripe, and the box in the
                    -- same well-and-border the callout editor's input wears -- so it sits
                    -- in the column like any defensives row instead of floating.
                    local ROW_H = 50
                    local rowF = CreateFrame("Frame", nil, parent)
                    rowF:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
                    rowF:SetSize(parent:GetWidth() > 0 and parent:GetWidth() or 600, ROW_H)
                    ns.Solid(rowF, "BACKGROUND", ns.THEME.line, 0.12):SetAllPoints()

                    local lbl = ns.Font(rowF, 14, nil)
                    lbl:SetPoint("LEFT", rowF, "LEFT", 20, 0)
                    lbl:SetText("Says")

                    local box = CreateFrame("EditBox", nil, rowF)
                    box:SetPoint("LEFT", rowF, "LEFT", 80, 0)
                    box:SetPoint("RIGHT", rowF, "RIGHT", -150, 0)
                    box:SetHeight(28)
                    box:SetAutoFocus(false)
                    box:SetMaxLetters(60)
                    box:SetFontObject("GameFontHighlight")
                    box:SetTextInsets(6, 6, 0, 0)
                    local well = ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1)
                    well:SetAllPoints()
                    ns.Border(box)
                    local raw = RawEntry()
                    box:SetText(type(raw) == "string" and raw or "")

                    local function SaveBox(self)
                        local v = self:GetText() or ""
                        local rw = ns.RemindersTable(true, encounterID)
                        rw[disp] = (v ~= "" and v) or true
                        for k = 1, #g.fps do rw[g.fps[k]] = nil end
                        ns.RefreshRuntime()
                    end
                    box:SetScript("OnEnterPressed", function(self)
                        SaveBox(self)
                        self:ClearFocus()
                        EUI:RefreshPage(true)
                    end)
                    box:SetScript("OnEditFocusLost", SaveBox)
                    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

                    -- Enter commits, and so does OK -- a visible commit for anyone who
                    -- does not trust an edit box that saves silently. Preview delivers
                    -- the line exactly as a fight would: shown over the alert, spoken.
                    local okBtn = ns.Button(rowF, "OK", 44, 24, function()
                        SaveBox(box)
                        box:ClearFocus()
                        EUI:RefreshPage(true)
                    end)
                    okBtn:SetPoint("RIGHT", rowF, "RIGHT", -86, 0)

                    local prevBtn = ns.Button(rowF, "Preview", 62, 24, function()
                        SaveBox(box)
                        if ns.PreviewReminderLine then
                            ns.PreviewReminderLine(box:GetText() or "")
                        end
                    end)
                    prevBtn:SetPoint("RIGHT", rowF, "RIGHT", -18, 0)
                    y = y - ROW_H
                else
                    _, h = W:DualRow(parent, y,
                        { type = "toggle", text = "Use My Spec Default",
                          tooltip = "On: this ability calls from your normal priority "
                          .. "list. Off: it gets its own copy of that list to reorder "
                          .. "or prune, shown below.",
                          getValue = function() return custom == nil end,
                          setValue = function(v)
                              if v then
                                  ns.ClearBossList(specID, akey)
                              else
                                  local src = ns.EffectiveListFor(specID, encounterID)
                                  if not (src and #src > 0) then
                                      -- EffectiveListFor does not fall through to the spec
                                      -- default when an encounterID is given (a boss with
                                      -- no override of its own reads as empty, not "use
                                      -- the default"), so ask for the default explicitly:
                                      -- the active preset's list, same as everywhere else.
                                      src = ns.EffectiveListFor(specID, nil)
                                  end
                                  local bl = ns.BossList(specID, akey, true)
                                  wipe(bl)
                                  if src then
                                      for k = 1, #src do bl[k] = src[k] end
                                  end
                              end
                              ns.RefreshRuntime()
                              EUI:RefreshPage(true)
                          end }
                    ); y = y - h

                    if custom ~= nil then
                        y = ns.RenderPriorityEditor(parent, y, W, EUI, specID, akey)
                    end
                end
            end
        end
    end

    -- Independent of the accordion above: these don't ride an existing timeline
    -- fingerprint at all, so a boss with nothing marked yet can still carry one.
    _, h = W:SectionHeader(parent, "CUSTOM REMINDERS", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "      Boss pulls, spell casts and auras -- separate from "
          .. "the tank-buster list above." },
        { type = "label", text = "" }
    ); y = y - h

    local crSet = ns.CustomRemindersTable and ns.CustomRemindersTable(false, encounterID)
    local crList = {}
    if crSet then
        for uid, r in pairs(crSet) do crList[#crList + 1] = { uid = uid, r = r } end
        table.sort(crList, function(a, b) return (a.r.name or "") < (b.r.name or "") end)
    end

    if #crList == 0 then
        _, h = W:DualRow(parent, y,
            { type = "label", text = "      None yet for this boss." },
            { type = "label", text = "" }
        ); y = y - h
    else
        for i = 1, #crList do
            local uid, r = crList[i].uid, crList[i].r
            local trigDesc = "?"
            if r.trigger and r.trigger.type == "pull" then
                trigDesc = "Pull"
            elseif r.trigger and r.trigger.type == "spell" then
                local info = C_Spell and C_Spell.GetSpellInfo
                    and C_Spell.GetSpellInfo(r.trigger.spellID)
                trigDesc = (r.trigger.kind == "aura" and "Aura: " or "Cast: ")
                    .. ((info and info.name) or tostring(r.trigger.spellID))
            end

            local row
            row, h = W:DualRow(parent, y,
                { type = "toggle",
                  text = ("      %s  |cff8a99b5(%s)|r"):format(r.name or "Reminder", trigDesc),
                  tooltip = "Untick to keep this reminder without deleting it.",
                  getValue = function() return r.enabled ~= false end,
                  setValue = function(v)
                      r.enabled = v
                      ns.RefreshRuntime()
                  end },
                { type = "label", text = "" }
            ); y = y - h
            if row then
                AttachInline(row._rightRegion, "Edit", 46, function()
                    ns.ShowCustomReminderEditor(encounterID, uid)
                end, "Edit", "Change this reminder's trigger, message or how long it lingers.")
                AttachInline(row._rightRegion, "Delete", 56, function()
                    local writeSet = ns.CustomRemindersTable(false, encounterID)
                    if writeSet then writeSet[uid] = nil end
                    ns.RefreshRuntime()
                    EUI:RefreshPage(true)
                end, "Delete", "Removes this reminder.")
            end
        end
    end

    _, h = W:Button(parent, "+ Add a Custom Reminder", y, function()
        ns.ShowCustomReminderEditor(encounterID, nil)
    end)
    y = y - h

    return y
end

-------------------------------------------------------------------------------
--  Custom reminder editor: name, message, trigger, linger
-------------------------------------------------------------------------------
local TRIGGER_CHOICES = { pull = "Boss Pull", cast = "Spell Cast", aura = "Spell Aura Applied" }
local TRIGGER_ORDER = { "pull", "cast", "aura" }

local function TriggerKindOf(trig)
    if not trig or trig.type == "pull" then return "pull" end
    return trig.kind == "aura" and "aura" or "cast"
end

-- Rebuilt fresh on every open, same as the instance/boss modal above: an occasional
-- settings dialog is not worth the bookkeeping a cached singleton would need for a
-- dropdown and text fields that all close over a different encounter/uid each time.
function ns.ShowCustomReminderEditor(encounterID, uid)
    local EUI = _G.EllesmereUI
    local W = EUI.Widgets

    local dimmer, panel = ns.MakeModal(440, 480)
    dimmer:SetFrameStrata("TOOLTIP")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(uid and "Edit Reminder" or "New Reminder")

    local set = ns.CustomRemindersTable(false, encounterID)
    local existing = (set and uid) and set[uid] or nil
    local trig = (existing and existing.trigger) or { type = "pull" }

    local y = -46
    local PAD = 20

    local function AddLabel(text)
        local l = ns.Font(panel, 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        l:SetText(text)
        y = y - 16
    end

    local function AddBox(maxLetters, numeric)
        local box = CreateFrame("EditBox", nil, panel)
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        box:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
        box:SetHeight(26)
        box:SetAutoFocus(false)
        box:SetMaxLetters(maxLetters or 60)
        if numeric then box:SetNumeric(true) end
        box:SetFontObject("GameFontHighlight")
        box:SetTextInsets(6, 6, 0, 0)
        ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
        ns.Border(box)
        y = y - 32
        return box
    end

    AddLabel("Name")
    local nameBox = AddBox(40)
    nameBox:SetText((existing and existing.name) or "")

    AddLabel("Message (shown on screen)")
    local msgBox = AddBox(120)
    msgBox:SetText((existing and existing.msg) or "")

    -- Forward-declared: the dropdown's setValue below closes over this, but the fields it
    -- syncs (spellBox, spellFeedback) do not exist until after the dropdown row is built,
    -- since the row's own Y position sits above them. The assignment happens later in this
    -- same call, well before the dropdown is ever interactive.
    local SyncSpellRow

    local trigVal = TriggerKindOf(trig)
    local _, rowH = W:DualRow(panel, y,
        { type = "dropdown", text = "Trigger",
          values = TRIGGER_CHOICES, order = TRIGGER_ORDER,
          tooltip = "What starts this reminder.",
          getValue = function() return trigVal end,
          setValue = function(v)
              trigVal = v
              if SyncSpellRow then SyncSpellRow() end
          end },
        { type = "label", text = "" }
    ); y = y - rowH

    AddLabel("Spell ID (cast/aura triggers only)")
    local spellBox = AddBox(9, true)
    spellBox:SetText((trig.type == "spell" and trig.spellID) and tostring(trig.spellID) or "")
    local spellFeedback = ns.Font(panel, 10, nil, ns.THEME.muted)
    spellFeedback:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y + 6)
    spellFeedback:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
    spellFeedback:SetJustifyH("LEFT")
    y = y - 14

    SyncSpellRow = function()
        if trigVal == "pull" then
            spellFeedback:SetText("|cff8a99b5not used for a pull trigger|r")
            return
        end
        local sid, info = ns.ResolveSpell(spellBox:GetText())
        if sid then
            spellFeedback:SetText("|cff6DD09A" .. (info.name or "") .. "|r")
        else
            spellFeedback:SetText(
                (spellBox:GetText() ~= "" and "|cffff6060not a spell ID|r") or "")
        end
    end
    spellBox:SetScript("OnTextChanged", SyncSpellRow)
    SyncSpellRow()

    AddLabel("Fire on occurrence # (blank = every time)")
    local counterBox = AddBox(3, true)
    counterBox:SetText((trig.counter and trig.counter > 1) and tostring(trig.counter) or "")

    AddLabel("Linger (seconds)")
    local durBox = AddBox(3, true)
    durBox:SetText(tostring((existing and existing.dur) or 3))

    local enabledVal = (existing == nil) or existing.enabled ~= false
    local _, rowH2 = W:DualRow(panel, y,
        { type = "toggle", text = "Enabled",
          getValue = function() return enabledVal end,
          setValue = function(v) enabledVal = v end },
        { type = "label", text = "" }
    ); y = y - rowH2

    local function BuildTrigger()
        if trigVal == "pull" then return { type = "pull" } end
        local sid = ns.ResolveSpell(spellBox:GetText())
        if not sid then return nil end
        local counter = tonumber(counterBox:GetText())
        return { type = "spell", kind = trigVal, spellID = sid,
                 counter = (counter and counter > 1) and math.floor(counter) or nil }
    end

    local function Save()
        local newTrig = BuildTrigger()
        if not newTrig then
            ns.Print("|cffff6060need a valid spell ID for this trigger|r")
            return
        end
        local name = nameBox:GetText()
        if not name or name == "" then name = "Reminder" end
        local dur = tonumber(durBox:GetText()) or 3
        local writeSet = ns.CustomRemindersTable(true, encounterID)
        local key = uid or ("r" .. math.floor(GetTime() * 1000) .. math.random(1, 9999))
        writeSet[key] = {
            name = name, msg = msgBox:GetText() or "", trigger = newTrig,
            dur = math.max(1, dur), enabled = enabledVal,
        }
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end

    y = y - 10
    ns.Button(panel, "Preview", 90, 26, function()
        ns.PreviewCustomReminder({
            name = nameBox:GetText(), msg = msgBox:GetText(),
            dur = tonumber(durBox:GetText()) or 3,
        })
    end):SetPoint("BOTTOM", panel, "BOTTOM", -110, 16)
    ns.Button(panel, "Save", 90, 26, Save):SetPoint("BOTTOM", panel, "BOTTOM", -10, 16)
    ns.Button(panel, "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 90, 16)

    dimmer:Show()
end

function ns.BuildTreeSection(parent, y)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local _, h
    local specID = ns.CurrentSpec()
    local db = ns.DB()

    _, h = W:SectionHeader(parent, "REMINDER PACKS", y); y = y - h
    local packRow
    packRow, h = W:DualRow(parent, y,
        { type = "label", text = "      Share your lists, marks and reminders as one string." },
        { type = "label", text = "" }
    ); y = y - h
    if packRow then
        AttachInline(packRow._rightRegion or packRow, "Export", 60, function()
            if ns.ShowPackExport then ns.ShowPackExport() end
        end, "Export a Reminder Pack",
        "Everything a curator sets up -- priority lists, per-boss orders, callouts, marks, "
        .. "mutes and written reminders -- as one string to share.")
    end
    local packRow2
    packRow2, h = W:DualRow(parent, y,
        { type = "label", text = "      Install a curator's pack, with a preview first." },
        { type = "label", text = "" }
    ); y = y - h
    if packRow2 then
        AttachInline(packRow2._rightRegion or packRow2, "Import", 60, function()
            if ns.ShowPackImport then ns.ShowPackImport() end
        end, "Import a Reminder Pack",
        "Paste a pack string. Nothing applies until you choose Replace or Merge, and a "
        .. "damaged string is refused outright.")
    end

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

    -- The toggle is the instance's ON/OFF switch -- it writes the per-boss switches in
    -- bulk, so the two views can never disagree -- and the cog in its gutter is what opens
    -- the options modal. The toggle used to open the modal itself, which made switching a
    -- dungeon off impossible and opening it feel like a mis-click.
    local function InstanceSlot(inst)
        if not inst then return { type = "label", text = "" } end
        return { type = "toggle",
            text = inst.name,
            tooltip = ("Callouts for this %s, all %d bosses at once. Single bosses can still "
                .. "be switched inside the cog."):format(
                inst.isRaid and "raid" or "dungeon", #inst.bosses),
            getValue = function()
                local off = ns.DB().bossOff
                if not off then return true end
                for b = 1, #inst.bosses do
                    local eid = inst.bosses[b].encounterID
                    if eid and not off[tostring(eid)] then return true end
                end
                return #inst.bosses == 0
            end,
            setValue = function(v)
                local db = ns.DB()
                if type(db.bossOff) ~= "table" then db.bossOff = {} end
                for b = 1, #inst.bosses do
                    local eid = inst.bosses[b].encounterID
                    if eid then db.bossOff[tostring(eid)] = (not v) or nil end
                end
                if next(db.bossOff) == nil then db.bossOff = nil end
                ns.RefreshRuntime()
                EUI:RefreshPage(true)
            end }
    end

    -- The house cog: dim until hovered, sitting in the gutter between the checkbox and
    -- the instance name, same art as every other cog in the suite.
    local function AttachCog(rgn, inst)
        if not (rgn and inst) then return end
        local cog = CreateFrame("Button", nil, rgn)
        -- The suite's cog VERBATIM, anchor included: 26px, dim 0.4 resting, 0.7 hovered,
        -- COGS_ICON art, sitting immediately LEFT OF THE TOGGLE PILL -- the same spot
        -- every other cog in EllesmereUI occupies. The first two attempts parked it at
        -- the row's far left, where a gray icon reads as a second, broken checkbox.
        cog:SetSize(26, 26)
        cog:SetPoint("RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -8, 0)
        rgn._lastInline = cog
        cog:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cog:SetAlpha(0.4)
        local tex = cog:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        local EUIg = _G.EllesmereUI
        if EUIg and EUIg.COGS_ICON then
            tex:SetTexture(EUIg.COGS_ICON)
        else
            tex:SetTexture("Interface" .. string.char(92) .. "Buttons"
                .. string.char(92) .. "UI-OptionsButton")
        end
        cog:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            if EUIg and EUIg.ShowWidgetTooltip then
                EUIg.ShowWidgetTooltip(self, "Bosses, reminders and lists for " .. inst.name)
            end
        end)
        cog:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
        end)
        cog:SetScript("OnClick", function()
            ns.ShowInstanceModal(inst, specID, EUI, W)
        end)
    end

    local rows = math.max(#dungeons, #raids)
    for i = 1, rows do
        local d, r = dungeons[i], raids[i]
        local instRow
        instRow, h = W:DualRow(parent, y, InstanceSlot(d), InstanceSlot(r)); y = y - h
        if instRow then
            AttachCog(instRow._leftRegion, d)
            AttachCog(instRow._rightRegion, r)
        end
    end

    return y
end

-- One dungeon or raid, every boss expanded, in its own scrollable modal. The widget
-- factory renders into whatever parent it is handed, so the same row builders that drew
-- the inline tree draw the modal body. Edits inside the rows refresh the options PAGE by
-- calling EUI:RefreshPage -- the proxy below intercepts that so the modal body re-renders
-- in the same breath and never shows stale state.
function ns.ShowInstanceModal(inst, specID, EUI, W)
    local dimmer, panel = ns.MakeModal(660, 540)
    local MIN_H, MAX_H, CHROME = 220, 540, 96

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -40)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 52)

    local content
    local proxy
    local selected = 1
    local Render
    local RenderBody
    -- Accordion and per-ability state, keyed by encounter, surviving re-renders.
    local uiState = {}

    -- The boss picker lives in the header's top-right corner, out of the body. A styled
    -- button opening the client's own context menu: the row factory only builds dropdowns
    -- inside rows, and a body row for navigation was the complaint.
    local pick = ns.Button(panel, "Select Boss", 130, 22, function()
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(panel, function(_, root)
                for b = 1, #inst.bosses do
                    local idx = b
                    root:CreateButton(inst.bosses[b].name, function()
                        selected = idx
                        Render()
                    end)
                end
            end)
        else
            -- No menu API: the button cycles instead of dropping down.
            selected = (selected % #inst.bosses) + 1
            Render()
        end
    end)
    pick:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -12)

    -- The body is pcall'd and failures PRINT. Two rounds of this modal silently eating
    -- its own content taught the lesson: a UI that can fail must say where.
    function Render()
        local ok, err = pcall(RenderBody)
        if not ok then
            ns.Print("|cffff6060boss window failed to draw|r: " .. tostring(err))
        end
    end

    function RenderBody()
        -- A fresh body per render: rows cannot be unbuilt individually, and edits are
        -- rare enough that replacing the child frame outright stays cheap.
        if content then content:Hide() end
        content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(600)
        scroll:SetScrollChild(content)

        local yy = -4
        local boss = inst.bosses[selected] or inst.bosses[1]
        title:SetText(("%s  |cffF0A830%s|r"):format(inst.name, boss and boss.name or ""))

        if boss then
            yy = RenderBoss(content, yy, W, proxy, inst, boss, specID, uiState)
        end
        content:SetHeight(-yy + 20)
        -- The window fits its boss: a three-row boss gets a compact dialog, a packed one
        -- caps at the old height and scrolls.
        local panelH = math.max(MIN_H, math.min(MAX_H, (-yy + 20) + CHROME))
        panel:SetHeight(panelH)
        -- The template's scrollbar is always-visible by default, which reads as broken
        -- next to a window that just sized itself to need no scrolling.
        local bar = scroll.ScrollBar
        if bar then bar:SetShown((-yy + 20) > (panelH - CHROME)) end
    end

    proxy = setmetatable({
        RefreshPage = function(_, force)
            EUI:RefreshPage(force)
            Render()
        end,
    }, { __index = EUI })

    ns.Button(panel, "Close", 110, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)

    Render()
    dimmer:Show()
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
