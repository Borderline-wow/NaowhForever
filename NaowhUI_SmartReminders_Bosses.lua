-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Bosses.lua -- browse this season's bosses and every ability the
--  journal lists for them, labelled by who each one is aimed at.
--
--  Every name, icon and tank marking is read out of the player's own client at runtime,
--  so it cannot go stale, it covers whatever season the client is on, and the addon
--  carries no encounter knowledge of its own. A shipped, BigWigs-GetOptions()-derived
--  phase-grouped filter was tried and dropped: BigWigs treats some tank-buster warnings
--  as always-on rather than a toggleable option, which GetOptions() never lists, so the
--  filter silently dropped real tank abilities across a wide range of bosses. Every
--  journal ability shows now, unfiltered.
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
-- Second return is true only when THIS call is the one that just triggered the on-demand
-- load -- confirmed live (raid boss descriptions came back empty on the session's first
-- scrape, then correct after a reload) that scraping the instant the module loads can
-- catch some of its data before the Journal has finished populating it. ScrapeBosses
-- uses this to queue one silent re-scrape rather than leave a whole session stuck with
-- whatever the cold first pass happened to catch.
local function EnsureJournal()
    if EJ_GetCurrentTier and C_EncounterJournal and C_EncounterJournal.GetSectionInfo then
        return true, false
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end
    local ok = EJ_GetCurrentTier ~= nil and C_EncounterJournal ~= nil
        and C_EncounterJournal.GetSectionInfo ~= nil
    return ok, ok
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
local rescrapeQueued
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
                    else
                        -- Per-label, not the whole blob: a later occurrence carrying two
                        -- flags where the first only had one ("Heroic, Deadly" showing up
                        -- after a prior "Heroic") would never substring-match as a whole,
                        -- appending the already-present label a second time.
                        for label in extras:gmatch("[^,]+") do
                            label = label:match("^%s*(.-)%s*$")
                            if label ~= "" and not prior.extras:find(label, 1, true) then
                                prior.extras = prior.extras .. ", " .. label
                            end
                        end
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
    local journalOk, freshLoad = EnsureJournal()
    if not journalOk then scrapeFailed = "journal" return nil end
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

    -- A module loaded on-demand this exact instant is not always fully populated yet.
    -- One silent re-scrape a moment later catches up without the player needing to
    -- notice or hit Refresh themselves. freshLoad is only ever true on the very first
    -- scrape of a session (EnsureJournal reports the module as already loaded on any
    -- later call, including this retry), so this can only ever queue once.
    if freshLoad and not rescrapeQueued then
        rescrapeQueued = true
        C_Timer.After(2, function()
            rescrapeQueued = false
            if JournalBusy() then return end
            ns.ScrapeBosses(true)
            local EUI = ns.UI
            if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
        end)
    end

    return cache
end

-------------------------------------------------------------------------------
--  BigWigs ability lists
-------------------------------------------------------------------------------
-- The journal documents everything -- per-difficulty variants, sub-abilities, whole
-- mechanics BigWigs never warns about -- so the flat journal listing carried rows whose
-- checkbox could never do anything: the engine only ever receives what BigWigs actually
-- broadcasts, and that set is the module's own option list. When a boss has a BigWigs
-- module installed, the page lists exactly that (mod.toggleOptions, the same set
-- BigWigs' own options UI shows), keyed by the ids the engine will receive. Bosses with
-- no module keep the full journal listing.
local bwOptionCache = {}   -- [dungeonEncounterID] = { {id, stage}, ... }, or false
local bwPacksLoaded

-- Content packs are LoadOnDemand and never loaded outside their own zone; BigWigs' own
-- options UI force-loads them the same way when browsing. Core comes in through each
-- pack's dependencies. First use only, from this page only -- the same lazy rule as the
-- journal scrape. LittleWigs' expansion packs are included because the season's dungeon
-- rotation reaches back into old expansions.
local function LoadBossModPacks()
    if bwPacksLoaded then return end
    bwPacksLoaded = true
    if not (C_AddOns and C_AddOns.LoadAddOn and C_AddOns.GetNumAddOns) then return end
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string"
            and (name:find("^BigWigs_") or name:find("^LittleWigs"))
            and name ~= "BigWigs_Plugins" and name ~= "BigWigs_Options" then
            C_AddOns.LoadAddOn(name)
        end
    end
end

local function BigWigsOptionList(encounterID)
    -- Some journal rows carry no dungeonEncounterID (EJ_GetEncounterInfo's 7th return can
    -- be nil) -- a nil TABLE WRITE below would throw, unlike the read just above, which
    -- Lua allows. Nothing to look up without an id anyway; falls through to the journal
    -- listing the same as "no module found" does.
    if encounterID == nil then return nil end
    local cached = bwOptionCache[encounterID]
    if cached ~= nil then return cached or nil end
    LoadBossModPacks()
    local core = _G.BigWigs
    if not (core and type(core.IterateBossModules) == "function") then
        bwOptionCache[encounterID] = false
        return nil
    end
    local target
    for _, m in core:IterateBossModules() do
        if m.IsEncounterID and m:IsEncounterID(encounterID) then target = m break end
    end
    -- BigWigs core resolves a module's GetOptions into toggleOptions/optionHeaders via
    -- SetupOptions and drops GetOptions; its own options UI calls SetupOptions before
    -- reading too, in case that has not run yet.
    if target and target.SetupOptions then target:SetupOptions() end
    local toggles = target and target.toggleOptions
    if type(toggles) ~= "table" then
        bwOptionCache[encounterID] = false
        return nil
    end
    -- optionHeaders marks the option a group starts at, values already resolved by core
    -- to display strings (stage names from the journal, "Mythic", ...). Carried onto
    -- every following entry so the render loop only has to compare neighbours.
    -- Entries can be plain ids or {id, flag, ...} tables; string options ("stages",
    -- "berserk") are BigWigs UI plumbing, not abilities, and never broadcast as keys.
    local headers = target.optionHeaders
    local list, seen, stage = {}, {}, nil
    for i = 1, #toggles do
        local opt = toggles[i]
        if type(opt) == "table" then opt = opt[1] end
        if headers and headers[opt] ~= nil then stage = tostring(headers[opt]) end
        if type(opt) == "number" and opt > 0 and not seen[opt] then
            seen[opt] = true
            list[#list + 1] = { id = opt, stage = stage }
        end
    end
    if #list == 0 then
        bwOptionCache[encounterID] = false
        return nil
    end
    bwOptionCache[encounterID] = list
    return list
end

-- Merged fresh per render rather than cached: the journal side can improve underneath
-- (the cold-load re-scrape above), and the merge is a dozen table reads per boss.
-- Row identity is ALWAYS the BigWigs id -- it is what the engine receives, so the
-- checkbox/preset written under it is found at fire time directly. The journal entry
-- for the same mechanic is matched by spell id, then by name (the two id spaces are
-- not guaranteed to agree: Possession Barrage is 1292036 in BigWigs, 1284103 in the
-- journal) and contributes description, icon and role tags.
local function BigWigsAbilities(encounterID, journalAbilities)
    local opts = BigWigsOptionList(encounterID)
    if not opts then return nil end
    local byId, byName = {}, {}
    for i = 1, #(journalAbilities or {}) do
        local a = journalAbilities[i]
        byId[a.spellID] = a
        if a.title and not byName[a.title] then byName[a.title] = a end
    end
    local list = {}
    for i = 1, #opts do
        local id = opts[i].id
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        local name = info and info.name
        local j = byId[id] or (name and byName[name])
        list[#list + 1] = {
            title       = (j and j.title) or name or ("Spell " .. id),
            spellID     = id,
            icon        = (j and j.icon) or (info and info.iconID),
            extras      = j and j.extras,
            description = j and j.description,
            stage       = opts[i].stage,
        }
    end
    return list
end

-------------------------------------------------------------------------------
--  The tree page
-------------------------------------------------------------------------------
-- Dungeons and raids as a collapsed tree: click an instance to open it, click a boss to set
-- a priority just for that boss. Everything renders through the shared widget factory, so
-- this page reads like every other one rather than a custom window pretending to be one.
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
        local EUIg = ns.UI
        if EUIg and EUIg.ShowWidgetTooltip then
            EUIg.ShowWidgetTooltip(btn, "Remove",
                entry.userAdded and "Deletes this spell you added."
                or "Takes this out of your choices. Restore them with the button at the bottom.")
        end
    end)
    btn:SetScript("OnLeave", function()
        local c = ns.THEME.muted
        a:SetColorTexture(c.r, c.g, c.b, 0.85); b:SetColorTexture(c.r, c.g, c.b, 0.85)
        local EUIg = ns.UI
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
    local EUIg = ns.UI
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
-- rather than captured directly. Dialogs built from the widget factory's rows cannot do
-- this -- see ShowAbilitySettingsPopup below for why.
--
-- Add and Rename are the same dialog: a name, a confirm and a cancel.
local namePrompt

local function ShowNamePrompt(title, confirmLabel, initial, onCommit)
    if not namePrompt then
        local dimmer, panel = ns.MakeModal(340, 150, "namePrompt")
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
    local dimmer, panel = ns.MakeModal(360, 130, "abilitySettings")

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
    local dimmer, panel = ns.MakeModal(360, 130, "fallbackSettings")

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

    local lbl = ns.Font(prow, 13, nil, isActive and ns.THEME.accent or ns.THEME.muted)
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
        local c = ns.THEME.accent
        edit:SetTextColor(c.r, c.g, c.b, 1)
        local EUIg = ns.UI
        if EUIg and EUIg.ShowWidgetTooltip then
            EUIg.ShowWidgetTooltip(self, "Rename this preset.")
        end
    end)
    editHit:SetScript("OnLeave", function()
        local c = ns.THEME.muted
        edit:SetTextColor(c.r, c.g, c.b, 1)
        local EUIg = ns.UI
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
            local EUIg = ns.UI
            if EUIg and EUIg.ShowWidgetTooltip then
                EUIg.ShowWidgetTooltip(self,
                    "|cff0091edDelete Preset|r\nRemoves this preset and its list. Cannot be undone.")
            end
        end)
        del:SetScript("OnLeave", function()
            local c = ns.THEME.muted
            a:SetColorTexture(c.r, c.g, c.b, 0.85); b:SetColorTexture(c.r, c.g, c.b, 0.85)
            local EUIg = ns.UI
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
              text = "      |cff9a9ea6" .. c.name .. (c.userAdded and " (added by you)" or "") .. "|r",
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
          text = ("      |cff0091edLast:  %s|r"):format(db.voiceNone or "Call for an External"),
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

-- The boss's own preset choice: which of the spec's presets it calls its defensives
-- from. The Enable This Boss toggle lives on the boss-picker row in
-- RenderInstanceDetail, which gates this whole section.
-- Used by RenderInstanceDetail, the journal-sourced ability list. Returns y.
local function RenderBossHeader(parent, y, W, EUI, encounterID, specID)
    local _, h

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

    return y
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
    local EUI = callerEUI or ns.UI
    local W = EUI.Widgets

    local dimmer, panel = ns.MakeModal(480, 620, "customReminderEditor")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(uid and "Edit Reminder" or "New Reminder")

    local set = ns.CustomRemindersTable(false, encounterID)
    local existing = (set and uid) and set[uid] or nil
    local trig = (existing and existing.trigger) or { type = "pull" }

    local PAD = 20

    local function HoverTip(hit, tooltip)
        hit:SetScript("OnEnter", function(self)
            local EUIg = ns.UI
            if EUIg and EUIg.ShowWidgetTooltip then EUIg.ShowWidgetTooltip(self, tooltip) end
        end)
        hit:SetScript("OnLeave", function()
            local EUIg = ns.UI
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
    -- A single-corner anchor with no width ever set left tabBar's own geometry (and
    -- everything anchored off its LEFT/RIGHT points transitively -- every tab button)
    -- unresolvable: GetLeft/GetTop came back nil for the tab buttons even fully shown
    -- with alpha 1, confirmed live via debug prints. A second anchor point gives it a
    -- real width, same as every other full-width strip in this file already does.
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, TAB_TOP)
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
        local marker = ns.Solid(btn, "OVERLAY", ns.THEME.accent, 1)
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

        row.hl = ns.Solid(row, "BACKGROUND", ns.THEME.accent, 0.14)
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
            pickerHint:SetText("|cff9a9ea6Nothing recorded for this boss yet -- pull it with "
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
            pickerHint:SetText(("|cff9a9ea6+%d more not shown -- type the Spell ID below.|r")
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
                    feedback:SetText("|cff9a9ea6no spell name found -- boss-mod keys "
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
    -- Returned so a caller (ns.ShowBossReminderPicker) can hook OnHide and refresh its
    -- own list once this editor closes -- ignored by every other existing call site.
    return dimmer, panel
end

-- Profile tab: sharing (Reminder Packs) and the two global on/off switches.
-- Global in scope -- neither is "which boss" or "how it looks", both are
-- "what this profile does everywhere" -- so this is where they belong now
-- that the boss list has its own two tabs.
function ns.BuildProfileSettings(parent, y)
    local EUI = ns.UI
    local W   = EUI.Widgets
    local _, h
    local db = ns.DB()

    _, h = W:SectionHeader(parent, "PROFILES", y); y = y - h

    -- Values/order rebuilt per page build; a create/copy/delete refreshes the page, so the
    -- dropdown never shows a stale list.
    local profNames = ns.ListProfiles()
    local profValues = {}
    for _, name in ipairs(profNames) do profValues[name] = name end
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Active Profile",
          values = profValues, order = profNames,
          tooltip = "Which settings profile this character uses. Everything on these pages "
          .. "-- priority lists, per-boss orders, callouts, positions -- lives in the "
          .. "profile.",
          getValue = function() return ns.ActiveProfileName() end,
          setValue = function(v)
              ns.SwitchProfile(v)
              EUI:RefreshPage(true)
          end },
        { type = "label", text = "      Profiles are chosen per character." }
    ); y = y - h

    local profRow
    profRow, h = W:DualRow(parent, y,
        { type = "label", text = "" },
        { type = "label", text = "" }
    ); y = y - h
    if profRow then
        local function AfterChange()
            EUI:RefreshPage(true)
        end
        local newBtn = ns.Button(profRow._leftRegion, "New Profile", 110, 22, function()
            ShowNamePrompt("New Profile", "Create", "", function(text)
                local ok, err = ns.CreateProfile(text)
                if not ok then ns.Print(err) return end
                ns.SwitchProfile(text:match("^%s*(.-)%s*$"))
                AfterChange()
            end)
        end)
        newBtn:SetPoint("LEFT", profRow._leftRegion, "LEFT", 20, 0)
        ns.Tooltip(newBtn, "New Profile", "A fresh profile with default settings; this "
            .. "character switches to it.")
        local copyBtn = ns.Button(profRow._leftRegion, "Copy Profile", 110, 22, function()
            ShowNamePrompt("Copy Profile", "Copy", "", function(text)
                local ok, err = ns.CopyProfile(ns.ActiveProfileName(), text)
                if not ok then ns.Print(err) return end
                ns.SwitchProfile(text:match("^%s*(.-)%s*$"))
                AfterChange()
            end)
        end)
        copyBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)
        ns.Tooltip(copyBtn, "Copy Profile", "Duplicates this profile under a new name and "
            .. "switches to the copy.")
        local delBtn = ns.Button(profRow._rightRegion, "Delete", 90, 22, function()
            local name = ns.ActiveProfileName()
            local dimmer, panel = ns.MakeModal(340, 130, "profileDeleteConfirm")
            local head = ns.Font(panel, 14, "OUTLINE")
            head:SetPoint("TOP", panel, "TOP", 0, -16)
            head:SetText("Delete '" .. name .. "'?")
            local hint = ns.Font(panel, 11, nil, ns.THEME.muted)
            hint:SetPoint("TOP", head, "BOTTOM", 0, -8)
            hint:SetText("Cannot be undone.")
            local yes = ns.Button(panel, "Delete", 100, 24, function()
                local ok, err = ns.DeleteProfile(name)
                if not ok then ns.Print(err) end
                dimmer:Hide()
                AfterChange()
            end)
            yes:SetPoint("BOTTOM", panel, "BOTTOM", -56, 14)
            local no = ns.Button(panel, "Cancel", 100, 24, function() dimmer:Hide() end)
            no:SetPoint("BOTTOM", panel, "BOTTOM", 56, 14)
            dimmer:Show()
        end)
        delBtn:SetPoint("RIGHT", profRow._rightRegion, "RIGHT", -14, 0)
        ns.Tooltip(delBtn, "Delete", "Removes the active profile. Characters using it fall "
            .. "back to Default. The last profile cannot be deleted.")
    end

    -- ns.Reset used to be reachable through the host window's own reset control; with the
    -- addon standalone this row is its only door.
    local resetRow
    resetRow, h = W:DualRow(parent, y,
        { type = "label", text = "      Reset the active profile to default." },
        { type = "label", text = "" }
    ); y = y - h
    if resetRow and resetRow._rightRegion then
        local btn = ns.Button(resetRow._rightRegion, "Reset Profile", 110, 22, function()
            local dimmer, panel = ns.MakeModal(340, 130, "profileResetConfirm")
            local head = ns.Font(panel, 14, "OUTLINE")
            head:SetPoint("TOP", panel, "TOP", 0, -16)
            head:SetText("Reset '" .. tostring(ns.ActiveProfileName()) .. "'?")
            local hint = ns.Font(panel, 11, nil, ns.THEME.muted)
            hint:SetPoint("TOP", head, "BOTTOM", 0, -8)
            hint:SetText("Every setting in it returns to default. Cannot be undone.")
            local yes = ns.Button(panel, "Reset", 100, 24, function()
                if ns.Reset then ns.Reset() end
                dimmer:Hide()
                EUI:RefreshPage(true)
            end)
            yes:SetPoint("BOTTOM", panel, "BOTTOM", -56, 14)
            local no = ns.Button(panel, "Cancel", 100, 24, function() dimmer:Hide() end)
            no:SetPoint("BOTTOM", panel, "BOTTOM", 56, 14)
            dimmer:Show()
        end)
        btn:SetPoint("RIGHT", resetRow._rightRegion, "RIGHT", -14, 0)
        ns.Tooltip(btn, "Reset Profile", "Wipes the active profile's settings back to "
            .. "defaults. Other profiles are untouched.")
    end
    local packRow
    packRow, h = W:DualRow(parent, y,
        { type = "label", text = "      Share your Smart Reminders" },
        { type = "label", text = "" }
    ); y = y - h
    -- Not AttachInline here: it chains off a region's existing control, and this right
    -- half has none (its label field is blank) -- it fell back to anchoring off the
    -- region's own LEFT edge (the row's midpoint) instead, so the button sat in the
    -- row's LEFT half and overlapped the label text next to it regardless of width.
    -- Anchored to the region's own RIGHT edge directly instead.
    if packRow and packRow._rightRegion then
        local btn = ns.Button(packRow._rightRegion, "Share your Profile", 130, 22, function()
            if ns.ShowPackExport then ns.ShowPackExport() end
        end)
        btn:SetPoint("RIGHT", packRow._rightRegion, "RIGHT", -14, 0)
        ns.Tooltip(btn, "Share your Smart Reminders",
            "Everything a curator sets up -- priority lists, per-boss orders, callouts and "
            .. "written reminders -- as one string to share. A profile built from someone "
            .. "else's imported pack cannot be shared onward.")
    end
    local packRow2
    packRow2, h = W:DualRow(parent, y,
        { type = "label", text = "      Import Smart Reminder Profile" },
        { type = "label", text = "" }
    ); y = y - h
    if packRow2 and packRow2._rightRegion then
        local btn = ns.Button(packRow2._rightRegion, "Import Profile", 120, 22, function()
            if ns.ShowPackImport then ns.ShowPackImport() end
        end)
        btn:SetPoint("RIGHT", packRow2._rightRegion, "RIGHT", -14, 0)
        ns.Tooltip(btn, "Import Profile",
            "Paste a profile string. Nothing applies until you choose Replace or Merge, and a "
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
-- relocated to the selected boss's own Enable This Boss toggle (on the boss-picker row
-- in RenderInstanceDetail) instead of a per-instance shortcut.

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
--  Per-ability reminder picker: this ability's spot on the normal defensive
--  priority list, and (Custom Reminder tab) a written note of its own bound
--  straight to its own BigWigs cast/bar -- built on the Raid Reminder engine
--  (NaowhUI_SmartReminders_RaidReminders.lua) so it can be assigned to a role/class/
--  spec/name/subgroup too, the same NSRT/TimelineReminders-style tool
--  ns.ShowBossReminderPicker's boss-wide reminders already are.
-------------------------------------------------------------------------------
local RR_ROLE_VALUES = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local RR_ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

