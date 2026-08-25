-------------------------------------------------------------------------------
--  NaowhUI_TankReminder_Bosses.lua -- browse this season's bosses and every ability the
--  journal lists for them, labelled by who each one is aimed at.
--
--  Every name, icon and tank marking is read out of the player's own client at runtime,
--  so it cannot go stale, it covers whatever season the client is on, and the addon
--  carries no encounter knowledge of its own. The one exception: when
--  NaowhUI_SmartReminders_CuratedAbilities.lua has an entry for the boss, its abilities
--  are filtered and grouped by that shipped phase list instead of showing everything the
--  journal has; see that file for why.
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
-- Instance expansion state used to live here; instances render inline via
-- BuildBossListPage/RenderInstanceDetail now, not a modal.

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

-- Frames are never garbage collected, so a dialog built from plain frames is built once and
-- re-pointed on each open, with the per-open values held in a state table the widgets read
-- rather than captured directly. Dialogs built from EllesmereUI's widget factory cannot do
-- this -- see ShowAbilitySettingsPopup below for why.
--
-- Add and Rename are the same dialog: a name, a confirm and a cancel.
local namePrompt

local function ShowNamePrompt(title, confirmLabel, initial, onCommit)
    if not namePrompt then
        local dimmer, panel = ns.MakeModal(340, 150)
        local np = { dimmer = dimmer }

        np.head = ns.Font(panel, 14, "OUTLINE")
        np.head:SetPoint("TOP", panel, "TOP", 0, -16)

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
        np.box = box

        local function Commit()
            local fn = np.onCommit
            dimmer:Hide()
            if fn then fn(box:GetText()) end
        end
        box:SetScript("OnEnterPressed", Commit)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); dimmer:Hide() end)

        np.confirm = ns.Button(panel, "Save", 90, 26, Commit)
        np.confirm:SetPoint("BOTTOM", panel, "BOTTOM", -50, 16)
        ns.Button(panel, "Cancel", 90, 26, function() dimmer:Hide() end)
            :SetPoint("BOTTOM", panel, "BOTTOM", 50, 16)

        namePrompt = np
    end

    local np = namePrompt
    np.onCommit = onCommit
    np.head:SetText(title)
    ns.SetButtonText(np.confirm, confirmLabel)
    np.box:SetText(initial or "")
    np.dimmer:Show()
    np.box:SetFocus()
    np.box:HighlightText()
end

local function ShowAddPresetPopup(specID, EUI)
    ShowNamePrompt("New Preset", "Create", ns.NextPresetName(specID), function(text)
        ns.AddPreset(specID, text)
        EUI:RefreshPage(true)
    end)
end

local function ShowRenamePresetPopup(specID, presetKey, currentName, EUI)
    ShowNamePrompt("Rename Preset", "Save", currentName or "", function(text)
        ns.RenamePreset(specID, presetKey, text)
        EUI:RefreshPage(true)
    end)
end

-- Audio settings for one ability. The cog is designed to grow -- text options and whatever
-- else makes sense later -- so its content lives in its own small modal rather than crowding
-- the row.
local function ShowAbilitySettingsPopup(specID, spellID, name, EUI)
    local W = EUI.Widgets
    local dimmer, panel = ns.MakeModal(360, 130)

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(name)

    local editBtn, placeClose
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
              if placeClose then placeClose() end
          end }
    ); y = y - h

    editBtn = ns.Button(panel, "Edit Callout", 120, 26, function()
        ns.ShowCalloutEditor(("Audio callout for %s"):format(name),
            ns.CalloutFor(spellID, name), function(text)
                ns.SetCallout(spellID, text)
                if EUI.RefreshPage then EUI:RefreshPage(true) end
            end, spellID)
    end)
    editBtn:SetPoint("BOTTOM", panel, "BOTTOM", -55, 16)
    editBtn:SetShown(not ns.IsAudioOff(spellID))

    local closeBtn = ns.Button(panel, "Close", 90, 26, function() dimmer:Hide() end)
    placeClose = function()
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("BOTTOM", panel, "BOTTOM", editBtn:IsShown() and 65 or 0, 16)
    end
    placeClose()

    dimmer:Show()
end

-- Same shape as the ability popup above, but the fallback step stores its audio flag under
-- spellID 0 and its text directly on db.voiceNone rather than through the callout table, so
-- it cannot share ShowAbilitySettingsPopup's storage calls.
local function ShowFallbackSettingsPopup(EUI)
    local W = EUI.Widgets
    local db = ns.DB()
    local dimmer, panel = ns.MakeModal(360, 130)

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("Call for an External")

    local editBtn, placeClose
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
              if placeClose then placeClose() end
          end }
    ); y = y - h

    editBtn = ns.Button(panel, "Edit Callout", 120, 26, function()
        ns.ShowCalloutEditor("Said and shown when nothing on the list is up",
            db.voiceNone, function(v)
                db.voiceNone = v
                ns.RefreshRuntime()
            end, 0)
    end)
    editBtn:SetPoint("BOTTOM", panel, "BOTTOM", -55, 16)
    editBtn:SetShown(db.fallbackOn ~= false and not ns.IsAudioOff(0))

    local closeBtn = ns.Button(panel, "Close", 90, 26, function() dimmer:Hide() end)
    placeClose = function()
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("BOTTOM", panel, "BOTTOM", editBtn:IsShown() and 65 or 0, 16)
    end
    placeClose()

    dimmer:Show()
end

-- A left-column entry: click to switch presets, pencil to rename, x to delete. Hand-drawn
-- rather than a DualRow toggle since it needs the active highlight and the rename/delete
-- affordances a checkbox row does not have.
local function BuildPresetRow(leftPane, ly, rowW, rowH, specID, p, isActive, canDelete, EUI)
    local prow = CreateFrame("Button", nil, leftPane)
    prow:SetSize(rowW, rowH)
    prow:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, ly)

    if isActive then
        local bg = ns.Solid(prow, "BACKGROUND", ns.THEME.grey, 0.55)
        bg:SetAllPoints()
    end

    local lbl = ns.Font(prow, 13, nil, isActive and ns.THEME.blue or ns.THEME.muted)
    lbl:SetPoint("LEFT", prow, "LEFT", 8, 0)
    lbl:SetPoint("RIGHT", prow, "RIGHT", canDelete and -56 or -34, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetText(p.name)

    prow:SetScript("OnClick", function()
        ns.SelectPreset(specID, p.key)
        EUI:RefreshPage(true)
    end)

    local edit = ns.Font(prow, 11, nil, ns.THEME.muted)
    edit:SetText("Edit")
    local editHit = CreateFrame("Button", nil, prow)
    editHit:SetSize(28, rowH)
    if canDelete then
        editHit:SetPoint("RIGHT", prow, "RIGHT", -26, 0)
    else
        editHit:SetPoint("RIGHT", prow, "RIGHT", -6, 0)
    end
    edit:SetPoint("CENTER", editHit, "CENTER", 0, 0)
    editHit:SetScript("OnEnter", function(self)
        local c = ns.THEME.blue
        edit:SetTextColor(c.r, c.g, c.b, 1)
        local EUIg = _G.EllesmereUI
        if EUIg and EUIg.ShowWidgetTooltip then
            EUIg.ShowWidgetTooltip(self, "Rename this preset.")
        end
    end)
    editHit:SetScript("OnLeave", function()
        local c = ns.THEME.muted
        edit:SetTextColor(c.r, c.g, c.b, 1)
        local EUIg = _G.EllesmereUI
        if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
    end)
    editHit:SetScript("OnClick", function() ShowRenamePresetPopup(specID, p.key, p.name, EUI) end)

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
-- -- on the right. Per-boss overrides go through RenderInstanceDetail/RenderAbilityRow, keyed
-- by spell id rather than a priority list.
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

-- The whole boss's own hierarchy, top part: Enable This Boss (off = nothing below, no
-- alerts of any kind), then which of the spec's presets it calls its defensives from.
-- Used by RenderInstanceDetail, the journal-sourced ability list.
-- Returns y, bossOn.
local function RenderBossHeader(parent, y, W, EUI, encounterID, specID)
    local _, h
    local db = ns.DB()

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

    if not bossOn then return y, false end

    -- Which of the spec's presets this boss calls its defensives from. Shows the spec's
    -- active preset until the tank actually picks one for this boss -- nothing is written
    -- just from opening the modal and looking at it.
    local presets = ns.ListPresets(specID)
    if #presets > 0 then
        local presetValues, presetOrder = {}, {}
        for i = 1, #presets do
            presetValues[presets[i].key] = presets[i].name
            presetOrder[i] = presets[i].key
        end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Defensive Preset",
              values = presetValues, order = presetOrder,
              tooltip = "Which of your spec's presets this boss calls its defensives from.",
              getValue = function()
                  return ns.BossPresetKey(specID, encounterID) or ns.ActivePresetKey(specID)
              end,
              setValue = function(v)
                  ns.SetBossPreset(specID, encounterID, v)
                  ns.RefreshRuntime()
                  EUI:RefreshPage(true)
              end }
        ); y = y - h
    end

    return y, true