-- Categories join with " + " (AND, narrows), values within one category join with
-- "/" (OR, widens) -- mirrors ns.RaidReminderTargetsMe's own semantics exactly, so
-- what the summary says is what the targeting actually does.
local function RaidReminderTargetDesc(target)
    target = ns.NormalizeRaidReminderTarget(target)
    if target.all then return "Everyone" end

    local function Joined(set, label, order)
        if not (set and next(set)) then return nil end
        local list = {}
        for key in pairs(set) do list[#list + 1] = (label and label(key)) or tostring(key) end
        table.sort(list)
        return table.concat(list, order or "/")
    end

    local parts = {}
    local p
    p = Joined(target.roles, function(k) return RR_ROLE_VALUES[k] or k end); if p then parts[#parts + 1] = p end
    p = Joined(target.classes, function(k)
        local names = _G.LOCALIZED_CLASS_NAMES_MALE
        return (names and names[k]) or k
    end); if p then parts[#parts + 1] = p end
    p = Joined(target.specs, function(k)
        local ok, _, name = pcall(GetSpecializationInfoByID, k)
        return (ok and name) or tostring(k)
    end); if p then parts[#parts + 1] = p end
    p = Joined(target.names, nil, ", "); if p then parts[#parts + 1] = p end
    p = Joined(target.subgroups, function(k) return "Group " .. k end); if p then parts[#parts + 1] = p end

    if #parts == 0 then return "Everyone" end
    return table.concat(parts, " + ")
end

-- A reminder built from this ability's own cog carries abilitySpellID (the journal
-- spellID, not necessarily the same value as trigger.spellID -- the BigWigs key the
-- mechanic picker resolved it to) so it shows here instead of in the boss-wide list
-- ns.ShowBossReminderPicker renders. One per ability, same as the old bound-reminder
-- model this replaces -- first match wins.
local function FindBoundRaidReminder(encounterID, spellID)
    local set = ns.RaidRemindersTable and ns.RaidRemindersTable(false, encounterID)
    if not set then return nil, nil end
    for uid, r in pairs(set) do
        if r.abilitySpellID == spellID then return uid, r end
    end
    return nil, nil
end

local RR_DISPLAY_VALUES = { text = "Message", timer = "Timer", icon = "Icon", bar = "Bar",
    circle = "Circle", chat = "Chat Line", nameplateGlow = "Nameplate Glow",
    raidframeGlow = "Raid-Frame Glow" }
local RR_DISPLAY_ORDER = { "text", "timer", "icon", "bar", "circle", "chat",
    "nameplateGlow", "raidframeGlow" }

function ns.ShowAbilityReminderPicker(encounterID, ability, callerEUI)
    local EUI = callerEUI or ns.UI
    local W = EUI.Widgets

    -- Taller than before (was 440x480/body 320): a preset can carry up to MAX_SLOTS
    -- defensives, each now its own row below the preset dropdown. Grown by the same
    -- amount panel and body both, preserving the original's ~84px margin above Save/
    -- Cancel -- matches the 480x620 precedent this file already uses for its other,
    -- taller modal (the full custom reminder editor).
    local dimmer, panel = ns.MakeModal(440, 640, "abilityReminderPicker")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(ability.title or "Ability")

    local PAD = 20
    local TAB_TOP = -46

    local binding = ns.EnsureBinding(encounterID, ability.spellID)
    local specID = ns.CurrentSpec and ns.CurrentSpec()
    -- One warning time for the whole preset on this ability -- not per defensive within
    -- it (that granularity was tried and dropped: too fiddly for what it bought). Lazily
    -- initialized inside RebuildBody, same reasoning presetVal below documents: re-deriving
    -- it on every rebuild would stomp an in-progress drag the instant switching tabs or
    -- presets triggered one.
    local leadTimeVal

    -- Same destroy-and-recreate idiom as the custom reminder editor's own dynFrame: the
    -- old body is hidden and dropped rather than cleared field by field, since GetChildren
    -- only ever returns child FRAMES, not the label FontStrings this also has to remove.
    local body
    -- presetVal is written by the dropdown built in RebuildBody and read back by Save()
    -- -- it has to outlive any single rebuild, since a pick must not be lost if switching
    -- tabs or presets forces a reflow later.
    local presetVal

    -- RebuildBody is assigned below (forward-declared here so SelectPageTab, built next,
    -- can close over it) -- same forward-reference shape RebuildTriggerFields uses in
    -- ShowRaidReminderEditor above.
    local RebuildBody

    -- Two tabs, independent of each other rather than mutually exclusive like the old
    -- single-toggle model: Defensive Preset (unchanged) and Custom Reminder, a written
    -- note bound straight to this ability's own BigWigs cast/bar. An ability can carry
    -- both -- the defensive callout is always for you; a Custom Reminder can target
    -- anyone, so silencing one when the other is set would be wrong as often as right.
    local pageTab = "defensive"
    local tabBtns = {}
    local function SelectPageTab(id)
        pageTab = id
        for tid, btn in pairs(tabBtns) do
            local on = (tid == id)
            btn.marker:SetShown(on)
            local c = on and ns.THEME.fg or ns.THEME.muted
            btn.label:SetTextColor(c.r, c.g, c.b, 1)
        end
        RebuildBody()
    end
    local function AddPageTab(id, text, anchorTo)
        local btn = CreateFrame("Button", nil, panel)
        btn:SetHeight(22)
        local lbl = ns.Font(btn, 12, nil, ns.THEME.muted)
        lbl:SetText(text)
        btn:SetSize(lbl:GetStringWidth() + 4, 22)
        lbl:SetPoint("CENTER")
        if anchorTo then btn:SetPoint("LEFT", anchorTo, "RIGHT", 18, 0)
        else btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP) end
        local marker = ns.Solid(btn, "OVERLAY", ns.THEME.accent, 1)
        marker:SetPoint("BOTTOMLEFT", 0, -3)
        marker:SetPoint("BOTTOMRIGHT", 0, -3)
        marker:SetHeight(2)
        marker:Hide()
        btn:SetScript("OnClick", function() SelectPageTab(id) end)
        btn.label, btn.marker = lbl, marker
        tabBtns[id] = btn
        return btn
    end
    local defTabBtn = AddPageTab("defensive", "Defensive Preset")
    AddPageTab("custom", "Custom Reminder", defTabBtn)
    defTabBtn.marker:Show()
    defTabBtn.label:SetTextColor(ns.THEME.fg.r, ns.THEME.fg.g, ns.THEME.fg.b, 1)

    RebuildBody = function()
        if body then body:Hide() end
        body = CreateFrame("Frame", nil, panel)
        body:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP - 30)
        body:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, TAB_TOP - 30)
        -- An explicit height, not just the two TOP anchors -- matching dynFrame in the full
        -- custom reminder editor below (SetSize) and messageBody/triggerBody in the same
        -- (SetHeight): a frame anchored on only one edge never resolves a height on its
        -- own, and every rebuilt-body frame elsewhere in this file sets one for that reason.
        body:SetHeight(480)

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
        -- Fixed width instead of stretching to the body's edge, matching every other
        -- field this popup lines up on both edges.
        local FIELD_W = 260
        -- A single dropdown row, fixed width to FIELD_W -- BuildDropdownControl
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

        if pageTab == "defensive" then
            -- One preset, not a hand-built list: this ability draws from whichever preset
            -- is chosen here, the same way a boss or a custom reminder already draws from
            -- one -- edited on the Setup page, not duplicated per ability.
            local presets = ns.ListPresets(specID)
            if #presets == 0 then
                local hint = ns.Font(body, 11, nil, ns.THEME.muted)
                hint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                hint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                hint:SetWordWrap(true)
                hint:SetText("|cff9a9ea6No presets yet -- add one on the Setup page "
                    .. "first.|r")
                by = by - 34
            else
                local presetValues, presetOrder = {}, {}
                for i = 1, #presets do
                    presetValues[presets[i].key] = presets[i].name
                    presetOrder[i] = presets[i].key
                end
                -- Derived from binding.preset ONLY the first time this body is ever
                -- built (presetVal starts nil, and no real preset key is ever nil) --
                -- shows the effective default (this boss's preset, else the spec's
                -- active one) until this ability actually gets its own pick, matching
                -- the same fallback EffectiveList itself uses at runtime. A rebuild
                -- triggered by the dropdown's OWN change must never re-derive this: it
                -- would re-read binding.preset, still the OLD value until Save() runs,
                -- and stomp the pick right back to it -- which is exactly what made the
                -- dropdown look stuck on the old preset the instant a different one was
                -- clicked (the same trap leadTimeVal's own init below already has to
                -- dodge, just missed here when RebuildBody() was added to this one).
                if presetVal == nil then
                    presetVal = binding.preset or ns.BossPresetKey(specID, encounterID)
                        or ns.ActivePresetKey(specID) or presetOrder[1]
                end
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

            -- Lazily initialized, not re-derived on every rebuild (see its own comment
            -- above) -- an edit that triggers a rebuild (switching presets or tabs) must
            -- not stomp a drag still in progress.
            if leadTimeVal == nil then
                leadTimeVal = binding.leadTime or (ns.DB().leadTime or 3)
            end
            Label("Warning Time (seconds before impact)")
            local trackFrame, valBox = EUI.BuildSliderCore(body, 200, 4, 12, 40, 22, 12,
                1, 0, 10, 1,
                function() return leadTimeVal end,
                function(v) leadTimeVal = v end)
            trackFrame:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            valBox:SetPoint("LEFT", trackFrame, "RIGHT", 10, 0)
            by = by - 32
        else
            local hint = ns.Font(body, 11, nil, ns.THEME.muted)
            hint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            hint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            hint:SetJustifyH("LEFT")
            hint:SetWordWrap(true)
            hint:SetText("A written note tied straight to this ability's own BigWigs "
                .. "cast or bar -- assignable to a role, class, spec, player or "
                .. "subgroup, not just you.")
            by = by - 36

            local uid, entry = FindBoundRaidReminder(encounterID, ability.spellID)
            if entry then
                local nameLbl = ns.Font(body, 12, nil, ns.THEME.fg)
                nameLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                nameLbl:SetText(entry.name or "Reminder")
                by = by - 18

                local descLbl = ns.Font(body, 11, nil, ns.THEME.muted)
                descLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                descLbl:SetText(RaidReminderTargetDesc(entry.target) .. "  -- "
                    .. (RR_DISPLAY_VALUES[entry.display and entry.display.type] or "Message"))
                by = by - 30

                local editBtn = ns.Button(body, "Edit", 100, 26, function()
                    local nestedDimmer = ns.ShowRaidReminderEditor(
                        encounterID, uid, EUI, nil, ability.spellID)
                    if nestedDimmer then nestedDimmer:HookScript("OnHide", RebuildBody) end
                end)
                editBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                local removeBtn = ns.Button(body, "Remove", 100, 26, function()
                    local writeSet = ns.RaidRemindersTable(false, encounterID)
                    if writeSet then writeSet[uid] = nil end
                    RebuildBody()
                end)
                removeBtn:SetPoint("LEFT", editBtn, "RIGHT", 10, 0)
                by = by - 32
            else
                local noneLbl = ns.Font(body, 11, nil, ns.THEME.muted)
                noneLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                noneLbl:SetText("None yet for this ability.")
                by = by - 26

                local addBtn = ns.Button(body, "+ Add a Custom Reminder", 200, 26, function()
                    local nestedDimmer = ns.ShowRaidReminderEditor(
                        encounterID, nil, EUI, nil, ability.spellID)
                    if nestedDimmer then nestedDimmer:HookScript("OnHide", RebuildBody) end
                end)
                addBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                by = by - 32
            end
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

    RebuildBody()

    -- Only the Defensive Preset tab's settings -- the Custom Reminder tab saves
    -- immediately through its own nested editor's Save button (ns.ShowRaidReminderEditor),
    -- there's nothing of its deferred to this button.
    local function Save()
        -- "defensive" unconditionally: nothing on this picker writes "custom" anymore
        -- (the Custom Reminder tab is additive now, not a mode switch -- see the header
        -- comment above), so this also self-heals a profile with a stale "custom" from
        -- before that change, which would otherwise silently suppress this ability's
        -- Pre-Selected Defensives pick forever (ns.HandleBigWigsAbility's own gate).
        binding.mode = "defensive"
        binding.preset = presetVal
        -- Per-defensive leadTimeBySpell was tried and dropped -- too fiddly for what it
        -- bought -- back to one warning time for the whole preset on this ability. No
        -- migration: any leftover leadTimeBySpell from that build is simply never read
        -- again once this saves.
        binding.leadTimeBySpell = nil
        binding.leadTime = (leadTimeVal ~= (ns.DB().leadTime or 3)) and leadTimeVal or nil
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

    -- Single source of truth with the runtime's own default (ns.AbilityEnabledForBinding),
    -- so the checkbox can never disagree with what actually calls out. Unticking here keeps
    -- the ability on the page but silent; removing it from the page is the Add Ability
    -- picker's job.
    local enabled = ability.spellID and ns.AbilityEnabledForBinding(encounterID, ability.spellID)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
    check:SetChecked(enabled)
    check:SetScript("OnClick", function(self)
        if not ability.spellID then self:SetChecked(false); return end
        ns.EnsureBinding(encounterID, ability.spellID).enabled = self:GetChecked() and true or false
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

    local test = ns.Button(row, "Test", 44, 26, function()
        if not ability.spellID then
            ns.Print("|cffff6060this journal entry has no spell id to bind to|r")
            return
        end
        ns.TestFireAbility(encounterID, ability.spellID)
    end)
    test:SetPoint("TOPRIGHT", cog, "TOPLEFT", -4, 0)

    local remove = ns.Button(row, "X", 26, 26, function()
        ns.ConfirmRemoveAbility(encounterID, ability, EUI)
    end)
    remove:SetPoint("TOPRIGHT", test, "TOPLEFT", -4, 0)
    remove.label:SetTextColor(1, 0.38, 0.38, 1)
    ns.Tooltip(remove, "Remove Ability",
        "Take this ability off the boss. Its preset and warning time go with it.")

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
    title:SetPoint("RIGHT", remove, "LEFT", -8, 0)
    title:SetJustifyH("LEFT")
    title:SetText((ability.title or "?") .. (roleTag and ("  " .. roleTag) or ""))

    local desc = ns.Font(row, 11, nil, ns.THEME.muted)
    desc:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -20)
    desc:SetPoint("RIGHT", remove, "LEFT", -8, 0)
    desc:SetHeight(ABILITY_ROW_H - 24)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    local descText = ability.description or "|cff9a9ea6No description in the journal.|r"
    if restTag then descText = ("|cff9a9ea6[%s]|r  "):format(restTag) .. descText end
    desc:SetText(descText)

    local div = ns.Solid(row, "ARTWORK", ns.THEME.line, 1)
    div:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    div:SetHeight(1)

    return y - ABILITY_ROW_H
end

-- The selected instance's own view: Share Profile / Select Boss, the boss's own
-- Enable/Preset header (RenderBossHeader), then
-- every ability the Dungeon Journal lists for that boss -- journal icon, description
-- and role flags (Tank/Dps/Healer) included, all data ns.ScrapeBosses already collects
-- (boss.abilities).
local function RenderInstanceDetail(parent, y, W, EUI, inst, specID)
    local boss = inst.bosses[selectedBossIdx[inst.id] or 1]

    if not boss then
        local hint = ns.Font(parent, 12, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        hint:SetText("This instance has no bosses in the journal yet.")
        return y - 20
    end

    -- One row carries the whole boss selection state: the picker on the left (with the
    -- boss-wide reminders cog chained inline), Enable This Boss on the right. The picker
    -- is a real dropdown slot keyed by boss index.
    local db = ns.DB()
    local bossOn = not (db.bossOff and db.bossOff[tostring(boss.encounterID)])
    local bossValues, bossOrder = {}, {}
    for b = 1, #inst.bosses do
        bossValues[b] = inst.bosses[b].name
        bossOrder[b] = b
    end
    local _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Boss", width = 220,
          values = bossValues, order = bossOrder,
          tooltip = "Which of this instance's bosses the options below apply to.",
          getValue = function() return selectedBossIdx[inst.id] or 1 end,
          setValue = function(v)
              selectedBossIdx[inst.id] = v
              EUI:RefreshPage(true)
          end },
        { type = "toggle", text = "Enable This Boss",
          tooltip = "Off means this boss makes no alerts at all -- no defensives, no "
          .. "reminders, nothing -- and its options below disappear until it is back on.",
          getValue = function() return bossOn end,
          setValue = function(v)
              if type(db.bossOff) ~= "table" then db.bossOff = {} end
              db.bossOff[tostring(boss.encounterID)] = (not v) or nil
              if next(db.bossOff) == nil then db.bossOff = nil end
              ns.RefreshRuntime()
              EUI:RefreshPage(true)
          end }
    ); y = y - h
    if not bossOn then return y end

    y = RenderBossHeader(parent, y, W, EUI, boss.encounterID, specID)

    y = y - 10
    -- The shipped-data curated list (extracted from GetOptions with a script) was tried
    -- and dropped in 0824t for systematically missing abilities; re-auditing its misses
    -- against the module source showed the extractor's parsing was at fault ({id, flag}
    -- table entries), plus abilities BigWigs does not track at all -- which the engine
    -- can never fire anyway. Reading the installed modules at runtime has neither
    -- problem, so this listing is exact by construction.
    local abilities = BigWigsAbilities(boss.encounterID, boss.abilities) or boss.abilities
    if not (abilities and #abilities > 0) then
        local hint = ns.Font(parent, 12, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        hint:SetText("No abilities listed in the journal for this boss.")
        return y - 20
    end

    -- Only what the player has actually added. A boss starts blank: the journal lists
    -- everything a fight does, most of which is not a tank hit, and a page of rows that
    -- are all off by default reads as broken rather than as a choice.
    local added = {}
    for i = 1, #abilities do
        local a = abilities[i]
        if a.spellID and ns.AbilityAdded(boss.encounterID, a.spellID) then
            added[#added + 1] = a
        end
    end

    local addBtn = ns.Button(parent, "+ Add Ability", 130, 24, function()
        ns.ShowAbilityPicker(boss.encounterID, abilities, EUI)
    end)
    addBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    y = y - 30

    if #added == 0 then
        local hint = ns.Font(parent, 12, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        hint:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        hint:SetText("No abilities picked for this boss yet. Add Ability lists everything "
            .. "the journal has for the fight, with the known tank hits marked.")
        return y - 34
    end

    local lastStage
    for i = 1, #added do
        local a = added[i]
        if a.stage and a.stage ~= lastStage then
            lastStage = a.stage
            local hdr = ns.Font(parent, 11, nil, ns.THEME.muted)
            hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 6)
            hdr:SetText(a.stage)
            y = y - 24
        end
        y = RenderAbilityRow(parent, y, boss.encounterID, a, specID, EUI)
    end

    -- Custom Reminders and Raid/Dungeon Reminders for this boss used to render inline
    -- here; both moved behind the cog next to the boss picker above
    -- (ns.ShowBossReminderPicker) so picking a boss once covers everything about it,
    -- rather than each kind of reminder needing its own scroll down this list.

    return y
end

-- Dungeon Bosses / Raid Bosses tab: a pure navigation list on the left -- one row per
-- instance, click to select, no per-row toggle here anymore (the old bulk on/off per
-- instance is still reachable; it lives on the selected boss's own Enable This Boss row,
-- same as it always did for a single boss) -- and the selected instance's detail on the
-- right.
function ns.BuildBossListPage(parent, y, isRaid)
    local EUI = ns.UI
    local W   = EUI.Widgets
    local _, h
    local specID = ns.CurrentSpec()

    -- W:SectionHeader is a fixed widget -- left-aligned, one set colour, a 40px band with
    -- the label sitting near its bottom -- no centering or colour override exists on it.
    -- Hand-built here instead: centered, Naowh's gold, and a fraction of that height, which
    -- is most of what was leaving a gap between the tab strip and the content below.
    local pageHead = ns.Font(parent, 14, nil, ns.THEME.accent)
    pageHead:SetPoint("TOP", parent, "TOP", 0, y)
    pageHead:SetJustifyH("CENTER")
    pageHead:SetText(isRaid and "Raid Bosses" or "Dungeon Bosses")
    y = y - 22

    -- Raid-only on purpose. The gate asks whether the OTHER tank has the boss, and that
    -- question only exists with two of them -- a five-man has one tank holding every boss
    -- unit, so the check always answers yes there and changes nothing. It sat on the Setup
    -- tab looking like a global behaviour switch.
    if isRaid then
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Only While I Have the Boss",
              tooltip = "For raids with two tanks: stay quiet when the boss is on the other "
              .. "tank. Checked at the moment the warning fires -- threat first, then the "
              .. "boss's actual target -- and whenever the game keeps the answer sealed the "
              .. "alert plays anyway, because a spare callout costs less than a silent tank "
              .. "buster. It lives here because it only matters with two tanks -- in a "
              .. "dungeon you normally hold every boss yourself, so it rarely changes "
              .. "anything there.",
              getValue = function() return ns.DB().aggroOnly end,
              setValue = function(v) ns.DB().aggroOnly = v end },
            { type = "label", text = "" }
        ); y = y - h
    end

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
        local bg = ns.Solid(row, "BACKGROUND", ns.THEME.accent, isSel and 0.16 or 0)
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

-- Removing an ability drops its binding, and the preset and warning time saved on it go
-- too, so it asks first. Named in the question rather than a bare "are you sure": the
-- button that opens this sits on a row among several near-identical ones.
function ns.ConfirmRemoveAbility(encounterID, ability, callerEUI)
    local EUI = callerEUI or ns.UI
    local dimmer, panel = ns.MakeModal(400, 190, "abilityRemoveConfirm")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("Remove Ability")

    local body = ns.Font(panel, 12, nil, ns.THEME.fg)
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -48)
    body:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    body:SetText(("Remove |cff0091ed%s|r from this boss?"):format(ability.title or "this ability"))

    local warn = ns.Font(panel, 11, nil, ns.THEME.muted)
    warn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -84)
    warn:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    warn:SetJustifyH("LEFT")
    warn:SetWordWrap(true)
    warn:SetText("Its defensive preset and warning time go with it. Adding it back later "
        .. "starts that ability fresh.")

    local remove = ns.Button(panel, "Remove", 110, 26, function()
        -- EnsureBinding first: a binding saved under this ability's journal alias reads
        -- back fine but would survive a delete keyed on the current id. Ensuring migrates
        -- the alias onto that id, so the nil below actually removes it.
        ns.EnsureBinding(encounterID, ability.spellID)
        local set = ns.AbilityBindingsTable(false, encounterID)
        if set then set[ability.spellID] = nil end
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end)
    remove:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -6, 16)
    remove.label:SetTextColor(1, 0.38, 0.38, 1)

    local cancel = ns.Button(panel, "Cancel", 110, 26, function() dimmer:Hide() end)
    cancel:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 6, 16)

    dimmer:Show()
    return dimmer