end

-------------------------------------------------------------------------------
--  Custom reminder editor: name, message, trigger, linger
-------------------------------------------------------------------------------
local TRIGGER_CHOICES = { pull = "Boss Pull", bwmsg = "BigWigs/DBM Message",
    bwtimer = "BigWigs/DBM Timer", aura = "Aura Applied" }
local TRIGGER_ORDER = { "pull", "bwmsg", "bwtimer", "aura" }

local SHOW_IN_TIP = "Blank fires immediately. A number is seconds; minute format works "
    .. "too (1:30.5 = 90.5 seconds). Separate several with a comma to fire more than once."
local COUNTER_TIP = "Blank fires every time. Match a count with >N, >=N, <N, <=N, !N (not "
    .. "N) or a bare number (exactly N). Separate conditions with a comma to match any of "
    .. "them, or add a leading + on the second one to require both -- example: >3,+<7 "
    .. "fires between 4 and 6."

-- Rebuilt fresh on every open: an occasional settings dialog is not worth the bookkeeping
-- a cached singleton would need for a dropdown and text fields that all close over a
-- different encounter/uid each time.
-- callerEUI, when given, is a caller's own EUI proxy (e.g. the ability picker's) -- its
-- RefreshPage also re-renders that caller, not just the real options page, which is what
-- actually makes a saved/edited reminder show up in its list without a reopen.
-- Icon + display name for a catalogued BigWigs/DBM key. Positive keys are almost always
-- real spell ids; negative ones are BigWigs' own convention for "this is really a
-- Dungeon Journal section", the same -sectionID scheme its own options panel uses. Both
-- routes read Blizzard's plain data (C_Spell / C_EncounterJournal) -- nothing here reads
-- anything of BigWigs' or DBM's own beyond the bare key and label they already broadcast.
local function ResolveMechanicIcon(key)
    if key > 0 then
        return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(key)
    elseif C_EncounterJournal and C_EncounterJournal.GetSectionInfo then
        local ok, info = pcall(C_EncounterJournal.GetSectionInfo, -key)
        return ok and info and info.abilityIcon or nil
    end
end

local function ResolveMechanicName(key, entry)
    if key > 0 then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(key)
        if info and info.name then return info.name end
    end
    -- The boss mod's own message/bar text as a fallback: it is not always a real spell
    -- (a negative journal key, or an arbitrary internal id some modules use), and that
    -- text is still the clearest label available for it.
    if type(entry.text) == "string" and entry.text ~= "" then return entry.text end
    return "Key " .. tostring(key)
end

-- Capped rather than scrolled: this addon has no scroll-frame primitive of its own, and a
-- boss with more than a handful of distinct mechanics is rare enough that "seen most
-- often, plus a manual fallback" covers the real case without building one just for this.
-- Never a silent cap -- MECHANIC_PICKER_ROWS worth show, and a hint discloses the rest.
local MECHANIC_PICKER_ROWS = 8

function ns.ShowCustomReminderEditor(encounterID, uid, callerEUI)
    local EUI = callerEUI or _G.EllesmereUI
    local W = EUI.Widgets

    local dimmer, panel = ns.MakeModal(480, 620)

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(uid and "Edit Reminder" or "New Reminder")

    local set = ns.CustomRemindersTable(false, encounterID)
    local existing = (set and uid) and set[uid] or nil
    local trig = (existing and existing.trigger) or { type = "pull" }

    local PAD = 20

    local function HoverTip(hit, tooltip)
        hit:SetScript("OnEnter", function(self)
            local EUIg = _G.EllesmereUI
            if EUIg and EUIg.ShowWidgetTooltip then EUIg.ShowWidgetTooltip(self, tooltip) end
        end)
        hit:SetScript("OnLeave", function()
            local EUIg = _G.EllesmereUI
            if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
        end)
    end

    -------------------------------------------------------------------------
    --  Tabs -- BigWigs' own per-ability panel splits "which mechanic, what
    --  fires it" from "how it's shown"; this splits Trigger from Message
    --  the same way, over our own fields rather than theirs.
    -------------------------------------------------------------------------
    local TAB_TOP = -40
    local BODY_TOP = TAB_TOP - 30

    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP)
    tabBar:SetHeight(24)

    local tabDivider = ns.Solid(panel, "ARTWORK", ns.THEME.line, 1)
    tabDivider:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, BODY_TOP + 6)
    tabDivider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, BODY_TOP + 6)
    tabDivider:SetHeight(1)

    local tabButtons, tabBodies = {}, {}

    local function SelectTab(id)
        for tid, btn in pairs(tabButtons) do
            local on = (tid == id)
            btn.marker:SetShown(on)
            local c = on and ns.THEME.fg or ns.THEME.muted
            btn.label:SetTextColor(c.r, c.g, c.b, 1)
        end
        for tid, body in pairs(tabBodies) do
            body:SetShown(tid == id)
        end
    end

    local function AddTab(id, text, anchorTo)
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(24)
        local lbl = ns.Font(btn, 12, nil, ns.THEME.muted)
        lbl:SetText(text)
        btn:SetSize(lbl:GetStringWidth() + 4, 24)
        lbl:SetPoint("CENTER")
        if anchorTo then
            btn:SetPoint("LEFT", anchorTo, "RIGHT", 18, 0)
        else
            btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
        end
        local marker = ns.Solid(btn, "OVERLAY", ns.THEME.gold, 1)
        marker:SetPoint("BOTTOMLEFT", 0, -3)
        marker:SetPoint("BOTTOMRIGHT", 0, -3)
        marker:SetHeight(2)
        marker:Hide()
        btn:SetScript("OnClick", function() SelectTab(id) end)
        btn.label, btn.marker = lbl, marker
        tabButtons[id] = btn

        local body = CreateFrame("Frame", nil, panel)
        body:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, BODY_TOP)
        body:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, BODY_TOP)
        body:SetHeight(-BODY_TOP - 60)
        tabBodies[id] = body
        return btn, body
    end

    local triggerTabBtn, triggerBody = AddTab("trigger", "Trigger")
    local _, messageBody = AddTab("message", "Message", triggerTabBtn)

    -------------------------------------------------------------------------
    --  Message tab: name, preset, linger, enabled. Same fields as before,
    --  just parented to their own tab instead of stacked under everything.
    -------------------------------------------------------------------------
    local my = 0

    local function AddLabelM(text, tooltip)
        local l = ns.Font(messageBody, 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", messageBody, "TOPLEFT", PAD, my)
        l:SetText(text)
        if tooltip then
            local hit = CreateFrame("Frame", nil, messageBody)
            hit:SetPoint("TOPLEFT", l, "TOPLEFT", -4, 4)
            hit:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 4, -4)
            HoverTip(hit, tooltip)
        end
        my = my - 16
    end

    local function AddBoxM(maxLetters, numeric, rightInset)
        local box = CreateFrame("EditBox", nil, messageBody)
        box:SetPoint("TOPLEFT", messageBody, "TOPLEFT", PAD, my)
        box:SetPoint("RIGHT", messageBody, "RIGHT", -(rightInset or PAD), 0)
        box:SetHeight(26)
        box:SetAutoFocus(false)
        box:SetMaxLetters(maxLetters or 60)
        if numeric then box:SetNumeric(true) end
        box:SetFontObject("GameFontHighlight")
        box:SetTextInsets(6, 6, 0, 0)
        ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
        ns.Border(box)
        my = my - 32
        return box
    end

    AddLabelM("Name")
    local nameBox = AddBoxM(40)
    nameBox:SetText((existing and existing.name) or "")

    -- A preset rather than a typed line: the reminder announces whichever defensive in that
    -- preset is actually still up when it fires. Free text could only ever name a fixed
    -- spell, which is wrong the moment that spell is on cooldown -- the reason these are
    -- called smart reminders at all.
    local editorSpecID = ns.CurrentSpec()
    if #ns.ListPresets(editorSpecID) == 0 then
        ns.AddPreset(editorSpecID, "Default")
    end
    local presets = ns.ListPresets(editorSpecID)
    local presetValues, presetOrder = {}, {}
    for i = 1, #presets do
        presetValues[presets[i].key] = presets[i].name
        presetOrder[i] = presets[i].key
    end

    local presetVal = (existing and existing.preset) or ns.ActivePresetKey(editorSpecID)
        or presetOrder[1]

    local _, presetRowH = W:DualRow(messageBody, my,
        { type = "dropdown", text = "Preset Group",
          values = presetValues, order = presetOrder,
          tooltip = "Which of your spec's presets this reminder calls from. When it fires "
              .. "it names the highest defensive on that list still off cooldown.",
          getValue = function() return presetVal end,
          setValue = function(v) presetVal = v end },
        { type = "label", text = "" }
    ); my = my - presetRowH

    -- Icon/Color/Sound: same three fields ns.ShowAbilityReminderPicker's custom mode
    -- already has, added here too -- this editor is the only place a bwtimer trigger (the
    -- one with a real duration behind it) can be configured, so it needs the same reach.
    AddLabelM("Icon Spell ID (optional)")
    local iconBox = AddBoxM(9, true, PAD + 34)
    local iconPreview = messageBody:CreateTexture(nil, "ARTWORK")
    iconPreview:SetSize(24, 24)
    iconPreview:SetPoint("LEFT", iconBox, "RIGHT", 6, 0)
    iconPreview:Hide()
    local iconFeedback = ns.Font(messageBody, 10, nil, ns.THEME.muted)
    iconFeedback:SetPoint("TOPLEFT", messageBody, "TOPLEFT", PAD, my)
    iconFeedback:SetPoint("RIGHT", messageBody, "RIGHT", -PAD, 0)
    iconFeedback:SetJustifyH("LEFT")
    my = my - 14
    local function SyncIconM()
        local sid, info = ns.ResolveSpell(iconBox:GetText())
        if sid then
            local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
            if tex then iconPreview:SetTexture(tex); iconPreview:Show()
            else iconPreview:Hide() end
            iconFeedback:SetText("|cff6DD09A" .. ((info and info.name) or "") .. "|r")
        elseif iconBox:GetText() == "" then
            iconPreview:Hide()
            iconFeedback:SetText("")
        else
            iconPreview:Hide()
            iconFeedback:SetText("|cffff6060not a spell id|r")
        end
    end
    iconBox:SetScript("OnTextChanged", SyncIconM)
    iconBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    iconBox:SetText((existing and existing.iconSpellID and tostring(existing.iconSpellID)) or "")
    SyncIconM()

    local existingColor = existing and existing.color
    local pendingColor = { r = (existingColor and existingColor.r) or 1,
        g = (existingColor and existingColor.g) or 1, b = (existingColor and existingColor.b) or 1,
        a = (existingColor and existingColor.a) or 1 }
    local _, colorRowH = W:DualRow(messageBody, my,
        { type = "colorpicker", text = "Text Color", hasAlpha = false,
          tooltip = "This reminder's text color.",
          getValue = function() return pendingColor.r, pendingColor.g, pendingColor.b,
              pendingColor.a end,
          setValue = function(r, g, b, a) pendingColor = { r = r, g = g, b = b, a = a } end },
        { type = "label", text = "" }
    ); my = my - colorRowH

    local pendingSoundKey = (existing and existing.sound) or "none"
    local soundPaths, soundNames, soundOrder = EUI.BuildAlertSoundTables()
    if EUI.AppendSharedMediaSounds then EUI.AppendSharedMediaSounds(soundPaths, soundNames, soundOrder) end
    local _, soundRowH = W:DualRow(messageBody, my,
        { type = "dropdown", text = "Sound", values = soundNames, order = soundOrder,
          tooltip = "Plays once when this reminder fires.",
          getValue = function() return pendingSoundKey end,
          setValue = function(v)
              pendingSoundKey = v
              if EUI._PlayLSMSound and soundPaths[v] then EUI._PlayLSMSound(soundPaths[v]) end
          end },
        { type = "label", text = "" }
    ); my = my - soundRowH

    AddLabelM("Linger (seconds)")
    local durBox = AddBoxM(3, true)
    durBox:SetText(tostring((existing and existing.dur) or 3))

    local enabledVal = (existing == nil) or existing.enabled ~= false
    W:DualRow(messageBody, my,
        { type = "toggle", text = "Enabled",
          getValue = function() return enabledVal end,
          setValue = function(v) enabledVal = v end },
        { type = "label", text = "" }
    )

    -------------------------------------------------------------------------
    --  Trigger tab: type, mechanic picker, dynamic fields.
    -------------------------------------------------------------------------
    -- Seeded once from the trigger being edited; an older cast/aura reminder (the editor
    -- no longer creates these, but existing ones still run -- see EffectiveList) maps its
    -- spell id across into a BigWigs/DBM Message trigger as the closest equivalent, so
    -- re-editing it is a starting point rather than a dead end.
    local trigVal
    if trig.type == "bwtimer" then trigVal = "bwtimer"
    elseif trig.type == "aura" then trigVal = "aura"
    elseif trig.type == "bwmsg" or trig.type == "spell" then trigVal = "bwmsg"
    else trigVal = "pull" end

    local spellIDText = (trig.spellID and tostring(trig.spellID)) or ""
    local counterText = (type(trig.counter) == "string" and trig.counter)
        or (type(trig.counter) == "number" and tostring(trig.counter)) or ""
    local timeleftText = (trig.timeleft and tostring(trig.timeleft)) or ""
    local delayText = (type(trig.delay) == "string" and trig.delay) or ""
    -- Dropdown values, not text -- their widgets write straight into these on selection,
    -- so unlike the *Text fields there is no separate save-back step before a rebuild.
    local targetVal = (trig.target == "player") and "player" or "boss"
    local auraEventVal = (trig.auraEvent == "removed") and "removed" or "applied"

    -- The dynamic block below the Trigger dropdown -- which fields it holds depends on
    -- trigVal, so it is torn down and rebuilt on every change rather than show/hidden in
    -- place. The current widgets (nil for whichever fields the active type does not use)
    -- are read back into the *Text locals before a rebuild so switching types and back
    -- does not lose what was typed.
    local dynFrame, spellBox, counterBox, timeleftBox, delayBox
    local DYN_Y   -- set below, once the Trigger dropdown row's height is known
    local RebuildDynFields
    local triggerRow -- the Trigger dropdown's own row handle, so a picker pick can refresh its label

    local function SaveDynFieldsToText()
        if spellBox then spellIDText = spellBox:GetText() or "" end
        if counterBox then counterText = counterBox:GetText() or "" end
        if timeleftBox then timeleftText = timeleftBox:GetText() or "" end
        if delayBox then delayText = delayBox:GetText() or "" end
    end

    -- Public entry point for the picker rows below: picking a mechanic changes trigVal
    -- and spellIDText from OUTSIDE the Trigger dropdown's own setValue, so the dropdown's
    -- displayed label has to be told to re-read them rather than assume it already knows.
    local function RefreshTriggerLabel()
        local ctrl = triggerRow and triggerRow._leftRegion and triggerRow._leftRegion._control
        if ctrl and ctrl._refreshLabel then ctrl._refreshLabel() end
    end

    local triggerRowH
    triggerRow, triggerRowH = W:DualRow(triggerBody, 0,
        { type = "dropdown", text = "Trigger",
          values = TRIGGER_CHOICES, order = TRIGGER_ORDER,
          tooltip = "What starts this reminder.",
          getValue = function() return trigVal end,
          setValue = function(v)
              SaveDynFieldsToText()
              trigVal = v
              RebuildDynFields()
          end },
        { type = "label", text = "" }
    )
    DYN_Y = -triggerRowH

    -- The mechanic picker: every BigWigs/DBM key actually seen for this boss (recorded by
    -- RecordBossModKey the moment it fires live -- see the bridge above), sorted by how
    -- often it has come up. Picking one fills the Spell ID field below exactly the way
    -- typing it in would, so nothing downstream (BuildTrigger, Save) needed to change.
    local pickerRows = {}
    for i = 1, MECHANIC_PICKER_ROWS do
        local row = CreateFrame("Button", nil, triggerBody)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, 0)
        row:SetPoint("RIGHT", triggerBody, "RIGHT", -PAD, 0)

        row.hl = ns.Solid(row, "BACKGROUND", ns.THEME.gold, 0.14)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row:SetScript("OnEnter", function(s) s.hl:Show() end)
        row:SetScript("OnLeave", function(s) s.hl:Hide() end)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = ns.Font(row, 11, nil, ns.THEME.fg)
        row.name:SetPoint("LEFT", 24, 0)
        row.name:SetPoint("RIGHT", -34, 0)
        row.name:SetJustifyH("LEFT")

        row.tag = ns.Font(row, 9, nil, ns.THEME.muted)
        row.tag:SetPoint("RIGHT", -2, 0)

        pickerRows[i] = row
    end

    local pickerHint = ns.Font(triggerBody, 10, nil, ns.THEME.muted)
    pickerHint:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, 0)
    pickerHint:SetPoint("RIGHT", triggerBody, "RIGHT", -PAD, 0)
    pickerHint:SetJustifyH("LEFT")

    local PICKER_ROW_H = 24
    local PICKER_HEIGHT = 0 -- computed by RebuildPicker, consumed by RebuildDynFields

    local function RebuildPicker()
        for i = 1, MECHANIC_PICKER_ROWS do pickerRows[i]:Hide() end
        pickerHint:SetText("")

        if trigVal ~= "bwmsg" and trigVal ~= "bwtimer" then
            PICKER_HEIGHT = 0
            return
        end

        local cat = ns.BossModCatalogueTable and ns.BossModCatalogueTable(false, encounterID)
        local list = {}
        if cat then
            for key, entry in pairs(cat) do
                list[#list + 1] = { key = key, entry = entry }
            end
        end
        table.sort(list, function(a, b) return (a.entry.seen or 0) > (b.entry.seen or 0) end)

        if #list == 0 then
            pickerHint:SetText("|cff8a99b5Nothing recorded for this boss yet -- pull it with "
                .. "BigWigs or DBM running, or type a Spell ID below.|r")
            pickerHint:SetHeight(28)
            PICKER_HEIGHT = 28
            return
        end

        local shown = math.min(#list, MECHANIC_PICKER_ROWS)
        for i = 1, shown do
            local row, item = pickerRows[i], list[i]
            row:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, -((i - 1) * PICKER_ROW_H))
            row.icon:SetTexture(ResolveMechanicIcon(item.key))
            row.name:SetText(ResolveMechanicName(item.key, item.entry))
            row.tag:SetText(item.entry.mod == "DBM" and "|cff2da6ffDBM|r" or "|cfff0a830BW|r")
            row:SetScript("OnClick", function()
                SaveDynFieldsToText()
                trigVal = (item.entry.kind == "timer") and "bwtimer" or "bwmsg"
                spellIDText = tostring(item.key)
                RefreshTriggerLabel()
                RebuildDynFields()
            end)
            row:Show()
        end

        pickerHint:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, -(shown * PICKER_ROW_H))
        if #list > shown then
            pickerHint:SetText(("|cff8a99b5+%d more not shown -- type the Spell ID below.|r")
                :format(#list - shown))
            pickerHint:SetHeight(16)
        else
            pickerHint:SetHeight(4)
        end
        PICKER_HEIGHT = shown * PICKER_ROW_H + (pickerHint:GetText() ~= "" and 20 or 4)
    end

    RebuildDynFields = function()
        if dynFrame then dynFrame:Hide() end
        RebuildPicker()

        dynFrame = CreateFrame("Frame", nil, triggerBody)
        dynFrame:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", 0, DYN_Y - PICKER_HEIGHT)
        dynFrame:SetSize(480, 210)
        spellBox, counterBox, timeleftBox, delayBox = nil, nil, nil, nil

        local dy = 0
        local function DLabel(text, tooltip)
            local l = ns.Font(dynFrame, 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", dynFrame, "TOPLEFT", PAD, dy)
            l:SetText(text)
            if tooltip then
                local hit = CreateFrame("Frame", nil, dynFrame)
                hit:SetPoint("TOPLEFT", l, "TOPLEFT", -4, 4)
                hit:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 4, -4)
                HoverTip(hit, tooltip)
            end
            dy = dy - 16
        end
        local function DBox(maxLetters, numeric, rightInset)
            local box = CreateFrame("EditBox", nil, dynFrame)
            box:SetPoint("TOPLEFT", dynFrame, "TOPLEFT", PAD, dy)
            box:SetPoint("RIGHT", dynFrame, "RIGHT", -(rightInset or PAD), 0)
            box:SetHeight(26)
            box:SetAutoFocus(false)
            box:SetMaxLetters(maxLetters or 60)
            if numeric then box:SetNumeric(true) end
            box:SetFontObject("GameFontHighlight")
            box:SetTextInsets(6, 6, 0, 0)
            ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
            ns.Border(box)
            dy = dy - 32
            return box
        end

        if trigVal == "pull" then
            DLabel("Show in", SHOW_IN_TIP)
            delayBox = DBox(60)
            delayBox:SetText(delayText)
        else
            if trigVal == "aura" then
                local _, rowHA = W:DualRow(dynFrame, dy,
                    { type = "dropdown", text = "Target",
                      values = { boss = "Boss", player = "You" }, order = { "boss", "player" },
                      tooltip = "Which unit the aura has to land on.",
                      getValue = function() return targetVal end,
                      setValue = function(v) targetVal = v end },
                    { type = "dropdown", text = "When",
                      values = { applied = "Applied", removed = "Removed", stacks = "Stacks" },
                      order = { "applied", "removed", "stacks" },
                      tooltip = "Fire when the aura lands, when it falls off, or when it "
                          .. "gains a stack -- read straight off the combat log, since a "
                          .. "boss unit's own aura data is blocked from every addon during "
                          .. "restricted content, confirmed live.",
                      getValue = function() return auraEventVal end,
                      setValue = function(v) auraEventVal = v; RebuildDynFields() end }
                ); dy = dy - rowHA
            end

            DLabel("Spell ID")
            spellBox = DBox(9, true, 80)
            spellBox:SetText(spellIDText)
            -- Anchored off spellBox itself so the reserved rightInset above only has to be
            -- wide enough, not exactly right.
            local ok = ns.Button(dynFrame, "OK", 54, 26, function() spellBox:ClearFocus() end)
            ok:SetPoint("LEFT", spellBox, "RIGHT", 6, 0)
            local feedback = ns.Font(dynFrame, 10, nil, ns.THEME.muted)
            feedback:SetPoint("TOPLEFT", dynFrame, "TOPLEFT", PAD, dy + 6)
            feedback:SetPoint("RIGHT", dynFrame, "RIGHT", -PAD, 0)
            feedback:SetJustifyH("LEFT")
            dy = dy - 14

            local function Sync()
                local sid, info = ns.ResolveSpell(spellBox:GetText())
                if sid then
                    feedback:SetText("|cff6DD09A" .. ((info and info.name) or "") .. "|r")
                elseif spellBox:GetText() == "" then
                    feedback:SetText("")
                elseif trigVal == "aura" then
                    -- An aura id is a real spell, unlike a BigWigs/DBM message key, which
                    -- can be an arbitrary number with no matching spell at all.
                    feedback:SetText("|cffff6060not a spell ID|r")
                else
                    feedback:SetText("|cff8a99b5no spell name found -- boss-mod keys "
                        .. "aren't always real spell ids, that's fine|r")
                end
            end
            spellBox:SetScript("OnTextChanged", Sync)
            spellBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            Sync()

            if trigVal == "bwtimer" then
                DLabel("Timeleft (seconds)",
                    "Fires when this many seconds are left on the bar.")
                timeleftBox = DBox(6, true)
                timeleftBox:SetText(timeleftText)
            end

            if trigVal == "aura" and auraEventVal == "stacks" then
                DLabel("Stack Count", "Fires when the aura reaches this many stacks. Same "
                    .. "syntax as Counter: blank fires on every stack gain, or match a "
                    .. "threshold with >N, >=N, <N, <=N, !N (not N) or a bare number "
                    .. "(exactly N).")
            else
                DLabel("Counter", COUNTER_TIP)
            end
            counterBox = DBox(40)
            counterBox:SetText(counterText)

            DLabel("Show in", SHOW_IN_TIP)
            delayBox = DBox(60)
            delayBox:SetText(delayText)
        end
    end
    RebuildDynFields()

    SelectTab("trigger")

    local function BuildTrigger()
        SaveDynFieldsToText()
        if trigVal == "pull" then
            return { type = "pull", delay = (delayText ~= "" and delayText) or nil }
        end
        local sid = tonumber(spellIDText)
        if not sid then return nil end
        local newTrig = { type = trigVal, spellID = sid,
            counter = (counterText ~= "" and counterText) or nil,
            delay = (delayText ~= "" and delayText) or nil }
        if trigVal == "bwtimer" then
            newTrig.timeleft = tonumber(timeleftText)
            if not newTrig.timeleft then return nil end
        elseif trigVal == "aura" then
            newTrig.target = targetVal
            newTrig.auraEvent = auraEventVal
        end
        return newTrig
    end

    local function Save()
        local newTrig = BuildTrigger()
        if not newTrig then
            ns.Print("|cffff6060need a valid spell ID"
                .. (trigVal == "bwtimer" and " and timeleft" or "") .. " for this trigger|r")
            return
        end
        local name = nameBox:GetText()
        if not name or name == "" then name = "Reminder" end
        local dur = tonumber(durBox:GetText()) or 3
        local iconSid = tonumber(iconBox:GetText())
        local writeSet = ns.CustomRemindersTable(true, encounterID)
        local key = uid or ("r" .. math.floor(GetTime() * 1000) .. math.random(1, 9999))
        writeSet[key] = {
            name = name, preset = presetVal, trigger = newTrig,
            dur = math.max(1, dur), enabled = enabledVal,
            color = pendingColor,
            iconSpellID = (iconSid and iconSid > 0) and iconSid or nil,
            sound = (pendingSoundKey ~= "none") and pendingSoundKey or nil,
        }
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end

    ns.Button(panel, "Preview", 90, 26, function()
        local iconSid = tonumber(iconBox:GetText())
        ns.PreviewCustomReminder({
            name = nameBox:GetText(), preset = presetVal,
            dur = tonumber(durBox:GetText()) or 3,
            color = pendingColor,
            iconSpellID = (iconSid and iconSid > 0) and iconSid or nil,
            sound = (pendingSoundKey ~= "none") and pendingSoundKey or nil,
        })
    end):SetPoint("BOTTOM", panel, "BOTTOM", -110, 16)
    ns.Button(panel, "Save", 90, 26, Save):SetPoint("BOTTOM", panel, "BOTTOM", -10, 16)
    ns.Button(panel, "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 90, 16)

    dimmer:Show()
end

-- Profile tab: sharing (Reminder Packs) and the two global on/off switches.
-- Global in scope -- neither is "which boss" or "how it looks", both are
-- "what this profile does everywhere" -- so this is where they belong now
-- that the boss list has its own two tabs.
function ns.BuildProfileSettings(parent, y)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local _, h
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

    return y
end

-- InstanceSlot/AttachInstanceCog (the old bulk on/off toggle + cog opening the old
-- fingerprint-accordion boss modal, both since removed) were here and are gone -- the left
-- column is pure navigation now, and the bulk on/off they wrote is still reachable, just
-- relocated to the selected boss's own Enable This Boss row (RenderBossHeader) instead of
-- a per-instance shortcut.

-- Which instance is selected on each tab, and which boss within it -- both persist
-- across a RefreshPage (module-level upvalues, not page-local), the same way the Setup
-- tab's old tile selection did before that got removed. Independent per tab: picking a
-- dungeon must not disturb whichever raid was showing.
local selectedInst = { dungeon = nil, raid = nil }
local selectedBossIdx = {}   -- keyed by instance.id

-- One ability row: checkbox (this ability's binding, stored in AbilityBindingsTable by
-- its journal spellID), icon, title, description, a cog on the right. Fixed height rather
-- than measured from the wrapped description's real extent -- GetStringHeight() right
-- after SetPoint/SetText depends on this row's own width having already resolved through
-- its parent chain, which is exactly the kind of synchronous-layout assumption that
-- produced the Setup-tab overlap earlier tonight. A long description clips instead;
-- annoying, never wrong.
-------------------------------------------------------------------------------
--  Per-ability reminder picker: keep this ability on the normal defensive
--  priority list, or bind a written reminder straight to its own cast.
-------------------------------------------------------------------------------
-- A bound reminder rides the same "spell" trigger type the old cast/aura editor used to
-- write -- see CheckCustomReminders in the main file, which still matches it off the
-- combat log against any cast of this exact journal spellID, no BigWigs/DBM message
-- needed. Kept separate from the full custom-reminder editor (Trigger/Message tabs) on
-- purpose: that editor's Trigger dropdown has no "spell" option and remaps one to
-- "BigWigs/DBM Message" for display, which would silently swap this ability's direct-cast
-- match for a broadcast-key match -- a different and less reliable trigger -- the moment
-- it got re-saved there.
local function FindBoundReminder(encounterID, spellID)
    local set = ns.CustomRemindersTable(false, encounterID)
    if not set then return nil, nil end
    for uid, r in pairs(set) do
        local t = r.trigger
        if t and t.type == "spell" and t.spellID == spellID and (t.kind or "cast") == "cast" then
            return uid, r
        end
    end
    return nil, nil
end

function ns.ShowAbilityReminderPicker(encounterID, ability, callerEUI)
    local EUI = callerEUI or _G.EllesmereUI
    local W = EUI.Widgets

    local dimmer, panel = ns.MakeModal(440, 480)

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(ability.title or "Ability")

    local PAD = 20
    local TAB_TOP = -46

    local boundUid, boundReminder = FindBoundReminder(encounterID, ability.spellID)
    local bindings = ns.AbilityBindingsTable(true, encounterID)
    bindings[ability.spellID] = bindings[ability.spellID] or {}
    local binding = bindings[ability.spellID]
    local modeVal = (binding.mode == "custom") and "custom" or "defensive"
    local specID = ns.CurrentSpec and ns.CurrentSpec()

    -- One toggle, not two tabs: Pre-Selected Defensives and Custom Reminder are mutually
    -- exclusive for a given ability now (see Save) -- the primary callout steps aside for
    -- this ability entirely when a custom reminder is what's configured, so there is only
    -- ever one thing on screen for this ability, never both at once.
    local toggleCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    toggleCheck:SetSize(22, 22)
    toggleCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP)
    local toggleLabel = ns.Font(panel, 12, nil, ns.THEME.fg)
    toggleLabel:SetPoint("LEFT", toggleCheck, "RIGHT", 4, 0)
    toggleLabel:SetText("Use Pre-Selected Defensives")

    -- Same destroy-and-recreate idiom as the custom reminder editor's own dynFrame: the
    -- old body is hidden and dropped rather than cleared field by field, since GetChildren
    -- only ever returns child FRAMES, not the label FontStrings this also has to remove.
    local body
    -- pendingColor/pendingSoundKey/pendingSoundPaths/presetVal are written by the widgets
    -- built in RebuildBody and read back by Save() -- they have to outlive any single
    -- rebuild, since a pick must not be lost if something else on the panel forces a
    -- reflow later.
    local msgBox, durBox, iconBox, presetVal
    local pendingColor, pendingSoundKey, pendingSoundPaths

    local function RebuildBody()
        if body then body:Hide() end
        body = CreateFrame("Frame", nil, panel)
        body:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP - 30)
        body:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, TAB_TOP - 30)
        -- An explicit height, not just the two TOP anchors -- matching dynFrame in the full
        -- custom reminder editor below (SetSize) and messageBody/triggerBody in the same
        -- (SetHeight): a frame anchored on only one edge never resolves a height on its
        -- own, and every rebuilt-body frame elsewhere in this file sets one for that reason.
        body:SetHeight(320)
        msgBox, durBox, iconBox = nil, nil, nil

        -- Wrapped: a blank body with no error anywhere on screen is the exact failure mode
        -- that shipped once already (the tab buttons mispositioned so badly the whole
        -- panel looked dead). If something in here throws, this says so instead of leaving
        -- another silent blank panel.
        local ok, err = pcall(function()
        local by = 0

        -- One-column helpers throughout -- W:DualRow's second slot always reserves the
        -- full right half even fed a blank label, which is exactly the dead space this
        -- popup does not have the width to spare (it is 440px, not a page-width column).
        local function Label(text)
            local lbl = ns.Font(body, 11, nil, ns.THEME.muted)
            lbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            lbl:SetText(text)
            by = by - 16
        end
        -- Every field the same fixed width instead of stretching to the body's edge, so
        -- Message/Icon/Sound/Linger all line up on both edges together rather than each
        -- field claiming whatever width its own row happens to need.
        local FIELD_W = 260
        local function Box(maxLetters, numeric, rightInset)
            local box = CreateFrame("EditBox", nil, body)
            box:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            box:SetSize(FIELD_W - (rightInset or 0), 26)
            box:SetAutoFocus(false)
            box:SetMaxLetters(maxLetters or 60)
            if numeric then box:SetNumeric(true) end
            box:SetFontObject("GameFontHighlight")
            box:SetTextInsets(6, 6, 0, 0)
            ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
            ns.Border(box)
            by = by - 32
            return box
        end
        -- A single dropdown row, fixed width to match Box -- EllesmereUI.BuildDropdownControl
        -- is the same primitive W:DualRow's own "dropdown" slot type calls, without the
        -- page-row chrome (background band, hover-tag) that widget wraps it in, which is
        -- built for a full-width options page rather than a small modal.
        local function DropdownRow(values, order, getValue, setValue)
            local ddBtn = EUI.BuildDropdownControl(body, FIELD_W,
                body:GetFrameLevel() + 1, values, order, getValue, setValue)
            ddBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            by = by - 32
            return ddBtn
        end

        if modeVal == "defensive" then
            -- One preset, not a hand-built list: this ability draws from whichever preset
            -- is chosen here, the same way a boss or a custom reminder already draws from
            -- one -- edited on the Setup page, not duplicated per ability.
            local presets = ns.ListPresets(specID)
            if #presets == 0 then
                local hint = ns.Font(body, 11, nil, ns.THEME.muted)
                hint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                hint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                hint:SetWordWrap(true)
                hint:SetText("|cff8a99b5No presets yet -- add one on the Setup page "
                    .. "first.|r")
                by = by - 34
            else
                local presetValues, presetOrder = {}, {}
                for i = 1, #presets do
                    presetValues[presets[i].key] = presets[i].name
                    presetOrder[i] = presets[i].key
                end
                -- Shows the effective default (this boss's preset, else the spec's active
                -- one) until this ability actually gets its own pick, matching the same
                -- fallback EffectiveList itself uses at runtime.
                presetVal = binding.preset or ns.BossPresetKey(specID, encounterID)
                    or ns.ActivePresetKey(specID) or presetOrder[1]
                Label("Defensive Preset")
                DropdownRow(presetValues, presetOrder,
                    function() return presetVal end,
                    function(v) presetVal = v end)
            end

            local note = ns.Font(body, 10, nil, ns.THEME.muted)
            note:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            note:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            note:SetJustifyH("LEFT")
            note:SetWordWrap(true)
            note:SetText("Calls out the highest defensive on that preset still ready "
                .. "when this ability is cast.")
            by = by - 30
        else
            Label("Message")
            msgBox = Box(120)
            msgBox:SetText((boundReminder and boundReminder.msg) or "")

            -- Icon: optional, looked up by spell id the same way the full custom reminder
            -- editor resolves its Trigger tab's Spell ID field (ns.ResolveSpell) -- a live
            -- preview and name confirm it before Save ever runs. Only relevant here:
            -- Pre-Selected Defensives mode has no message frame of its own to put one on.
            Label("Icon Spell ID (optional)")
            iconBox = Box(9, true, 34)
            local iconPreview = body:CreateTexture(nil, "ARTWORK")
            iconPreview:SetSize(24, 24)
            iconPreview:SetPoint("LEFT", iconBox, "RIGHT", 6, 0)
            iconPreview:Hide()
            local iconFeedback = ns.Font(body, 10, nil, ns.THEME.muted)
            iconFeedback:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            iconFeedback:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            iconFeedback:SetJustifyH("LEFT")
            by = by - 14
            local function SyncIcon()
                local sid, info = ns.ResolveSpell(iconBox:GetText())
                if sid then
                    local tex = C_Spell and C_Spell.GetSpellTexture
                        and C_Spell.GetSpellTexture(sid)
                    if tex then iconPreview:SetTexture(tex); iconPreview:Show()
                    else iconPreview:Hide() end
                    iconFeedback:SetText("|cff6DD09A" .. ((info and info.name) or "") .. "|r")
                elseif iconBox:GetText() == "" then
                    iconPreview:Hide()
                    iconFeedback:SetText("")
                else
                    iconPreview:Hide()
                    iconFeedback:SetText("|cffff6060not a spell id|r")
                end
            end
            iconBox:SetScript("OnTextChanged", SyncIcon)
            iconBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            iconBox:SetText((boundReminder and boundReminder.iconSpellID
                and tostring(boundReminder.iconSpellID)) or "")
            SyncIcon()

            -- Text color: an explicit per-reminder color, defaulting to white the same way
            -- every other text color in this addon starts white until changed. Hand-rolled
            -- swatch rather than W:ColorPicker/the DualRow colorpicker type -- both are
            -- built for a full-width options row; this replicates just the
            -- swatch-plus-native-picker core (EllesmereUI:ShowColorPicker, the same public
            -- entry point the shared swatch helper itself calls) at the size this popup
            -- actually needs.
            local existingColor = boundReminder and boundReminder.color
            pendingColor = { r = (existingColor and existingColor.r) or 1,
                g = (existingColor and existingColor.g) or 1,
                b = (existingColor and existingColor.b) or 1, a = 1 }
            Label("Text Color")
            local swatch = CreateFrame("Button", nil, body)
            swatch:SetSize(24, 24)
            swatch:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            local swatchFill = swatch:CreateTexture(nil, "ARTWORK")
            swatchFill:SetAllPoints()
            swatchFill:SetColorTexture(pendingColor.r, pendingColor.g, pendingColor.b, 1)
            ns.Border(swatch)
            swatch:SetScript("OnClick", function()
                local snapR, snapG, snapB = pendingColor.r, pendingColor.g, pendingColor.b
                local function Applied()
                    local popup = EUI._colorPickerPopup
                    if not popup then return end
                    local cr, cg, cb = popup:GetColorRGB()
                    pendingColor = { r = cr, g = cg, b = cb, a = 1 }
                    swatchFill:SetColorTexture(cr, cg, cb, 1)
                end
                EUI:ShowColorPicker({
                    swatchFunc = Applied,
                    hasOpacity = false,
                    cancelFunc = function()
                        pendingColor = { r = snapR, g = snapG, b = snapB, a = 1 }
                        swatchFill:SetColorTexture(snapR, snapG, snapB, 1)
                    end,
                    r = pendingColor.r, g = pendingColor.g, b = pendingColor.b,
                }, swatch)
            end)
            by = by - 32

            -- Sound: the same catalogue and SharedMedia appender the Setup > Sounds page's
            -- own Alert Sound dropdown uses, so this list matches exactly.
            pendingSoundKey = (boundReminder and boundReminder.sound) or "none"
            local soundNames, soundOrder
            pendingSoundPaths, soundNames, soundOrder = EUI.BuildAlertSoundTables()
            if EUI.AppendSharedMediaSounds then
                EUI.AppendSharedMediaSounds(pendingSoundPaths, soundNames, soundOrder)
            end
            Label("Sound")
            DropdownRow(soundNames, soundOrder,
                function() return pendingSoundKey end,
                function(v)
                    pendingSoundKey = v
                    if EUI._PlayLSMSound and pendingSoundPaths[v] then
                        EUI._PlayLSMSound(pendingSoundPaths[v])
                    end
                end)

            Label("Linger (seconds)")
            durBox = Box(3, true)
            durBox:SetText(tostring((boundReminder and boundReminder.dur) or 3))
        end
        end)
        if not ok then
            local errText = ns.Font(body, 11, nil, { r = 1, g = 0.35, b = 0.35 })
            errText:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
            errText:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            errText:SetJustifyH("LEFT")
            errText:SetWordWrap(true)
            errText:SetText("Failed to build this panel: " .. tostring(err))
            ns.Print("|cffff6060ability reminder picker|r: " .. tostring(err))
        end
    end

    local function SelectMode(m)
        modeVal = m
        toggleCheck:SetChecked(m == "defensive")
        RebuildBody()
    end

    toggleCheck:SetChecked(modeVal == "defensive")
    toggleCheck:SetScript("OnClick", function(self)
        SelectMode(self:GetChecked() and "defensive" or "custom")
    end)
    RebuildBody()

    local function Save()
        binding.mode = modeVal
        if modeVal == "defensive" then
            binding.preset = presetVal
            -- Mutually exclusive per ability: switching to Pre-Selected Defensives drops
            -- any custom reminder this ability had, so ns.HandleBigWigsAbility (which
            -- skips its own pick entirely when mode is "custom") is never fighting a
            -- leftover custom popup that's still configured to fire for the same cast.
            local writeSet = ns.CustomRemindersTable(false, encounterID)
            if writeSet then writeSet[boundUid or ("ab" .. ability.spellID)] = nil end
        else
            local writeSet = ns.CustomRemindersTable(true, encounterID)
            local key = boundUid or ("ab" .. ability.spellID)
            local iconSid = iconBox and tonumber(iconBox:GetText())
            writeSet[key] = {
                name = ability.title,
                trigger = { type = "spell", spellID = ability.spellID, kind = "cast" },
                dur = math.max(1, tonumber(durBox and durBox:GetText()) or 3),
                enabled = true,
                color = pendingColor,
                iconSpellID = (iconSid and iconSid > 0) and iconSid or nil,
                sound = (pendingSoundKey and pendingSoundKey ~= "none") and pendingSoundKey
                    or nil,
                msg = msgBox and msgBox:GetText() or "",
            }
        end
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end

    ns.Button(panel, "Save", 90, 26, Save):SetPoint("BOTTOM", panel, "BOTTOM", -50, 16)
    ns.Button(panel, "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 50, 16)

    dimmer:Show()
end

local ABILITY_ROW_H = 62

local function RenderAbilityRow(parent, y, encounterID, ability, specID, EUI)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(ABILITY_ROW_H)

    -- Single source of truth with the runtime's own default (ns.AbilityEnabledForBinding):
    -- an explicit binding wins, otherwise this defaults to on for a curated tank buster,
    -- same as the checkbox would otherwise silently disagree with what actually calls out.
    local enabled = ability.spellID and ns.AbilityEnabledForBinding(encounterID, ability.spellID)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
    check:SetChecked(enabled)
    check:SetScript("OnClick", function(self)
        if not ability.spellID then self:SetChecked(false); return end
        local set = ns.AbilityBindingsTable(true, encounterID)
        set[ability.spellID] = set[ability.spellID] or {}
        set[ability.spellID].enabled = self:GetChecked() and true or false
        ns.RefreshRuntime()
    end)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", check, "TOPRIGHT", 6, 4)
    if ability.icon then icon:SetTexture(ability.icon) end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cog = ns.Button(row, "...", 30, 26, function()
        if not ability.spellID then
            ns.Print("|cffff6060this journal entry has no spell id to bind to|r")
            return
        end
        ns.ShowAbilityReminderPicker(encounterID, ability, EUI)
    end)
    cog:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)

    -- Role/difficulty flags straight off the journal (FLAG_LABELS, same icon set the
    -- in-game Adventure Guide shows) -- Tank/Dps/Healer first since those are the ones
    -- worth a glance, the rest folded into the description line below instead of a
    -- second row, which is what caused the Setup-tab overlap this row's fixed height
    -- comment already warns about.
    local ROLE_COLOR = { Tank = "|cffF0A830", Dps = "|cffFF6060", Healer = "|cff6DD09A" }
    local roleTag, restTag
    if ability.extras then
        local roles, rest = {}, {}
        for label in ability.extras:gmatch("[^,]+") do
            label = label:match("^%s*(.-)%s*$")
            if ROLE_COLOR[label] then
                roles[#roles + 1] = ROLE_COLOR[label] .. label .. "|r"
            elseif label ~= "" then
                rest[#rest + 1] = label
            end
        end
        if #roles > 0 then roleTag = table.concat(roles, " ") end
        if #rest > 0 then restTag = table.concat(rest, ", ") end
    end

    local title = ns.Font(row, 13, nil, ns.THEME.fg)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    title:SetPoint("RIGHT", cog, "LEFT", -8, 0)
    title:SetJustifyH("LEFT")
    title:SetText((ability.title or "?") .. (roleTag and ("  " .. roleTag) or ""))

    local desc = ns.Font(row, 11, nil, ns.THEME.muted)
    desc:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -20)
    desc:SetPoint("RIGHT", cog, "LEFT", -8, 0)
    desc:SetHeight(ABILITY_ROW_H - 24)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    local descText = ability.description or "|cff8a99b5No description in the journal.|r"
    if restTag then descText = ("|cff8a99b5[%s]|r  "):format(restTag) .. descText end
    desc:SetText(descText)

    local div = ns.Solid(row, "ARTWORK", ns.THEME.line, 1)
    div:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    div:SetHeight(1)

    return y - ABILITY_ROW_H
end

local PHASE_HEADER_H = 24

local function RenderPhaseHeader(parent, y, text)
    local h = ns.Font(parent, 12, nil, ns.THEME.gold)
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    h:SetJustifyH("LEFT")
    h:SetText(text)
    return y - PHASE_HEADER_H
end

-- Curated abilities carry only a spellID -- name/icon/description still come from the
-- journal dump (ejByID) when it has the spell, since that is Blizzard's own text. Not
-- every curated spellID is journal-indexed (role-tagged and submodule-only entries rarely
-- are), so a miss falls back to C_Spell rather than dropping the row.
local function ResolveCuratedAbility(ejByID, spellID)
    local hit = ejByID[spellID]
    if hit then return hit end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if not info or not info.name then return nil end
    return { title = info.name, spellID = spellID, icon = info.iconID }
end

-- The selected instance's own view: Share Profile / Select Boss, the boss's own
-- Enable/Preset header (RenderBossHeader), then
-- every ability the Dungeon Journal lists for that boss -- journal icon, description
-- and role flags (Tank/Dps/Healer) included, all data ns.ScrapeBosses already collects
-- (boss.abilities).
-- TEMPORARY diagnostic: Tank/Dps tags aren't showing (Healer does), and descriptions are
-- often blank, in both Dungeon and Raid Bosses. One-shot per boss selection so switching
-- boss/instance re-dumps rather than spamming every re-render. Remove once explained.
local lastDiagBoss
local function RenderInstanceDetail(parent, y, W, EUI, inst, specID)
    local boss = inst.bosses[selectedBossIdx[inst.id] or 1]

    if boss and boss.encounterID and lastDiagBoss ~= boss.encounterID then
        lastDiagBoss = boss.encounterID
        ns.Print(("|cffF0A830ability flags|r %s (%d abilities)"):format(
            boss.name or "?", #(boss.abilities or {})))
        for i = 1, #(boss.abilities or {}) do
            local a = boss.abilities[i]
            ns.Print(("  %s sid=%s extras=%s desc=%s"):format(
                a.title or "?", tostring(a.spellID), a.extras or "nil",
                (a.description and a.description ~= "") and "yes" or "no"))
        end
    end

    local topRow = CreateFrame("Frame", nil, parent)
    topRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    topRow:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    topRow:SetHeight(26)

    -- Whole profile only -- sharing just one boss was removed as its own feature (the
    -- Reminder Packs page dropped it too), so this is a plain Export/Import pair now
    -- rather than a menu choosing between two scopes.
    local exportBtn = ns.Button(topRow, "Export", 70, 26, function()
        if ns.ShowPackExport then ns.ShowPackExport() end
    end)
    -- CONTENT_PAD, matching every EllesmereUI-native widget's own left inset
    -- (W:DualRow/W:Button/W:SectionHeader all apply it internally) -- without it this
    -- hand-built row sits slightly left of where "Enable This Boss" and everything below
    -- it actually starts.
    exportBtn:SetPoint("LEFT", topRow, "LEFT", EUI.CONTENT_PAD or 16, 0)

    local importBtn = ns.Button(topRow, "Import", 70, 26, function()
        if ns.ShowPackImport then ns.ShowPackImport() end
    end)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)

    -- Doubles as the boss-name display: one control at the top right instead of a
    -- button plus a separate name label below. Styled and behaving like a dropdown --
    -- current boss's name, a "v" -- via the same MenuUtil context-menu approach used
    -- elsewhere in this file. Not a genuine UIDropDownMenu-style popup: BuildDropdownControl,
    -- the primitive that would give one, is a private local inside
    -- EllesmereUI_Widgets.lua, not something this addon can call.
    local pick = ns.Button(topRow, "", 220, 26, function()
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(topRow, function(_, root)
                for b = 1, #inst.bosses do
                    local idx = b
                    root:CreateButton(inst.bosses[b].name, function()
                        selectedBossIdx[inst.id] = idx
                        EUI:RefreshPage(true)
                    end)
                end
            end)
        else
            selectedBossIdx[inst.id] = ((selectedBossIdx[inst.id] or 1) % #inst.bosses) + 1
            EUI:RefreshPage(true)
        end
    end)
    pick:SetPoint("RIGHT", topRow, "RIGHT", 0, 0)
    ns.SetButtonText(pick, (boss and boss.name or "Select Boss") .. "  v")
    if pick.label then pick.label:SetTextColor(ns.THEME.fg.r, ns.THEME.fg.g, ns.THEME.fg.b, 1) end
    y = y - 34

    if not boss then
        local hint = ns.Font(parent, 12, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        hint:SetText("This instance has no bosses in the journal yet.")
        return y - 20
    end

    -- No "General" header and no separate name line anymore -- the boss's name now
    -- lives in the picker above, so Enable This Boss sits directly under the top row.
    local bossOn
    y, bossOn = RenderBossHeader(parent, y, W, EUI, boss.encounterID, specID)
    if not bossOn then return y end

    y = y - 10
    if not (boss.abilities and #boss.abilities > 0) then
        local hint = ns.Font(parent, 12, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        hint:SetText("No abilities listed in the journal for this boss.")
        return y - 20
    end

    local curated = ns.CURATED_ABILITIES and ns.CURATED_ABILITIES[boss.encounterID]
    if curated then
        local ejByID = {}
        for i = 1, #boss.abilities do
            local a = boss.abilities[i]
            if a.spellID then ejByID[a.spellID] = a end
        end
        for g = 1, #curated do
            local group = curated[g]
            local rendered = 0
            for i = 1, #group.abilities do
                local ability = ResolveCuratedAbility(ejByID, group.abilities[i])
                if ability then
                    if rendered == 0 then y = RenderPhaseHeader(parent, y, group.phase) end
                    y = RenderAbilityRow(parent, y, boss.encounterID, ability, specID, EUI)
                    rendered = rendered + 1
                end
            end
        end
    else
        for i = 1, #boss.abilities do
            y = RenderAbilityRow(parent, y, boss.encounterID, boss.abilities[i], specID, EUI)
        end
    end

    -- Independent of the ability list above: these aren't bound to one spell id, so a
    -- boss can carry one even with nothing curated yet (a pull timer, an aura watch, a
    -- raw BigWigs/DBM message or bar match). Excludes "spell"-triggered entries -- those
    -- are the per-ability picker's own Custom Reminder mode (ShowAbilityReminderPicker),
    -- already editable from that ability's row; listing them here too would let this
    -- generic editor delete the reminder object while the ability's binding still says
    -- "custom", leaving that ability silently unable to fire either kind of callout.
    do
        y = y - 10
        local _, h = W:SectionHeader(parent, "CUSTOM REMINDERS", y); y = y - h
        local crSet = ns.CustomRemindersTable and ns.CustomRemindersTable(false, boss.encounterID)
        local crList = {}
        if crSet then
            for uid, r in pairs(crSet) do
                if not (r.trigger and r.trigger.type == "spell") then
                    crList[#crList + 1] = { uid = uid, r = r }
                end
            end
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
                local trig = r.trigger
                local trigDesc = "?"
                if trig and trig.type == "pull" then
                    trigDesc = "Pull"
                elseif trig and (trig.type == "bwmsg" or trig.type == "bwtimer") then
                    local info = C_Spell and C_Spell.GetSpellInfo
                        and C_Spell.GetSpellInfo(trig.spellID)
                    trigDesc = (trig.type == "bwtimer" and "Timer: " or "Message: ")
                        .. ((info and info.name) or tostring(trig.spellID))
                elseif trig and trig.type == "aura" then
                    local info = C_Spell and C_Spell.GetSpellInfo
                        and C_Spell.GetSpellInfo(trig.spellID)
                    trigDesc = (trig.auraEvent == "removed" and "Aura Removed: " or "Aura Applied: ")
                        .. ((info and info.name) or tostring(trig.spellID))
                        .. (trig.target == "player" and " (You)" or " (Boss)")
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
                      end }
                ); y = y - h
                if row then
                    AttachInline(row._leftRegion, "Edit", 46, function()
                        ns.ShowCustomReminderEditor(boss.encounterID, uid, EUI)
                    end, "Edit", "Change this reminder's trigger, message or how long it lingers.")
                    AttachInline(row._leftRegion, "Delete", 56, function()
                        local writeSet = ns.CustomRemindersTable(false, boss.encounterID)
                        if writeSet then writeSet[uid] = nil end
                        ns.RefreshRuntime()
                        EUI:RefreshPage(true)
                    end, "Delete", "Removes this reminder.")
                end
            end
        end

        _, h = W:Button(parent, "+ Add a Custom Reminder", y, function()
            ns.ShowCustomReminderEditor(boss.encounterID, nil, EUI)
        end)
        y = y - h
    end

    return y
end

-- Dungeon Bosses / Raid Bosses tab: a pure navigation list on the left -- one row per
-- instance, click to select, no per-row toggle here anymore (the old bulk on/off per
-- instance is still reachable; it lives on the selected boss's own Enable This Boss row,
-- same as it always did for a single boss) -- and the selected instance's detail on the
-- right.
function ns.BuildBossListPage(parent, y, isRaid)
    local EUI = _G.EllesmereUI
    local W   = EUI.Widgets
    local _, h
    local specID = ns.CurrentSpec()

    -- W:SectionHeader is a fixed widget -- left-aligned, one set colour, a 40px band with
    -- the label sitting near its bottom -- no centering or colour override exists on it.
    -- Hand-built here instead: centered, Naowh's gold, and a fraction of that height, which
    -- is most of what was leaving a gap between the tab strip and the content below.
    local pageHead = ns.Font(parent, 14, nil, ns.THEME.gold)
    pageHead:SetPoint("TOP", parent, "TOP", 0, y)
    pageHead:SetJustifyH("CENTER")
    pageHead:SetText(isRaid and "Raid Bosses" or "Dungeon Bosses")
    y = y - 22

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

    local list = {}
    for i = 1, #data.instances do
        local inst = data.instances[i]
        if (inst.isRaid or false) == isRaid then list[#list + 1] = inst end
    end

    local key = isRaid and "raid" or "dungeon"
    local sel = selectedInst[key]
    -- The scraped list is rebuilt fresh on every refresh (ns.ScrapeBosses is cached, but
    -- a new table each call after a forced rescan) -- match the remembered selection back
    -- up by id rather than by table identity, or picking an instance would un-pick itself
    -- the moment anything else on the page forced a refresh.
    if sel then
        local found
        for i = 1, #list do if list[i].id == sel.id then found = list[i]; break end end
        sel = found
        selectedInst[key] = found
    end

    local LEFT_W = 190
    local topY = y

    -- The picker's own label, above the pool it picks from -- used to be a hint on the
    -- right that only showed up once nothing was picked yet; moved here so it reads as
    -- the list's heading instead of an empty-state message.
    local leftHead = ns.Font(parent, 12, nil, ns.THEME.muted)
    leftHead:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, topY)
    leftHead:SetJustifyH("LEFT")
    leftHead:SetText(isRaid and "Select a Raid" or "Select a Dungeon")
    local listTop = topY - 18

    local leftPane = CreateFrame("Frame", nil, parent)
    leftPane:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, listTop)
    leftPane:SetSize(LEFT_W, math.max(1, #list * 26))

    for i = 1, #list do
        local inst = list[i]
        local row = CreateFrame("Button", nil, leftPane)
        row:SetSize(LEFT_W, 26)
        row:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -(i - 1) * 26)

        local isSel = (sel == inst)
        local bg = ns.Solid(row, "BACKGROUND", ns.THEME.gold, isSel and 0.16 or 0)
        bg:SetAllPoints()

        local lbl = ns.Font(row, 12, nil, isSel and ns.THEME.fg or ns.THEME.muted)
        lbl:SetPoint("LEFT", row, "LEFT", 6, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(inst.name)

        row:SetScript("OnClick", function()
            selectedInst[key] = inst
            EUI:RefreshPage(true)
        end)
    end

    -- Right edge inset by CONTENT_PAD, same as RenderPresetListEditor's own right column
    -- above -- without it, everything anchored to this pane's own RIGHT (the ability
    -- rows' cog button in particular) sits under the scroll frame's scrollbar, both
    -- visually clipped and unclickable since the scrollbar's hit region wins the click.
    local rightPane = CreateFrame("Frame", nil, parent)
    rightPane:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_W + 16, topY)
    rightPane:SetPoint("RIGHT", parent, "RIGHT", -(EUI.CONTENT_PAD or 16), 0)

    local rightBottom = topY
    if sel then
        rightBottom = RenderInstanceDetail(rightPane, 0, W, EUI, sel, specID)
    else
        rightBottom = 0
    end

    local leftBottom = listTop - (#list * 26)
    return math.min(leftBottom, topY + rightBottom)
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