end

-- Choose which of a boss's abilities get reminders; the boss page lists exactly these.
-- The curated tank list marks rows here instead of pre-selecting them, so it still says
-- which hits are the real tank busters without choosing for the player.
--
-- Additive only. An ability already on the boss shows ticked and inert here; removing one
-- is the X on its own row, which confirms first (ns.ConfirmRemoveAbility), so a binding is
-- never destroyed by an untick that reads like a filter.
function ns.ShowAbilityPicker(encounterID, abilities, callerEUI)
    local EUI = callerEUI or ns.UI
    local PANEL_W = 460
    local dimmer, panel = ns.MakeModal(PANEL_W, 560, "abilityPicker")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("Add Abilities")

    local hint = ns.Font(panel, 11, nil, ns.THEME.muted)
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -42)
    hint:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("Tick the abilities you want reminders for. Marked ones are what the "
        .. "addon knows to be tank hits on this boss. Already-added abilities are ticked "
        .. "and stay put; remove one with the X on its row.")

    -- Scrolled rather than capped: a journal boss can list well past a screenful, and this
    -- is the only place an ability can be switched on, so a row that does not fit still has
    -- to be reachable.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -82)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -40, 54)
    local content = CreateFrame("Frame", nil, scroll)
    -- Sized off the panel, not scroll:GetWidth(): the scroll frame is anchor-derived and
    -- still reads 0 wide until a layout pass has run.
    content:SetSize(PANEL_W - 62, 1)
    scroll:SetScrollChild(content)

    local ok, err = pcall(function()
        local y, shown = 0, 0
        for i = 1, #abilities do
            local a = abilities[i]
            if a.spellID then
                shown = shown + 1
                local row = CreateFrame("Frame", nil, content)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                row:SetHeight(26)

                local already = ns.AbilityAdded(encounterID, a.spellID)
                local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                check:SetSize(22, 22)
                check:SetPoint("LEFT", row, "LEFT", 0, 0)
                check:SetChecked(already)
                if already then
                    check:Disable()
                else
                    check:SetScript("OnClick", function()
                        ns.EnsureBinding(encounterID, a.spellID).enabled = true
                        ns.RefreshRuntime()
                        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
                    end)
                end

                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(20, 20)
                icon:SetPoint("LEFT", check, "RIGHT", 4, 0)
                if a.icon then icon:SetTexture(a.icon) end
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local curated = ns.TANK_ABILITIES and ns.TANK_ABILITIES[a.spellID]
                local lbl = ns.Font(row, 11, nil, ns.THEME.fg)
                lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                lbl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(false)
                lbl:SetText((a.name or ("Spell " .. a.spellID))
                    .. (curated and "  |cff0091ed[tank hit]|r" or "")
                    .. (already and "  |cff9a9ea6added|r" or ""))

                y = y - 28
            end
        end
        if shown == 0 then
            local none = ns.Font(content, 11, nil, ns.THEME.muted)
            none:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            none:SetText("Nothing in the journal for this boss carries a spell id.")
        end
        content:SetHeight(math.max(1, math.abs(y)))
    end)
    if not ok then
        local errText = ns.Font(content, 11, nil, { r = 1, g = 0.35, b = 0.35 })
        errText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        errText:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        errText:SetJustifyH("LEFT")
        errText:SetWordWrap(true)
        errText:SetText("Failed to build this: " .. tostring(err))
        ns.Print("|cffff6060ability add picker|r: " .. tostring(err))
    end

    ns.Button(panel, "Close", 100, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)
    dimmer:Show()
    return dimmer
end

-------------------------------------------------------------------------------
--  Raid/Dungeon Reminders and Custom Reminders for one boss, behind the cog next to
--  that boss's picker (RenderInstanceDetail) -- a different shape than the per-ability
--  cog (ShowAbilityReminderPicker), which configures one ability's own tank-buster
--  callout. Both used to be full top-level tabs, each with its own boss dropdown
--  duplicating the one already on Dungeon/Raid Bosses; folded in here so a boss is only
--  ever picked once. Engine for raid reminders (data, targeting, BigWigs scheduling,
--  the four displays) lives in NaowhUI_SmartReminders_RaidReminders.lua; this is the
--  authoring UI on top of it, kept here since it needs the same tab/mechanic-picker/
--  HoverTip scaffolding ShowCustomReminderEditor/ShowRaidReminderEditor already built.
--  Ability-bound reminders (r.abilitySpellID set) are excluded below -- those live on
--  their own ability's cog instead (ShowAbilityReminderPicker's Custom Reminder tab).
-------------------------------------------------------------------------------
-- Opened from the cog next to a boss's picker (RenderInstanceDetail). isRaid decides
-- which of RaidRemindersTable's two kinds this boss's encounterID belongs to (the same
-- split ns.BuildBossListPage's left column already keys instances on), not something
-- picked here.
-- Which difficulty's recording the observed section is showing, per encounter. Page-local
-- rather than saved: it is a viewing choice, not a setting.
local observedDiffPick = {}

-- One recorded ability: icon, name, then each observed occurrence as a clickable time.
-- Clicking opens the reminder editor already pointed at that moment.
local function ObservedRow(content, sid, list, encounterID, isRaid, EUI, onChanged, y)
    local row = CreateFrame("Frame", nil, content)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:SetHeight(24)

    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexture((info and info.iconID) or 134400)

    local lbl = ns.Font(row, 11, nil, ns.THEME.fg)
    lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    lbl:SetWidth(150)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetText((info and info.name) or ("Spell " .. sid))

    -- How many time chips actually fit. This row renders on two very different surfaces --
    -- the 480px cog modal and the much wider options tab -- and a boss with a dozen
    -- recorded occurrences would run straight off the narrow one.
    local avail = content:GetWidth()
    if avail <= 0 then avail = 440 end
    local fits = math.max(1, math.floor((avail - 190) / 70))
    local shownCount = math.min(#list, fits)

    local anchor = lbl
    for i = 1, shownCount do
        local slot = list[i]
        if slot and slot.t then
            local phased = slot.stage and slot.stage > 1 and slot.ts
            local shown = phased and slot.ts or slot.t
            local label = ("%d:%02d"):format(math.floor(shown / 60), math.floor(shown % 60))
            if phased then label = "P" .. slot.stage .. " " .. label end
            local chip = ns.Button(row, label, phased and 62 or 46, 20, function()
                -- A phase-anchored observation seeds a phase trigger, since a pull-relative
                -- time for a later phase is only true for a pull of the same speed.
                local seed
                if phased then
                    seed = { trigger = { type = "stage", stage = slot.stage,
                        delay = math.floor(slot.ts * 10 + 0.5) / 10 },
                        name = (info and info.name) or nil }
                else
                    seed = { trigger = { type = "pull",
                        delay = math.floor(slot.t * 10 + 0.5) / 10 },
                        name = (info and info.name) or nil }
                end
                local d = ns.ShowRaidReminderEditor(encounterID, nil, EUI, isRaid, nil, seed)
                if d then d:HookScript("OnHide", onChanged) end
            end)
            chip:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
            local spread = (slot.hi and slot.lo) and (slot.hi - slot.lo) or 0
            local spreadNote = (spread > 3)
                and ("Varies by %.0fs across pulls -- treat it as approximate."):format(spread)
                or "Consistent across pulls."
            ns.Tooltip(chip, label,
                ("Occurrence %d, averaged over %d pull(s). %s Click to build a reminder "
                .. "for this moment."):format(i, slot.n or 1, spreadNote))
            anchor = chip
        end
    end
    if #list > shownCount then
        local more = ns.Font(row, 10, nil, ns.THEME.muted)
        more:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
        more:SetText(("+%d more"):format(#list - shownCount))
    end
    return row
end

-- The boss-scoped reminder lists -- RAID/DUNGEON REMINDERS, CUSTOM REMINDERS, the
-- anchors button and both Add buttons -- shared verbatim by the cog picker modal and
-- the Custom Reminders tab, so the two surfaces cannot drift. Renders into `content`
-- starting at startY (negative running offset) and returns the final y. opts.onChanged
-- runs after any edit/delete/add closes, and nested editors hook it onto their OnHide.
function ns.BuildBossReminderSections(content, encounterID, isRaid, startY, opts)
    local EUI = (opts and opts.EUI) or ns.UI
    local onChanged = (opts and opts.onChanged) or function() end

    local function EditRaidReminder(uid)
        local nestedDimmer = ns.ShowRaidReminderEditor(encounterID, uid, EUI, isRaid)
        if nestedDimmer then nestedDimmer:HookScript("OnHide", onChanged) end
    end
    local function EditCustomReminder(uid)
        local nestedDimmer = ns.ShowCustomReminderEditor(encounterID, uid, EUI)
        if nestedDimmer then nestedDimmer:HookScript("OnHide", onChanged) end
    end

    local y = startY or 0

    -- Hand-rolled rows throughout, not W:SectionHeader/W:DualRow -- those are built
    -- for a full-width options page (row backgrounds, hover-tags, a half-column each
    -- slot always reserves) and look wrong crammed into a 480px floating popup, the
    -- same reasoning ShowAbilityReminderPicker's own compact Label/Box helpers state.
    local function Header(text)
        local lbl = ns.Font(content, 12, nil, ns.THEME.accent)
        lbl:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        lbl:SetText(text)
        y = y - 20
    end

    local function NoneRow()
        local lbl = ns.Font(content, 11, nil, ns.THEME.muted)
        lbl:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        lbl:SetText("None yet for this boss.")
        y = y - 20
    end

    -- One reminder: an enabled checkbox, name + description, Edit/Delete on the right.
    local function ReminderRow(name, desc, getEnabled, setEnabled, editFn, deleteFn)
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        row:SetHeight(24)

        local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("LEFT", row, "LEFT", 0, 0)
        check:SetChecked(getEnabled())
        check:SetScript("OnClick", function(self)
            setEnabled(self:GetChecked() and true or false)
        end)

        local delBtn = ns.Button(row, "Delete", 56, 22, deleteFn)
        delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        local editBtn = ns.Button(row, "Edit", 46, 22, editFn)
        editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)

        local lbl = ns.Font(row, 11, nil, ns.THEME.fg)
        lbl:SetPoint("LEFT", check, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", editBtn, "LEFT", -8, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(name .. "  |cff9a9ea6(" .. desc .. ")|r")

        y = y - 26
    end

    if ns.ShowRaidReminderAnchorConfig then
        local anchorBtn = ns.Button(content, "Customize Anchors", 160, 26, function()
            ns.ShowRaidReminderAnchorConfig()
        end)
        anchorBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        y = y - 34
    end

    -- What this boss actually did, from the player's own pulls. Rendered above the
    -- reminder lists because it is the raw material they are built from: pick a time here
    -- and the editor opens already pointed at it.
    local diffs = ns.ObservedDifficulties and ns.ObservedDifficulties(encounterID) or {}
    Header("OBSERVED TIMINGS")
    if #diffs > 0 then
        local pick = observedDiffPick[encounterID]
        local chosen
        for _, d in ipairs(diffs) do
            if d.key == pick then chosen = d break end
        end
        chosen = chosen or diffs[1]
        local block = ns.ObservedFor(encounterID, tonumber(chosen.key))

        if #diffs > 1 then
            -- Only when there is a choice to make: the same boss on two difficulties casts
            -- on genuinely different schedules and the two must never be read as one.
            local dvalues, dorder = {}, {}
            for _, d in ipairs(diffs) do
                local dn = GetDifficultyInfo and GetDifficultyInfo(tonumber(d.key))
                dvalues[d.key] = ("%s (%d pulls)"):format(tostring(dn or d.key), d.pulls or 0)
                dorder[#dorder + 1] = d.key
            end
            local ddBtn = EUI.BuildDropdownControl(content, 220, content:GetFrameLevel() + 4,
                dvalues, dorder,
                function() return chosen.key end,
                function(v) observedDiffPick[encounterID] = v; onChanged() end)
            ddBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            y = y - 30
        end

        local rows = {}
        for sid, list in pairs(block and block.casts or {}) do
            rows[#rows + 1] = { sid = sid, list = list }
        end
        table.sort(rows, function(a, b)
            local at = a.list[1] and a.list[1].t or 0
            local bt = b.list[1] and b.list[1].t or 0
            return at < bt
        end)

        if #rows == 0 then
            NoneRow()
        else
            for i = 1, #rows do
                ObservedRow(content, rows[i].sid, rows[i].list, encounterID, isRaid, EUI,
                    onChanged, y)
                y = y - 26
            end
        end

        local cover = ns.Font(content, 10, nil, ns.THEME.muted)
        cover:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        cover:SetText(("from %d pull(s), longest %d:%02d -- click a time to build a "
            .. "reminder from it"):format(block and block.pulls or 0,
            math.floor((block and block.longest or 0) / 60), (block and block.longest or 0) % 60))
        y = y - 22
    else
        -- Says which of the two reasons it is. They need different actions from the
        -- player, and neither is guessable from an empty list.
        local src = ns.BossSource and ns.BossSource() or "timeline"
        local why = ns.Font(content, 11, nil, ns.THEME.muted)
        why:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        why:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        why:SetJustifyH("LEFT")
        why:SetWordWrap(true)
        if src ~= "bigwigs" and src ~= "dbm" then
            -- Boss Addon only lands on Timeline now by an explicit pick or with no boss
            -- mod installed at all, and those need different things from the player.
            if not (_G.BigWigsLoader or _G.DBM) then
                why:SetText("Recording rides BigWigs or DBM broadcasts and neither is "
                    .. "installed. With one of them running, every boss you pull records "
                    .. "itself here -- there is nothing to switch on.")
            else
                why:SetText("Boss Addon is set to Blizzard Timeline, which keeps ability "
                    .. "identity secret, so there is nothing to record from. Switch it to "
                    .. "BigWigs or DBM on the Setup tab.")
            end
        else
            why:SetText(("Nothing recorded for this boss yet. Pull it with %s running and "
                .. "its timings appear here once the fight ends. It has to be a real boss "
                .. "encounter -- trash fires no encounter events, so it records nothing.")
                :format(src == "dbm" and "DBM" or "BigWigs"))
        end
        why:SetHeight(math.max(16, why:GetStringHeight() + 4))
        y = y - why:GetHeight() - 10
    end

    Header((isRaid and "RAID" or "DUNGEON") .. " REMINDERS")
    local rrSet = ns.RaidRemindersTable and ns.RaidRemindersTable(false, encounterID)
    local rrList = {}
    if rrSet then
        for uid, r in pairs(rrSet) do
            if not r.abilitySpellID then rrList[#rrList + 1] = { uid = uid, r = r } end
        end
        table.sort(rrList, function(a, b) return (a.r.name or "") < (b.r.name or "") end)
    end
    if #rrList == 0 then
        NoneRow()
    else
        for i = 1, #rrList do
            local uid, r = rrList[i].uid, rrList[i].r
            local rowName = r.name or "Reminder"
            local desc = RaidReminderTargetDesc(r.target)
            local trig = r.trigger
            if trig and trig.type == "pull" and trig.delay then
                desc = ("+%gs  %s"):format(trig.delay, desc)
            elseif trig and trig.type == "stage" and trig.delay then
                desc = ("P%d +%gs  %s"):format(trig.stage or 0, trig.delay, desc)
            end
            ReminderRow(rowName, desc,
                function() return r.enabled ~= false end,
                function(v) r.enabled = v end,
                function() EditRaidReminder(uid) end,
                function()
                    local writeSet = ns.RaidRemindersTable(false, encounterID)
                    if writeSet then writeSet[uid] = nil end
                    onChanged()
                end)
        end
    end
    y = y - 6

    local addRRBtn = ns.Button(content,
        isRaid and "+ Add a Raid Reminder" or "+ Add a Dungeon Reminder", 190, 26, function()
            -- A thrown error here would otherwise be indistinguishable from a dead
            -- button -- WoW hides script errors by default, so an uncaught throw looks
            -- exactly like nothing happening at all.
            local okClick, clickErr = pcall(EditRaidReminder, nil)
            if not okClick then
                ns.Print("|cffff6060could not open the raid reminder editor|r: "
                    .. tostring(clickErr))
            end
        end)
    addRRBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - 34

    -- Excludes "spell"-triggered entries -- those are the per-ability picker's own
    -- Custom Reminder mode (ShowAbilityReminderPicker), already editable from that
    -- ability's row; listing them here too would let this generic editor delete the
    -- reminder object while the ability's binding still says "custom", leaving that
    -- ability silently unable to fire either kind of callout.
    Header("CUSTOM REMINDERS")
    local crSet = ns.CustomRemindersTable and ns.CustomRemindersTable(false, encounterID)
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
        NoneRow()
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
            ReminderRow(r.name or "Reminder", trigDesc,
                function() return r.enabled ~= false end,
                function(v) r.enabled = v; ns.RefreshRuntime() end,
                function() EditCustomReminder(uid) end,
                function()
                    local writeSet = ns.CustomRemindersTable(false, encounterID)
                    if writeSet then writeSet[uid] = nil end
                    ns.RefreshRuntime()
                    onChanged()
                end)
        end
    end
    y = y - 6

    local addCRBtn = ns.Button(content, "+ Add a Custom Reminder", 190, 26, function()
        EditCustomReminder(nil)
    end)
    addCRBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - 34

    return y
end


-- ShowCustomReminderEditor's twin: same modal size, same tab/mechanic-picker/Save
-- shape, restricted to BigWigs triggers only (no pull/aura, no DBM -- a raid reminder is
-- always tied to a real BigWigs broadcast) and carrying the two things that editor has
-- no concept of:
-- who this is for (Target) and which of the four displays shows it.
-- abilitySpellID, passed only from ShowAbilityReminderPicker's Custom Reminder tab,
-- tags a brand-new entry as bound to that ability (so it shows on the ability's own
-- cog instead of ShowBossReminderPicker's boss-wide list) and seeds the mechanic
-- picker's Spell ID field with it -- still just a starting guess, not locked, since
-- the real BigWigs key for an ability can differ from its journal spellID.
-- seed (optional): { trigger = {...}, name = "..." } -- a starting point for a brand-new
-- reminder, used by the observed-timings rows so a recorded moment opens the editor
-- already pointed at it. Ignored when editing an existing entry.
function ns.ShowRaidReminderEditor(encounterID, uid, callerEUI, isRaid, abilitySpellID, seed)
    local EUI = callerEUI or ns.UI
    local W = EUI.Widgets
    local kind = isRaid and "Raid" or "Dungeon"

    -- Taller than ShowCustomReminderEditor's 620: the Target tab now carries full
    -- role/class/subgroup checkbox grids plus spec/name text fields instead of one
    -- kind dropdown, and none of these tab bodies scroll.
    local dimmer, panel = ns.MakeModal(480, 860, "raidReminderEditor")

    local head = ns.Font(panel, 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText((uid and "Edit " or "New ")
        .. (abilitySpellID and "Custom Reminder" or (kind .. " Reminder")))

    local set = ns.RaidRemindersTable and ns.RaidRemindersTable(false, encounterID)
    local existing = (set and uid) and set[uid] or nil
    local boundAbilitySpellID = (existing and existing.abilitySpellID) or abilitySpellID
    local trig = (existing and existing.trigger) or (seed and seed.trigger) or { type = "bwtimer" }
    local target = (existing and existing.target) or { all = true }
    local display = (existing and existing.display) or { type = "text" }

    local PAD = 20

    -- Wrapped, matching ShowAbilityReminderPicker's own RebuildBody: a blank panel with
    -- no error anywhere on screen is a failure mode this codebase has already shipped
    -- once, so anything that throws here shows up as text on the panel instead of an
    -- empty modal nobody can diagnose from a screenshot alone.
    local ok, err = pcall(function()

    local function HoverTip(hit, tooltip)
        hit:SetScript("OnEnter", function(self)
            local EUIg = ns.UI
            if EUIg and EUIg.ShowWidgetTooltip then EUIg.ShowWidgetTooltip(self, tooltip) end
        end)
        hit:SetScript("OnLeave", function()
            local EUIg = ns.UI
            if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
        end)
    end

    -------------------------------------------------------------------------
    --  Tabs -- same split ShowCustomReminderEditor uses: what fires this,
    --  and for whom (Trigger & Target), versus how it looks (Display).
    -------------------------------------------------------------------------
    local TAB_TOP = -40
    local BODY_TOP = TAB_TOP - 30

    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP)
    -- A single-corner anchor with no width ever set left tabBar's own geometry (and
    -- everything anchored off its LEFT/RIGHT points transitively -- every tab button)
    -- unresolvable: GetLeft/GetTop came back nil for the tab buttons even fully shown
    -- with alpha 1, confirmed live via debug prints. A second anchor point gives it a
    -- real width, same as every other full-width strip in this file already does.
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, TAB_TOP)
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
        for tid, body in pairs(tabBodies) do body:SetShown(tid == id) end
    end

    local function AddTab(id, text, anchorTo)
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(24)
        local lbl = ns.Font(btn, 12, nil, ns.THEME.muted)
        lbl:SetText(text)
        btn:SetSize(lbl:GetStringWidth() + 4, 24)
        lbl:SetPoint("CENTER")
        if anchorTo then btn:SetPoint("LEFT", anchorTo, "RIGHT", 18, 0)
        else btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0) end
        local marker = ns.Solid(btn, "OVERLAY", ns.THEME.accent, 1)
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

    local triggerTabBtn, triggerBody = AddTab("trigger", "Trigger & Target")
    local _, displayBody = AddTab("display", "Display", triggerTabBtn)

    -------------------------------------------------------------------------
    --  Trigger & Target tab
    -------------------------------------------------------------------------
    local ty = 0
    local function TLabel(text, tooltip)
        local l = ns.Font(triggerBody, 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, ty)
        l:SetText(text)
        if tooltip then
            local hit = CreateFrame("Frame", nil, triggerBody)
            hit:SetPoint("TOPLEFT", l, "TOPLEFT", -4, 4)
            hit:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 4, -4)
            HoverTip(hit, tooltip)
        end
        ty = ty - 16
    end
    local function TBox(maxLetters, numeric, rightInset)
        local box = CreateFrame("EditBox", nil, triggerBody)
        box:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, ty)
        box:SetPoint("RIGHT", triggerBody, "RIGHT", -(rightInset or PAD), 0)
        box:SetHeight(26)
        box:SetAutoFocus(false)
        box:SetMaxLetters(maxLetters or 60)
        if numeric then box:SetNumeric(true) end
        box:SetFontObject("GameFontHighlight")
        box:SetTextInsets(6, 6, 0, 0)
        ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
        ns.Border(box)
        ty = ty - 32
        return box
    end

    TLabel("Name")
    local nameBox = TBox(40)
    if existing then
        nameBox:SetText(existing.name or "")
    elseif seed and seed.name then
        nameBox:SetText(seed.name)
    elseif abilitySpellID then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(abilitySpellID)
        nameBox:SetText((info and info.name) or "")
    end

    -- The mechanic picker: every BigWigs/DBM key actually seen for this boss (recorded
    -- by RecordBossModKey the moment it fires live), sorted by how often it has come
    -- up -- same data source and shape ShowCustomReminderEditor's own picker uses,
    -- since it is the one place both editors need "which real ability is this."
    local MECHANIC_ROWS = 6
    local pickerRows = {}
    for i = 1, MECHANIC_ROWS do
        local row = CreateFrame("Button", nil, triggerBody)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, 0)
        row:SetPoint("RIGHT", triggerBody, "RIGHT", -PAD, 0)
        row.hl = ns.Solid(row, "BACKGROUND", ns.THEME.accent, 0.14)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row:SetScript("OnEnter", function(s) s.hl:Show() end)
        row:SetScript("OnLeave", function(s) s.hl:Hide() end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = ns.Font(row, 11, nil, ns.THEME.fg)
        row.name:SetPoint("LEFT", 22, 0)
        row.name:SetPoint("RIGHT", -34, 0)
        row.name:SetJustifyH("LEFT")
        row.tag = ns.Font(row, 9, nil, ns.THEME.muted)
        row.tag:SetPoint("RIGHT", -2, 0)
        pickerRows[i] = row
    end
    local pickerHint = ns.Font(triggerBody, 10, nil, ns.THEME.muted)
    pickerHint:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, ty)
    pickerHint:SetPoint("RIGHT", triggerBody, "RIGHT", -PAD, 0)
    pickerHint:SetJustifyH("LEFT")
    local PICKER_ROW_H = 22
    local PICKER_TOP = ty

    local trigTypeVal = (trig.type == "bwmsg" and "bwmsg")
        or (trig.type == "pull" and "pull") or (trig.type == "aura" and "aura")
        or (trig.type == "stage" and "stage") or "bwtimer"
    local spellIDText = (trig.spellID and tostring(trig.spellID))
        or (abilitySpellID and tostring(abilitySpellID)) or ""
    local leadTimeText = (trig.leadTime and tostring(trig.leadTime)) or "3"
    local pullDelayText = (trig.delay and tostring(trig.delay)) or "5"
    local stageNumText = (trig.stage and tostring(trig.stage)) or "2"
    -- The early-fire lead for pull/stage (bwtimer has its own leadTimeText with different
    -- semantics); blank means fire exactly at the noted time.
    local earlyLeadText = ((trig.type == "pull" or trig.type == "stage") and trig.leadTime
        and tostring(trig.leadTime)) or ""
    local auraEventVal = (trig.auraEvent == "removed") and "removed" or "applied"
    local auraTargetVal = (trig.target == "boss") and "boss" or "player"

    -- Declared here, assigned below: a picker row's OnClick (built by RebuildPicker,
    -- called from inside RebuildTriggerFields itself) has to reach the rebuild function
    -- that is still being defined at the point this local exists -- same forward-
    -- reference shape ShowCustomReminderEditor's own RebuildDynFields/dynFrame pair uses.
    local RebuildTriggerFields

    local function RebuildPicker()
        for i = 1, MECHANIC_ROWS do pickerRows[i]:Hide() end
        pickerHint:SetText("")
        local cat = ns.BossModCatalogueTable and ns.BossModCatalogueTable(false, encounterID)
        local list = {}
        if cat then
            -- BigWigs only: a raid reminder's trigger is always "BigWigs Message/Timer"
            -- now (see the Trigger Type dropdown above), so a DBM-only catalogue entry
            -- would just be a dead pick here -- the catalogue itself stays shared with
            -- ShowCustomReminderEditor, which still wants both.
            for key, entry in pairs(cat) do
                if entry.mod ~= "DBM" then list[#list + 1] = { key = key, entry = entry } end
            end
        end
        table.sort(list, function(a, b) return (a.entry.seen or 0) > (b.entry.seen or 0) end)

        if #list == 0 then
            pickerHint:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, PICKER_TOP)
            pickerHint:SetText("|cff9a9ea6Nothing recorded for this boss yet -- pull it with "
                .. "BigWigs running, or type a Spell ID below.|r")
            pickerHint:SetHeight(28)
            return 28
        end

        local shown = math.min(#list, MECHANIC_ROWS)
        for i = 1, shown do
            local row, item = pickerRows[i], list[i]
            row:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, PICKER_TOP - (i - 1) * PICKER_ROW_H)
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(item.key)
            row.icon:SetTexture((info and info.iconID) or 134400)
            row.name:SetText((info and info.name) or (item.entry.text or ("Spell " .. item.key)))
            row.tag:SetText("|cfff0a830BW|r")
            row:SetScript("OnClick", function()
                trigTypeVal = (item.entry.kind == "timer") and "bwtimer" or "bwmsg"
                spellIDText = tostring(item.key)
                RebuildTriggerFields()
            end)
            row:Show()
        end
        pickerHint:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, PICKER_TOP - shown * PICKER_ROW_H)
        if #list > shown then
            pickerHint:SetText(("|cff9a9ea6+%d more not shown -- type the Spell ID below.|r")
                :format(#list - shown))
            pickerHint:SetHeight(16)
            return shown * PICKER_ROW_H + 20
        end
        pickerHint:SetHeight(4)
        return shown * PICKER_ROW_H + 4
    end

    local dynFrame, spellBox, leadTimeBox, pullDelayBox
    local triggerTypeRow

    -- Target: who sees this -- AND across categories (role/class/spec/name/subgroup),
    -- OR within one, matching ns.RaidReminderTargetsMe exactly (see its own comment).
    -- Declared here, built below: RebuildTriggerFields' own tail calls
    -- RebuildTargetSection so toggling Message/Timer (which changes how tall the
    -- fields above it are) re-anchors the whole Target section instead of leaving it
    -- frozen at its original position.
    local nTarget = ns.NormalizeRaidReminderTarget(target)
    local targetAllVal = nTarget.all
    local targetRoles, targetClasses, targetSubgroups = {}, {}, {}
    for k in pairs(nTarget.roles or {}) do targetRoles[k] = true end
    for k in pairs(nTarget.classes or {}) do targetClasses[k] = true end
    for k in pairs(nTarget.subgroups or {}) do targetSubgroups[k] = true end
    local targetSpecText, targetNameText
    do
        local list = {}
        for id in pairs(nTarget.specs or {}) do list[#list + 1] = tostring(id) end
        table.sort(list)
        targetSpecText = table.concat(list, ", ")
    end
    do
        local list = {}
        for name in pairs(nTarget.names or {}) do list[#list + 1] = name end
        table.sort(list)
        targetNameText = table.concat(list, ", ")
    end
    local targetSection
    local RebuildTargetSection

    RebuildTriggerFields = function()
        -- RebuildPicker returns a POSITIVE height consumed; SUBTRACT it from PICKER_TOP
        -- (already negative) to move further down the panel, same sign convention every
        -- other "ty = ty - rowHeight" line in this function already uses. Written as +
        -- originally, which flipped ty positive and threw everything after the picker
        -- back above it -- the overlap seen live.
        -- Skipped entirely for "pull"/"aura": neither is anchored to a BigWigs
        -- mechanic (pull is a flat delay, aura is a plain spell id + apply/remove),
        -- so there's nothing on the boss-mod catalogue to pick from either way.
        if trigTypeVal == "pull" or trigTypeVal == "aura" then
            for i = 1, MECHANIC_ROWS do pickerRows[i]:Hide() end
            pickerHint:SetText("")
            ty = PICKER_TOP
        else
            ty = PICKER_TOP - RebuildPicker()
        end
        -- Every call rebuilds this row from scratch (picking a mechanic off the
        -- picker, or switching Message/Timer itself, both call RebuildTriggerFields
        -- again) -- the previous one has to be hidden first or picking two different
        -- mechanics in a row stacks a second "Trigger Type" dropdown exactly on top
        -- of the first, both drawing their own label text into the same spot.
        if triggerTypeRow then triggerTypeRow:Hide() end

        local typeRowH
        triggerTypeRow, typeRowH = W:DualRow(triggerBody, ty,
            { type = "dropdown", text = "Trigger Type",
              values = { bwmsg = "BigWigs Message", bwtimer = "BigWigs Timer",
                  pull = "Time After Pull", aura = "Gain/Lose a Buff or Debuff",
                  stage = "Phase Start" },
              order = { "bwmsg", "bwtimer", "pull", "aura", "stage" },
              tooltip = "Message fires the instant BigWigs announces it. Timer waits "
                  .. "out the bar and fires this many seconds before it ends. Time "
                  .. "After Pull fires a fixed number of seconds into the encounter, "
                  .. "with no BigWigs mechanic involved. Gain/Lose a Buff or Debuff "
                  .. "fires off the combat log directly, reliable even when BigWigs "
                  .. "says nothing about it. Phase Start fires a fixed number of seconds "
                  .. "after the boss mod announces that phase -- it needs BigWigs or DBM, "
                  .. "and only fires on bosses whose module announces phases.",
              getValue = function() return trigTypeVal end,
              setValue = function(v) trigTypeVal = v; RebuildTriggerFields() end }
        )
        ty = ty - typeRowH

        if dynFrame then dynFrame:Hide() end
        dynFrame = CreateFrame("Frame", nil, triggerBody)
        dynFrame:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", 0, ty)
        dynFrame:SetSize(440, 120)
        local dy = 0
        local function DLabel(text)
            local l = ns.Font(dynFrame, 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", dynFrame, "TOPLEFT", PAD, dy)
            l:SetText(text)
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

        if trigTypeVal == "pull" then
            spellBox, leadTimeBox = nil, nil
            DLabel("Delay After Pull (seconds)")
            -- Not a numeric box: note-born entries carry fractional times (1:09.1).
            pullDelayBox = DBox(8)
            pullDelayBox:SetText(pullDelayText)
            pullDelayBox:SetScript("OnTextChanged", function()
                pullDelayText = pullDelayBox:GetText() or ""
            end)
            DLabel("Show This Many Seconds Early (blank = at that time)")
            local leadBox = DBox(4)
            leadBox:SetText(earlyLeadText)
            leadBox:SetScript("OnTextChanged", function()
                earlyLeadText = leadBox:GetText() or ""
            end)
        elseif trigTypeVal == "stage" then
            spellBox, leadTimeBox, pullDelayBox = nil, nil, nil
            DLabel("Phase Number")
            local stageBox = DBox(2, true)
            stageBox:SetText(stageNumText)
            stageBox:SetScript("OnTextChanged", function()
                stageNumText = stageBox:GetText() or ""
            end)
            DLabel("Seconds After the Phase Starts")
            local sdBox = DBox(8)
            sdBox:SetText(pullDelayText)
            sdBox:SetScript("OnTextChanged", function()
                pullDelayText = sdBox:GetText() or ""
            end)
            DLabel("Show This Many Seconds Early (blank = at that time)")
            local leadBox = DBox(4)
            leadBox:SetText(earlyLeadText)
            leadBox:SetScript("OnTextChanged", function()
                earlyLeadText = leadBox:GetText() or ""
            end)
        elseif trigTypeVal == "aura" then
            pullDelayBox, leadTimeBox = nil, nil
            DLabel("Spell ID")
            spellBox = DBox(9, true, 80)
            spellBox:SetText(spellIDText)
            local okBtn = ns.Button(dynFrame, "OK", 54, 26, function() spellBox:ClearFocus() end)
            okBtn:SetPoint("LEFT", spellBox, "RIGHT", 6, 0)
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
                else
                    feedback:SetText("|cffff6060not a spell id|r")
                end
            end
            spellBox:SetScript("OnTextChanged", function() spellIDText = spellBox:GetText() or ""; Sync() end)
            spellBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            Sync()

            local auraRowH
            _, auraRowH = W:DualRow(dynFrame, dy,
                { type = "dropdown", text = "Event",
                  values = { applied = "Gained", removed = "Lost" }, order = { "applied", "removed" },
                  getValue = function() return auraEventVal end,
                  setValue = function(v) auraEventVal = v end },
                { type = "dropdown", text = "On",
                  values = { player = "You", boss = "The Boss" }, order = { "player", "boss" },
                  tooltip = "Watch YOUR OWN aura (a defensive/buff you gain or lose) or "
                      .. "one applied TO the boss (a debuff you or the raid puts on it).",
                  getValue = function() return auraTargetVal end,
                  setValue = function(v) auraTargetVal = v end }
            )
            dy = dy - auraRowH
        else
            pullDelayBox = nil
            DLabel("Spell ID")
            spellBox = DBox(9, true, 80)
            spellBox:SetText(spellIDText)
            local okBtn = ns.Button(dynFrame, "OK", 54, 26, function() spellBox:ClearFocus() end)
            okBtn:SetPoint("LEFT", spellBox, "RIGHT", 6, 0)
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
                else
                    feedback:SetText("|cff9a9ea6no spell name found -- boss-mod keys aren't "
                        .. "always real spell ids, that's fine|r")
                end
            end
            spellBox:SetScript("OnTextChanged", function() spellIDText = spellBox:GetText() or ""; Sync() end)
            spellBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            Sync()

            if trigTypeVal == "bwtimer" then
                DLabel("Warning Time (seconds before it lands)")
                leadTimeBox = DBox(4, true)
                leadTimeBox:SetText(leadTimeText)
                leadTimeBox:SetScript("OnTextChanged", function() leadTimeText = leadTimeBox:GetText() or "" end)
            else
                leadTimeBox = nil
            end
        end

        -- dynFrame's own dy cursor is local to this closure and never reaches the outer
        -- ty on its own -- without this, the Target section built right after this call
        -- returns would render on top of whatever dynFrame just placed here, since ty
        -- would still be sitting at the Trigger Type row's own bottom edge.
        ty = ty + dy
        RebuildTargetSection()
    end

    RebuildTargetSection = function()
        if targetSection then targetSection:Hide() end
        targetSection = CreateFrame("Frame", nil, triggerBody)
        targetSection:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", 0, ty - 10)
        targetSection:SetPoint("RIGHT", triggerBody, "RIGHT", 0, 0)

        local tgy = 0
        local function TargetLabel(text)
            local l = ns.Font(targetSection, 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", targetSection, "TOPLEFT", PAD, tgy)
            l:SetText(text)
            tgy = tgy - 16
        end
        TargetLabel("Target")

        local allCheck = CreateFrame("CheckButton", nil, targetSection, "UICheckButtonTemplate")
        allCheck:SetSize(20, 20)
        allCheck:SetPoint("TOPLEFT", targetSection, "TOPLEFT", PAD, tgy)
        allCheck:SetChecked(targetAllVal)
        local allLbl = ns.Font(targetSection, 11, nil, ns.THEME.fg)
        allLbl:SetPoint("LEFT", allCheck, "RIGHT", 4, 0)
        allLbl:SetText("Everyone")
        tgy = tgy - 28

        -- Greyed out (not just ignored) while Everyone is checked -- an irrelevant
        -- control should read as irrelevant, same reasoning the boss cast-bar's own
        -- AddCastBlock gating uses elsewhere in this addon suite.
        local restFrame = CreateFrame("Frame", nil, targetSection)
        restFrame:SetPoint("TOPLEFT", targetSection, "TOPLEFT", 0, tgy)
        restFrame:SetPoint("RIGHT", targetSection, "RIGHT", 0, 0)

        local ry = 0
        local function RestLabel(text)
            local l = ns.Font(restFrame, 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", restFrame, "TOPLEFT", PAD, ry)
            l:SetText(text)
            ry = ry - 16
        end
        -- A fixed grid of small checkboxes -- shared shape for role/class/subgroup,
        -- the three fixed-size enumerations. AND-across/OR-within (see
        -- ns.RaidReminderTargetsMe) means checking two roles widens ("Tank OR
        -- Healer"), while a role AND a class both checked narrows to their overlap.
        local function CheckGrid(items, set, perRow, itemW, colorFn)
            for i = 1, #items do
                local key, label = items[i][1], items[i][2]
                local col = (i - 1) % perRow
                local row = math.floor((i - 1) / perRow)
                local check = CreateFrame("CheckButton", nil, restFrame, "UICheckButtonTemplate")
                check:SetSize(18, 18)
                check:SetPoint("TOPLEFT", restFrame, "TOPLEFT", PAD + col * itemW, ry - row * 22)
                check:SetChecked(set[key])
                check:SetScript("OnClick", function(self)
                    if self:GetChecked() then set[key] = true else set[key] = nil end
                end)
                local lbl = ns.Font(restFrame, 10, nil, ns.THEME.fg)
                lbl:SetPoint("LEFT", check, "RIGHT", 2, 0)
                lbl:SetWordWrap(false)
                lbl:SetText(label)
                if colorFn then
                    local r, g, b = colorFn(key)
                    if r then lbl:SetTextColor(r, g, b, 1) end
                end
            end
            ry = ry - math.ceil(#items / perRow) * 22 - 8
        end

        RestLabel("Role")
        do
            local items = {}
            for i = 1, #RR_ROLE_ORDER do items[i] = { RR_ROLE_ORDER[i], RR_ROLE_VALUES[RR_ROLE_ORDER[i]] } end
            CheckGrid(items, targetRoles, 3, 140)
        end

        RestLabel("Class")
        do
            local classNames = _G.LOCALIZED_CLASS_NAMES_MALE or {}
            local classOrder = {}
            for token in pairs(classNames) do classOrder[#classOrder + 1] = token end
            table.sort(classOrder)
            local items = {}
            for i = 1, #classOrder do items[i] = { classOrder[i], classNames[classOrder[i]] } end
            local classColors = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS
            CheckGrid(items, targetClasses, 3, 140, function(token)
                local c = classColors and classColors[token]
                if c then return c.r, c.g, c.b end
            end)
        end

        RestLabel("Subgroup")
        do
            local items = {}
            for i = 1, 8 do items[i] = { i, tostring(i) } end
            CheckGrid(items, targetSubgroups, 8, 52)
        end

        local function RestBox(labelText, existingText, onChange)
            RestLabel(labelText)
            local box = CreateFrame("EditBox", nil, restFrame)
            box:SetPoint("TOPLEFT", restFrame, "TOPLEFT", PAD, ry)
            box:SetPoint("RIGHT", restFrame, "RIGHT", -PAD, 0)
            box:SetHeight(26)
            box:SetAutoFocus(false)
            box:SetMaxLetters(200)
            box:SetFontObject("GameFontHighlight")
            box:SetTextInsets(6, 6, 0, 0)
            ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
            ns.Border(box)
            box:SetText(existingText)
            box:SetScript("OnTextChanged", function() onChange(box:GetText() or "") end)
            ry = ry - 32
        end
        RestBox("Spec IDs (comma-separated, optional)", targetSpecText,
            function(v) targetSpecText = v end)
        RestBox("Player Names (comma-separated, exact, optional)", targetNameText,
            function(v) targetNameText = v end)

        restFrame:SetHeight(-ry)
        restFrame:SetShown(not targetAllVal)
        allCheck:SetScript("OnClick", function(self)
            targetAllVal = self:GetChecked() and true or false
            restFrame:SetShown(not targetAllVal)
        end)

        targetSection:SetHeight(-tgy + (targetAllVal and 0 or -ry))
    end
    RebuildTriggerFields()

    -------------------------------------------------------------------------
    --  Display tab
    -------------------------------------------------------------------------
    local dsy = 0
    local function DsLabel(text)
        local l = ns.Font(displayBody, 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", displayBody, "TOPLEFT", PAD, dsy)
        l:SetText(text)
        dsy = dsy - 16
    end
    local function DsBox(maxLetters, numeric, rightInset)
        local box = CreateFrame("EditBox", nil, displayBody)
        box:SetPoint("TOPLEFT", displayBody, "TOPLEFT", PAD, dsy)
        box:SetPoint("RIGHT", displayBody, "RIGHT", -(rightInset or PAD), 0)
        box:SetHeight(26)
        box:SetAutoFocus(false)
        box:SetMaxLetters(maxLetters or 60)
        if numeric then box:SetNumeric(true) end
        box:SetFontObject("GameFontHighlight")
        box:SetTextInsets(6, 6, 0, 0)
        ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
        ns.Border(box)
        dsy = dsy - 32
        return box
    end

    local displayTypeVal = display.type or "text"
    local _, dispRowH = W:DualRow(displayBody, dsy,
        { type = "dropdown", text = "Display As",
          values = RR_DISPLAY_VALUES, order = RR_DISPLAY_ORDER,
          tooltip = "Message/Timer/Icon/Bar/Circle each have their own fixed on-screen "
              .. "spot. Chat Line prints instead of showing anything. Nameplate/"
              .. "Raid-Frame Glow highlight another raider's own frame -- set who "
              .. "below.",
          getValue = function() return displayTypeVal end,
          setValue = function(v) displayTypeVal = v end }
    ); dsy = dsy - dispRowH

    DsLabel("Glow Player Name (Nameplate/Raid-Frame Glow only)")
    local glowTargetBox = DsBox(24)
    glowTargetBox:SetText(display.glowTarget or "")

    DsLabel("Text -- %name (your name), %specicon, %time (linger seconds), {spell:ID}")
    local textBox = DsBox(120)
    textBox:SetText(display.text or "")

    DsLabel("Icon Spell ID (used for Icon display; optional otherwise)")
    local iconBox = DsBox(9, true, PAD + 34)
    local iconPreview = displayBody:CreateTexture(nil, "ARTWORK")
    iconPreview:SetSize(24, 24)
    iconPreview:SetPoint("LEFT", iconBox, "RIGHT", 6, 0)
    iconPreview:Hide()
    local iconFeedback = ns.Font(displayBody, 10, nil, ns.THEME.muted)
    iconFeedback:SetPoint("TOPLEFT", displayBody, "TOPLEFT", PAD, dsy)
    iconFeedback:SetPoint("RIGHT", displayBody, "RIGHT", -PAD, 0)
    iconFeedback:SetJustifyH("LEFT")
    dsy = dsy - 14
    local function SyncIcon()
        local sid, info = ns.ResolveSpell(iconBox:GetText())
        if sid then
            local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
            if tex then iconPreview:SetTexture(tex); iconPreview:Show() else iconPreview:Hide() end
            iconFeedback:SetText("|cff6DD09A" .. ((info and info.name) or "") .. "|r")
        elseif iconBox:GetText() == "" then
            iconPreview:Hide(); iconFeedback:SetText("")
        else
            iconPreview:Hide(); iconFeedback:SetText("|cffff6060not a spell id|r")
        end
    end
    iconBox:SetScript("OnTextChanged", SyncIcon)
    iconBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    iconBox:SetText((display.spellID and tostring(display.spellID)) or "")
    SyncIcon()

    local existingColor = display.color
    local pendingColor = { r = (existingColor and existingColor.r) or 1,
        g = (existingColor and existingColor.g) or 1, b = (existingColor and existingColor.b) or 1,
        a = (existingColor and existingColor.a) or 1 }
    local _, colorRowH = W:DualRow(displayBody, dsy,
        { type = "colorpicker", text = "Text Color", hasAlpha = false,
          tooltip = "This reminder's text color.",
          getValue = function() return pendingColor.r, pendingColor.g, pendingColor.b, pendingColor.a end,
          setValue = function(r, g, b, a) pendingColor = { r = r, g = g, b = b, a = a } end }
    ); dsy = dsy - colorRowH

    local pendingSoundKey = display.sound or "none"
    local soundPaths, soundNames, soundOrder = EUI.BuildAlertSoundTables()
    if EUI.AppendSharedMediaSounds then EUI.AppendSharedMediaSounds(soundPaths, soundNames, soundOrder) end
    local _, soundRowH = W:DualRow(displayBody, dsy,
        { type = "dropdown", text = "Sound", values = soundNames, order = soundOrder,
          tooltip = "Plays once when this reminder fires.",
          getValue = function() return pendingSoundKey end,
          setValue = function(v)
              pendingSoundKey = v
              if EUI._PlayLSMSound and soundPaths[v] then EUI._PlayLSMSound(soundPaths[v]) end
          end }
    ); dsy = dsy - soundRowH

    local ttsVal = display.tts == true
    local _, ttsRowH = W:DualRow(displayBody, dsy,
        { type = "toggle", text = "Speak (Text-to-Speech)",
          tooltip = "Reads the Text field aloud through your own client's built-in "
              .. "text-to-speech, using whatever voice/rate you set in the "
              .. "Accessibility panel.",
          getValue = function() return ttsVal end,
          setValue = function(v) ttsVal = v end }
    ); dsy = dsy - ttsRowH

    DsLabel("Linger (seconds)")
    local durBox = DsBox(3, true)
    durBox:SetText(tostring(display.dur or 4))

    -- MRT's event-13 "hide after use" gate -- once YOU successfully cast this spell,
    -- whatever's currently on screen for this reminder disappears immediately instead
    -- of waiting out its own Linger. Optional: blank means it only ever hides on its
    -- own timer, same as before this existed.
    DsLabel("Hide Once I Cast (Spell ID, optional)")
    local hideCastBox = DsBox(9, true, PAD + 34)
    local hideCastFeedback = ns.Font(displayBody, 10, nil, ns.THEME.muted)
    hideCastFeedback:SetPoint("TOPLEFT", displayBody, "TOPLEFT", PAD, dsy)
    hideCastFeedback:SetPoint("RIGHT", displayBody, "RIGHT", -PAD, 0)
    hideCastFeedback:SetJustifyH("LEFT")
    dsy = dsy - 14
    local function SyncHideCast()
        local sid, info = ns.ResolveSpell(hideCastBox:GetText())
        if sid then
            hideCastFeedback:SetText("|cff6DD09A" .. ((info and info.name) or "") .. "|r")
        elseif hideCastBox:GetText() == "" then
            hideCastFeedback:SetText("")
        else
            hideCastFeedback:SetText("|cffff6060not a spell id|r")
        end
    end
    hideCastBox:SetScript("OnTextChanged", SyncHideCast)
    hideCastBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    hideCastBox:SetText((display.hideAfterCastID and tostring(display.hideAfterCastID)) or "")
    SyncHideCast()

    local enabledVal = (existing == nil) or existing.enabled ~= false
    W:DualRow(displayBody, dsy,
        { type = "toggle", text = "Enabled",
          getValue = function() return enabledVal end,
          setValue = function(v) enabledVal = v end }
    )

    SelectTab("trigger")

    -------------------------------------------------------------------------
    --  Save / Preview
    -------------------------------------------------------------------------
    local function BuildEntry()
        local newTrig
        if trigTypeVal == "pull" then
            local delay = tonumber(pullDelayText)
            if not delay or delay < 0 then return nil, "need a valid delay in seconds" end
            newTrig = { type = "pull", delay = delay, leadTime = tonumber(earlyLeadText) }
        elseif trigTypeVal == "stage" then
            local stageN = tonumber(stageNumText)
            local delay = tonumber(pullDelayText)
            if not stageN or stageN < 1 then return nil, "need a phase number of 1 or more" end
            if not delay or delay < 0 then return nil, "need a valid delay in seconds" end
            newTrig = { type = "stage", stage = stageN, delay = delay,
                leadTime = tonumber(earlyLeadText) }
        else
            local sid = tonumber(spellIDText)
            if not sid then return nil, "need a valid Spell ID" end
            newTrig = { type = trigTypeVal, spellID = sid }
            if trigTypeVal == "bwtimer" then
                newTrig.leadTime = tonumber(leadTimeText) or 3
            elseif trigTypeVal == "aura" then
                newTrig.auraEvent = auraEventVal
                newTrig.target = auraTargetVal
            end
        end
        local newTarget = { all = targetAllVal }
        if not targetAllVal then
            if next(targetRoles) then newTarget.roles = targetRoles end
            if next(targetClasses) then newTarget.classes = targetClasses end
            if next(targetSubgroups) then newTarget.subgroups = targetSubgroups end
            local specs = {}
            for numStr in targetSpecText:gmatch("[^,%s]+") do
                local id = tonumber(numStr)
                if id then specs[id] = true end
            end
            if next(specs) then newTarget.specs = specs end
            local names = {}
            for namePart in targetNameText:gmatch("[^,]+") do
                namePart = namePart:match("^%s*(.-)%s*$")
                if namePart ~= "" then names[namePart] = true end
            end
            if next(names) then newTarget.names = names end
        end
        local iconSid = tonumber(iconBox:GetText())
        local hideCastSid = tonumber(hideCastBox:GetText())
        local newDisplay = {
            type = displayTypeVal,
            text = textBox:GetText(),
            spellID = (iconSid and iconSid > 0) and iconSid or nil,
            color = pendingColor,
            dur = math.max(1, tonumber(durBox:GetText()) or 4),
            sound = (pendingSoundKey ~= "none") and pendingSoundKey or nil,
            hideAfterCastID = (hideCastSid and hideCastSid > 0) and hideCastSid or nil,
            tts = ttsVal or nil,
            glowTarget = (glowTargetBox:GetText() ~= "" and glowTargetBox:GetText()) or nil,
        }
        return {
            name = (nameBox:GetText() ~= "" and nameBox:GetText()) or "Reminder",
            enabled = enabledVal, trigger = newTrig, target = newTarget, display = newDisplay,
            abilitySpellID = boundAbilitySpellID,
        }
    end

    local function Save()
        local entry, err = BuildEntry()
        if not entry then
            ns.Print("|cffff6060" .. (err or "could not save this reminder") .. "|r")
            return
        end
        local writeSet = ns.RaidRemindersTable(true, encounterID)
        local key = uid or ("rr" .. math.floor(GetTime() * 1000) .. math.random(1, 9999))
        writeSet[key] = entry
        -- Takes effect now, and refreshes the cached has-reminders flags the combat log
        -- hot path reads.
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end

    ns.Button(panel, "Preview", 90, 26, function()
        -- Bypasses ns.RaidReminderTargetsMe entirely, same as ShowCustomReminderEditor's
        -- own Preview button bypasses trigger matching -- a curator previewing sees it
        -- regardless of whether they personally match the target they just chose.
        local entry, buildErr = BuildEntry()
        if entry then
            if ns.PreviewRaidReminder then ns.PreviewRaidReminder(entry) end
        else
            ns.Print("|cffff6060" .. (buildErr or "could not preview this reminder") .. "|r")
        end
    end):SetPoint("BOTTOM", panel, "BOTTOM", -110, 16)
    ns.Button(panel, "Save", 90, 26, Save):SetPoint("BOTTOM", panel, "BOTTOM", -10, 16)
    ns.Button(panel, "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 90, 16)

    end)
    if not ok then
        -- Fixed offset, not TAB_TOP -- that local only exists inside the pcall'd
        -- closure above, out of scope here precisely because it failed to run.
        local errText = ns.Font(panel, 11, nil, { r = 1, g = 0.35, b = 0.35 })
        errText:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -70)
        errText:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
        errText:SetJustifyH("LEFT")
        errText:SetWordWrap(true)
        errText:SetText("Failed to build this panel: " .. tostring(err))
        ns.Print("|cffff6060raid reminder editor|r: " .. tostring(err))
    end

    dimmer:Show()
    -- Returned so a caller (ns.ShowBossReminderPicker) can hook OnHide and refresh its
    -- own list once this editor closes -- ignored by every other existing call site.
    return dimmer, panel
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
