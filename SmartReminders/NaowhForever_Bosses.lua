-------------------------------------------------------------------------------
--  NaowhForever_Bosses.lua -- browse this season's bosses and every ability the
--  journal lists for them, labelled by who each one is aimed at.
--
--  Everything is read from the player's own client at runtime. The tank marking comes
--  from the Encounter Journal, not C_EncounterEvents: that namespace has no boss
--  association at all, and joining it on spellID drops most tank busters (the journal
--  lists the applied aura, the event the triggering cast).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
if not ns then return end

-- GetSectionIconFlags returns INDICES into the flag list, not the enum values, so Tank (the
-- lowest bit, value 1) is index 0. Blizzard hardcodes the same 0 in its own role table.
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

local ROLE_COLOR = { Tank = "|cffF0A830", Dps = "|cffFF6060", Healer = "|cff6DD09A" }

-------------------------------------------------------------------------------
--  Journal availability
-------------------------------------------------------------------------------
-- Blizzard_EncounterJournal is load-on-demand, so the EJ_ globals do not exist until
-- something has opened it.
-- Second return is true when this call triggered the load: a scrape right after it can
-- miss data (raid descriptions came back empty live), so ScrapeBosses re-scrapes once.
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
-- reads back with no arguments and will not resync, so scraping under an open journal
-- corrupts what the player is looking at.
local function JournalBusy()
    return EncounterJournal ~= nil and EncounterJournal:IsShown()
end

-------------------------------------------------------------------------------
--  The scrape
-------------------------------------------------------------------------------
-- Built on first view and kept for the session; nothing is scraped at login.
local cache          -- { instances = { {id, name, isRaid, bosses = { {name, abilities} } } } }
local scrapeFailed
local rescrapeQueued
-- Stage-by-stage record of the last scrape, read by /nutank bosses.
local diag = {}

local function WalkSections(rootID, out, depth, seen)
    -- Depth-capped so a malformed section cycle cannot hang the client.
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

        -- Role headers like "Tanks" carry the tank flag too, but have no spell.
        local isAbility = info.spellID and info.spellID > 0
        -- Casts only; passives are never announced, so nothing can warn about them.
        if isAbility and C_Spell and C_Spell.IsSpellPassive then
            local okP, passive = pcall(C_Spell.IsSpellPassive, info.spellID)
            if okP and passive == true then isAbility = false end
        end
        if isAbility and info.title and info.title ~= "" then
            -- The journal repeats an ability under overview, role and stage sections; one
            -- row per spell, later occurrences only adding labels the first lacked.
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

-- mapID is the instance map id (GetInstanceInfo's 8th return, the TOCs'
-- X-BigWigs-LoadOn-InstanceId), so a boss page can load just this instance's pack.
local function ScrapeInstance(instanceID, name, isRaid, mapID)
    local entry = { id = instanceID, name = name, isRaid = isRaid, mapID = mapID, bosses = {} }

    EJ_SelectInstance(instanceID)
    for i = 1, 40 do
        local bossName, _, bossID = EJ_GetEncounterInfoByIndex(i)
        if not bossName then break end
        if bossID then
            -- Return 7 is dungeonEncounterID, the id ENCOUNTER_START reports.
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

    -- Restored afterwards; the journal UI keeps its own copy and would not notice ours.
    local priorTier = EJ_GetCurrentTier and EJ_GetCurrentTier()

    local out = { instances = {} }
    wipe(diag)
    diag.tier = priorTier

    -- Mythic+ pool: the live season list Blizzard's keystone UI uses.
    if C_ChallengeMode and C_ChallengeMode.GetMapTable and C_EncounterJournal.GetInstanceForGameMap then
        local maps = C_ChallengeMode.GetMapTable()
        diag.mapCount = maps and #maps or 0
        diag.mapped = 0
        for i = 1, (maps and #maps or 0) do
            local mapName, _, _, _, _, gameMapID = C_ChallengeMode.GetMapUIInfo(maps[i])
            local journalID = gameMapID and C_EncounterJournal.GetInstanceForGameMap(gameMapID)
            if journalID then
                diag.mapped = diag.mapped + 1
                out.instances[#out.instances + 1] = ScrapeInstance(journalID, mapName or "?", false, gameMapID)
            end
        end
    else
        diag.mapCount = -1   -- the API itself was unavailable
    end

    -- No "latest raid" API; the current tier's raid list is the journal's own heuristic.
    diag.raids = 0
    -- Forever's journal has no tiers and reports 0, which EJ_SelectTier rejects.
    if EJ_SelectTier and EJ_GetInstanceByIndex and priorTier and priorTier > 0 then
        EJ_SelectTier(priorTier)
        for i = 1, 20 do
            local instanceID, rname = EJ_GetInstanceByIndex(i, true)
            if not instanceID then break end
            diag.raids = diag.raids + 1
            -- The instance map id is EJ_GetInstanceInfo's 10th return.
            local _, _, _, _, _, _, _, _, _, raidMapID = EJ_GetInstanceInfo(instanceID)
            out.instances[#out.instances + 1] = ScrapeInstance(instanceID, rname or "?", true, raidMapID)
        end
    end

    diag.instances = #out.instances
    diag.bosses = 0
    for i = 1, #out.instances do diag.bosses = diag.bosses + #out.instances[i].bosses end

    if priorTier and priorTier > 0 and EJ_SelectTier then EJ_SelectTier(priorTier) end

    cache = out

    -- freshLoad is only true on the session's first scrape, so this queues at most once.
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
-- The engine only receives what BigWigs broadcasts, so a boss with a module lists its
-- toggleOptions instead of the journal; bosses with no module keep the journal listing.
local bwOptionCache = {}   -- [dungeonEncounterID] = { {id, stage}, ... }, or false
local bwPacksLoaded, bwPacksLoading, bwPackNames

-- Content packs are LoadOnDemand outside their own zone. LittleWigs' older expansion
-- packs are included because the dungeon rotation reaches back into them.
local function BossModPackNames()
    if bwPackNames then return bwPackNames end
    bwPackNames = {}
    if not (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetAddOnInfo) then
        return bwPackNames
    end
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string"
            and (name:find("^BigWigs_") or name:find("^LittleWigs"))
            and name ~= "BigWigs_Plugins" and name ~= "BigWigs_Options" then
            bwPackNames[#bwPackNames + 1] = name
        end
    end
    return bwPackNames
end

-- A pack's !Options.lua indexes the BigWigs global while loading, so a pack loaded
-- before the core throws inside BigWigs' loader, out of reach of our pcall. The core
-- is load-on-demand too, so it is loaded first.
local function BossModCoreUp()
    if _G.BigWigs then return true end
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "BigWigs_Core") end
    return _G.BigWigs ~= nil
end

local function LoadBossModPacks()
    if bwPacksLoaded or bwPacksLoading then return end
    -- Not latched: the core comes up by itself on zoning into an instance.
    if not BossModCoreUp() then return end
    if not (C_AddOns and C_AddOns.LoadAddOn and C_Timer and C_Timer.NewTicker) then
        bwPacksLoaded = true
        return
    end
    local names = BossModPackNames()
    if #names == 0 then bwPacksLoaded = true return end
    bwPacksLoading = true
    local i = 0
    C_Timer.NewTicker(0, function(ticker)
        i = i + 1
        if i > #names then
            ticker:Cancel()
            bwPacksLoading, bwPacksLoaded = false, true
            local EUI = ns.UI
            if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
            return
        end
        C_AddOns.LoadAddOn(names[i])
    end)
end
ns.LoadBossModPacks = LoadBossModPacks


local function BigWigsOptionList(encounterID, mapID)
    -- Some journal rows have no dungeonEncounterID, and a nil key write below would throw.
    if encounterID == nil then return nil end
    local cached = bwOptionCache[encounterID]
    if cached ~= nil then return cached or nil end
    -- Loads only this instance's pack. Sweeping all 22 packs on window open held the
    -- client at single-digit FPS. LoadZone is a no-op for an unknown zone.
    if mapID and BigWigsLoader and BigWigsLoader.LoadZone and BossModCoreUp() then
        pcall(BigWigsLoader.LoadZone, BigWigsLoader, mapID)
    elseif mapID and BigWigsLoader and BigWigsLoader.LoadZone then
        -- Core refused to load. Not cached: it comes up on its own on zoning in.
        return nil
    else
        -- No map id or an old BigWigs without LoadZone: fall back to the sweep.
        LoadBossModPacks()
        -- Not cached until every pack has landed, or an empty answer pins for the session.
        if bwPacksLoading then return nil end
    end
    local core = _G.BigWigs
    if not (core and type(core.IterateBossModules) == "function") then
        bwOptionCache[encounterID] = false
        return nil
    end
    local target
    for _, m in core:IterateBossModules() do
        if m.IsEncounterID and m:IsEncounterID(encounterID) then target = m break end
    end
    -- toggleOptions/optionHeaders only exist after SetupOptions, which BigWigs' own
    -- options UI also calls before reading.
    if target and target.SetupOptions then target:SetupOptions() end
    local toggles = target and target.toggleOptions
    if type(toggles) ~= "table" then
        bwOptionCache[encounterID] = false
        return nil
    end
    -- optionHeaders marks the option a group starts at, carried onto following entries.
    -- Entries are ids or {id, flag, ...}; string options ("stages", "berserk") are never
    -- broadcast as keys.
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

-- Not cached: the journal side can improve underneath (the cold-load re-scrape).
-- Rows are keyed by the BigWigs id, which is what the engine receives. The journal
-- entry is matched by spell id, then by name, since the id spaces can differ
-- (Possession Barrage: 1292036 in BigWigs, 1284103 in the journal).
local function BigWigsAbilities(encounterID, journalAbilities, mapID)
    local opts = BigWigsOptionList(encounterID, mapID)
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
        local desc = j and j.description
        if (not desc or desc == "") and C_Spell and C_Spell.GetSpellDescription then
            desc = C_Spell.GetSpellDescription(id)
        end
        list[#list + 1] = {
            title       = (j and j.title) or name or ("Spell " .. id),
            spellID     = id,
            icon        = (j and j.icon) or (info and info.iconID),
            extras      = j and j.extras,
            description = (desc and desc ~= "") and desc or nil,
            stage       = opts[i].stage,
        }
    end
    return list
end

-------------------------------------------------------------------------------
--  The tree page
-------------------------------------------------------------------------------
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

-- The attach helpers build onto a row once and re-point it on later builds; rows are reused.
local function AttachRemove(row, entry, specID, EUI, onGone)
    local btn = row._removeBtn
    if not btn then
        btn = CreateFrame("Button", nil, row)
        btn:SetSize(14, 14)
        btn:SetPoint("LEFT", row, "LEFT", 22, 0)
        btn:SetFrameLevel(row:GetFrameLevel() + 6)
        btn._a = ns.Solid(btn, "OVERLAY", ns.THEME.muted, 0.85)
        btn._a:SetSize(10, 2); btn._a:SetPoint("CENTER"); btn._a:SetRotation(math.rad(45))
        btn._b = ns.Solid(btn, "OVERLAY", ns.THEME.muted, 0.85)
        btn._b:SetSize(10, 2); btn._b:SetPoint("CENTER"); btn._b:SetRotation(math.rad(-45))
        row._removeBtn = btn
    end
    local a, b = btn._a, btn._b

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
    local grab = row._grab
    if not grab then
        grab = CreateFrame("Button", nil, row)
        grab:SetSize(14, 22)
        grab:SetPoint("LEFT", row, "LEFT", 4, 0)
        grab:SetFrameLevel(row:GetFrameLevel() + 6)

        for c = 0, 1 do
            for r2 = 0, 2 do
                local d = ns.Solid(grab, "OVERLAY", ns.THEME.muted, 0.85)
                d:SetSize(3, 3)
                d:SetPoint("TOPLEFT", grab, "TOPLEFT", 3 + c * 5, -(4 + r2 * 6))
            end
        end

        grab:RegisterForDrag("LeftButton")
        ns.Tooltip(grab, "Drag to reorder", "Drag this onto another enabled ability to change "
            .. "the order it is called out in.")
        row._grab = grab
    end
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
    return grab
end

local function AttachRowCog(rgn, onClick, tipTitle, tipBody)
    if not rgn then return end
    local EUIg = ns.UI
    local cog = rgn._cog
    if not cog then
        cog = CreateFrame("Button", nil, rgn)
        cog:SetSize(26, 26)
        cog:SetPoint("RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -8, 0)
        rgn._lastInline = cog
        cog:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cog:SetAlpha(0.4)
        local tex = cog:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        if EUIg and EUIg.COGS_ICON then tex:SetTexture(EUIg.COGS_ICON) end
        cog:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
        end)
        rgn._cog = cog
    end
    cog:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
        if EUIg and EUIg.ShowWidgetTooltip and tipTitle then
            EUIg.ShowWidgetTooltip(self, tipBody and (tipTitle .. ": " .. tipBody) or tipTitle)
        end
    end)
    cog:SetScript("OnClick", function() if onClick then onClick() end end)
    return cog
end

-------------------------------------------------------------------------------
--  Preset list editor: the spec-default page, one preset picker on the left
--  and its condensed ability list on the right.
-------------------------------------------------------------------------------

-- Frames are never garbage collected, so this is built once and re-pointed on each open,
-- with per-open values in a state table rather than captured. Add and Rename share it.
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

local function ShowAbilitySettingsPopup(specID, spellID, name, EUI)
    local W = EUI.Widgets
    local dimmer, panel = ns.MakeModal(360, 172, "abilitySettings")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
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

    _, h = W:DualRow(panel, y,
        { type = "toggle", text = "Call Together",
          tooltip = "Tick this on every cooldown that should be called as a set. When one "
          .. "of them comes up, the rest that are ready are named with it -- \"Vampiric "
          .. "Blood and Icebound Fortitude\". Order does not matter, and one on cooldown "
          .. "is simply left out rather than holding the callout back.",
          getValue = function() return ns.CalledTogether(specID, spellID) end,
          setValue = function(v)
              ns.SetCalledTogether(specID, spellID, v)
              if EUI.RefreshPage then EUI:RefreshPage(true) end
          end }
    ); y = y - h

    editBtn = UI.KeepButton(panel, "edit", "Edit Callout", 120, 26, function()
        ns.ShowCalloutEditor(("Audio callout for %s"):format(name),
            ns.CalloutFor(spellID, name), function(text)
                ns.SetCallout(spellID, text)
                if EUI.RefreshPage then EUI:RefreshPage(true) end
            end, spellID)
    end)
    editBtn:SetPoint("BOTTOM", panel, "BOTTOM", -55, 16)
    editBtn:SetShown(not ns.IsAudioOff(spellID))

    local closeBtn = UI.KeepButton(panel, "close", "Close", 90, 26, function() dimmer:Hide() end)
    placeClose = function()
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("BOTTOM", panel, "BOTTOM", editBtn:IsShown() and 65 or 0, 16)
    end
    placeClose()

    dimmer:Show()
end

-- A set renders as one row, so this chooser opens each member's own settings popup.
local function ShowSetSettingsPopup(specID, members, EUI)
    local dimmer, panel = ns.MakeModal(400, 160, "setSettings")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("Called Together")

    local y = -44
    for i = 1, #members do
        local sid = members[i]
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
        local nm = (info and info.name) or ("Spell " .. sid)
        local btn = UI.KeepButton(panel, "member", ns.CalloutFor(sid, nm), 340, 26, function()
            dimmer:Hide()
            ShowAbilitySettingsPopup(specID, sid, nm, EUI)
        end)
        btn:SetPoint("TOP", panel, "TOP", 0, y)
        ns.Tooltip(btn, nm, "Its audio, what it is called out loud, and taking it back "
            .. "out of the set.")
        y = y - 32
    end

    -- 26 for the button row, 16 for the bottom inset, and a gap so they do not touch.
    panel:SetHeight(math.abs(y) + 58)

    UI.KeepButton(panel, "close", "Close", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)

    dimmer:Show()
end

-- The fallback step stores its audio flag under spellID 0 and its text on db.voiceNone,
-- so it cannot share ShowAbilitySettingsPopup's storage calls.
local function ShowFallbackSettingsPopup(EUI)
    local W = EUI.Widgets
    local db = ns.DB()
    local dimmer, panel = ns.MakeModal(360, 178, "fallbackSettings")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
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

    _, h = W:DualRow(panel, y,
        { type = "toggle", text = "Announce in Chat",
          tooltip = "Sends " .. ns.Color("accent", "EXTERNAL!") .. " to party, raid or instance chat when nothing on "
          .. "your list is up, so whoever is watching for it can react. Group chat only, and at "
          .. "most once every three seconds however many telegraphs land together.",
          disabled = function() return db.fallbackOn == false end,
          disabledTooltip = "Switch the last step back on to use this.",
          getValue = function() return db.externalChat == true end,
          setValue = function(v)
              if db.fallbackOn == false then return end
              db.externalChat = v and true or false
          end }
    ); y = y - h

    editBtn = UI.KeepButton(panel, "edit", "Edit Callout", 120, 26, function()
        ns.ShowCalloutEditor("Said and shown when nothing on the list is up",
            db.voiceNone, function(v)
                db.voiceNone = v
                ns.RefreshRuntime()
            end, 0)
    end)
    editBtn:SetPoint("BOTTOM", panel, "BOTTOM", -55, 16)
    editBtn:SetShown(db.fallbackOn ~= false and not ns.IsAudioOff(0))

    local closeBtn = UI.KeepButton(panel, "close", "Close", 90, 26, function() dimmer:Hide() end)
    placeClose = function()
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("BOTTOM", panel, "BOTTOM", editBtn:IsShown() and 65 or 0, 16)
    end
    placeClose()

    dimmer:Show()
end

local function NewPresetRow(leftPane)
    local prow = CreateFrame("Button", nil, leftPane)
    prow.bg = ns.Solid(prow, "BACKGROUND", ns.THEME.grey, 0.55)
    prow.bg:SetAllPoints()

    prow.lbl = ns.Font(prow, 13, nil, ns.THEME.muted)
    prow.lbl:SetJustifyH("LEFT")
    prow.lbl:SetWordWrap(false)

    local edit = ns.Font(prow, 11, nil, ns.THEME.muted)
    edit:SetText("Edit")
    local editHit = CreateFrame("Button", nil, prow)
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
    prow.editHit = editHit

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
                ns.Color("accent", "Delete Preset") .. "\nRemoves this preset and its list. Cannot be undone.")
        end
    end)
    del:SetScript("OnLeave", function()
        local c = ns.THEME.muted
        a:SetColorTexture(c.r, c.g, c.b, 0.85); b:SetColorTexture(c.r, c.g, c.b, 0.85)
        local EUIg = ns.UI
        if EUIg and EUIg.HideWidgetTooltip then EUIg.HideWidgetTooltip() end
    end)
    prow.del = del
    return prow
end

local function BuildPresetRow(leftPane, ly, rowW, rowH, specID, p, isActive, canDelete, EUI)
    local prow = UI.Keep(leftPane, "presetRow", NewPresetRow)
    prow:SetSize(rowW, rowH)
    prow:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, ly)
    prow.bg:SetShown(isActive)

    local lbl = prow.lbl
    local c = isActive and ns.THEME.accent or ns.THEME.muted
    lbl:SetTextColor(c.r, c.g, c.b, 1)
    lbl:ClearAllPoints()
    lbl:SetPoint("LEFT", prow, "LEFT", 8, 0)
    lbl:SetPoint("RIGHT", prow, "RIGHT", canDelete and -56 or -34, 0)
    lbl:SetText(p.name)

    prow:SetScript("OnClick", function()
        ns.SelectPreset(specID, p.key)
        EUI:RefreshPage(true)
    end)

    local editHit = prow.editHit
    editHit:SetSize(28, rowH)
    editHit:ClearAllPoints()
    editHit:SetPoint("RIGHT", prow, "RIGHT", canDelete and -26 or -6, 0)
    editHit:SetScript("OnClick", function() ShowRenamePresetPopup(specID, p.key, p.name, EUI) end)

    prow.del:SetShown(canDelete)
    prow.del:SetScript("OnClick", function()
        ns.DeletePreset(specID, p.key)
        EUI:RefreshPage(true)
    end)

    return prow
end

-- Per-boss overrides go through RenderInstanceDetail/RenderAbilityRow instead, keyed by spell id.
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

    local leftPane = UI.Keep(parent, "presetLeft", function(p) return CreateFrame("Frame", nil, p) end)
    leftPane:SetSize(LEFT_W, 10)
    leftPane:SetPoint("TOPLEFT", parent, "TOPLEFT", EUI.CONTENT_PAD, topY)

    local rightPane = UI.Keep(parent, "presetRight", function(p) return CreateFrame("Frame", nil, p) end)
    rightPane:SetSize(rightW, 10)
    rightPane:SetPoint("TOPLEFT", parent, "TOPLEFT", EUI.CONTENT_PAD + LEFT_W + GAP, topY)

    local ly = 0
    for i = 1, #presets do
        local p = presets[i]
        BuildPresetRow(leftPane, ly, LEFT_W, PRESET_ROW_H, specID, p,
            p.key == activeKey, #presets > 1, EUI)
        ly = ly - PRESET_ROW_H
    end

    local addRow = UI.Keep(leftPane, "addPreset", function(host)
        local b = CreateFrame("Button", nil, host)
        local addLbl = ns.Font(b, 13, nil, ns.THEME.muted)
        addLbl:SetPoint("LEFT", b, "LEFT", 8, 0)
        addLbl:SetText("+ Add Preset")
        b:SetScript("OnEnter", function()
            local c = ns.THEME.fg
            addLbl:SetTextColor(c.r, c.g, c.b, 1)
        end)
        b:SetScript("OnLeave", function()
            local c = ns.THEME.muted
            addLbl:SetTextColor(c.r, c.g, c.b, 1)
        end)
        return b
    end)
    addRow:SetSize(LEFT_W, PRESET_ROW_H)
    addRow:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, ly)
    addRow:SetScript("OnClick", function() ShowAddPresetPopup(specID, EUI) end)
    ly = ly - PRESET_ROW_H

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

    -- The set is drawn as one row at its first member's position. Talented members only:
    -- RebuildSlots drops untalented spells, so they could never be called with the set.
    local setMembers
    for i = 1, #list do
        if ns.CalledTogether(specID, list[i]) and ns.IsSpellAvailable(list[i]) then
            setMembers = setMembers or {}
            setMembers[#setMembers + 1] = list[i]
        end
    end
    if setMembers and #setMembers < 2 then setMembers = nil end

    local setDrawn = false
    for i = 1, #list do
        local spellID = list[i]
        local idx = i
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        local name = (info and info.name) or ("Spell " .. spellID)
        local inSet = setMembers and ns.CalledTogether(specID, spellID)
            and ns.IsSpellAvailable(spellID)
        local skip = inSet and setDrawn

        if not skip then
            local label
            if inSet then
                setDrawn = true
                local said
                for m = 1, #setMembers do
                    local mi = C_Spell and C_Spell.GetSpellInfo
                        and C_Spell.GetSpellInfo(setMembers[m])
                    local one = ns.CalloutFor(setMembers[m], mi and mi.name)
                    said = said and (said .. " and " .. one) or one
                end
                label = ("      %d.  %s"):format(idx, said)
            else
                label = ("      %d.  %s"):format(idx, name)
                if not ns.IsSpellAvailable(spellID) then
                    label = label .. "  (not talented)"
                end
            end

            row, h = W:DualRow(rightPane, ry,
                { type = "toggle", text = label,
                  tooltip = inSet
                      and "Called as one. Open the cog to rename either half or take one out."
                      or ("Spell ID %d. Untick to drop it to the bottom of the list."):format(spellID),
                  getValue = function() return true end,
                  -- The whole set leaves together, or the other half reappears on its own row.
                  setValue = function()
                      if inSet then
                          for m = 1, #setMembers do
                              ns.SetSpellOnList(specID, nil, setMembers[m], false)
                          end
                      else
                          ns.SetSpellOnList(specID, nil, spellID, false)
                      end
                      EUI:RefreshPage(true)
                  end }
            ); ry = ry - h

            if row then
                dragRows[#dragRows + 1] = { frame = row, spellID = spellID, index = idx }
                AttachGrabber(row, spellID, idx, specID, nil, EUI)
                AttachRemove(row, { id = spellID, userAdded = false }, specID, EUI, function()
                    for m = 1, (inSet and #setMembers or 1) do
                        local rid = inSet and setMembers[m] or spellID
                        ns.SetSpellOnList(specID, nil, rid, false)
                        ns.HideSpell(specID, rid)
                    end
                end)
                -- Single-column row, so the toggle lives in the left region.
                AttachRowCog(row._leftRegion, function()
                    if inSet then
                        ShowSetSettingsPopup(specID, setMembers, EUI)
                    else
                        ShowAbilitySettingsPopup(specID, spellID, name, EUI)
                    end
                end, "Settings", inSet and "What each half is called, and leaving the set."
                    or "Audio, and anything added later.")
            end
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
              text = "      " .. ns.Color("muted", c.name .. (c.userAdded and " (added by you)" or "")),
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

    local db = ns.DB()
    row, h = W:DualRow(rightPane, ry,
        { type = "toggle",
          text = ("      " .. ns.Color("accent", "Last:  %s")):format(db.voiceNone or "Call for an External"),
          tooltip = "The final step, used when nothing on your list is up. Switch it off to say "
          .. "and show nothing at all in that case.\n\nThis is the default for the whole spec. "
          .. "An individual ability can override it from its own cog on a boss page, for hits "
          .. "the raid was never going to answer.",
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

    -- The widget factory has no text input, so the box is laid over the row's right half.
    row, h = W:DualRow(rightPane, ry,
        { type = "label", text = "      Add an Ability by Spell ID" },
        { type = "label", text = "" }   -- overlaid below with the entry box and Add button
    ); ry = ry - h

    if row and row._rightRegion then
        local rgn = row._rightRegion

        if not rgn._spellBox then
            local add = ns.Button(rgn, "Add", 54, 22, nil)
            add:SetPoint("RIGHT", rgn, "RIGHT", -14, 0)

            local box = ns.NewEditBox(rgn)
            box:SetPoint("LEFT", rgn, "LEFT", 6, 0)
            box:SetPoint("RIGHT", add, "LEFT", -8, 0)
            box:SetHeight(24)
            box:SetNumeric(true)
            box:SetMaxLetters(9)

            box.placeholder = ns.Font(box, 12, nil, ns.THEME.muted)
            box.placeholder:SetPoint("LEFT", box, "LEFT", 8, 0)
            box.placeholder:SetText("Enter SpellID")

            box.feedback = ns.Font(rgn, 10, nil, ns.THEME.muted)
            box.feedback:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -1)
            box.feedback:SetPoint("RIGHT", add, "LEFT", -8, 0)
            box.feedback:SetJustifyH("LEFT")
            box.add = add
            rgn._spellBox = box
        end
        local box = rgn._spellBox
        local add, placeholder, feedback = box.add, box.placeholder, box.feedback

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
        box:SetText("")
        Validate()
    end

    return topY + math.min(ly, ry)
end

-- The Enable This Boss toggle lives on the boss-picker row in RenderInstanceDetail.
local function RenderBossHeader(parent, y, W, EUI, encounterID, specID)
    local _, h

    -- Shows the spec's active preset until one is picked; opening it writes nothing.
    local presets = ns.ListPresets(specID)
    if #presets > 0 then
        local presetValues, presetOrder = {}, {}
        for i = 1, #presets do
            presetValues[presets[i].key] = presets[i].name
            presetOrder[i] = presets[i].key
        end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Cooldown Preset",
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
local TRIGGER_CHOICES = { bwmsg = "BigWigs Message Timer",
    caststart = "Boss Cast Starts", castend = "Boss Cast Finishes" }
local TRIGGER_ORDER = { "bwmsg", "caststart", "castend" }

local SHOW_IN_TIP = "Seconds after the trigger. Blank or zero fires immediately. "
    .. "For messages, the delay starts only when BigWigs/DBM sends the message. "
    .. "Enable Messages for this ability in BigWigs; disabled messages cannot trigger reminders."
local COUNTER_TIP = "Blank fires every time. Match a count with >N, >=N, <N, <=N, !N (not "
    .. "N) or a bare number (exactly N). Separate conditions with a comma to match any of "
    .. "them, or add a leading + on the second one to require both -- example: >3,+<7 "
    .. "fires between 4 and 6."

-- Negative BigWigs keys are -sectionID of a Dungeon Journal section.
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
    if type(entry.text) == "string" and entry.text ~= "" then return entry.text end
    return "Key " .. tostring(key)
end

function ns.ReminderAbilityChoices(encounterID)
    local byKey = {}
    local function Add(key, text, mod)
        if type(key) ~= "number" or key == 0 then return end
        if not byKey[key] then byKey[key] = { key = key, entry = { text = text, mod = mod } } end
    end
    local data = ns.ScrapeBosses and ns.ScrapeBosses(false)
    for _, inst in ipairs(data and data.instances or {}) do
        for _, boss in ipairs(inst.bosses or {}) do
            if boss.encounterID == encounterID then
                for _, ability in ipairs(BigWigsAbilities(encounterID, nil, inst.mapID) or {}) do
                    Add(ability.spellID, ability.title, "BW")
                end
            end
        end
    end
    local list = {}
    for _, item in pairs(byKey) do list[#list + 1] = item end
    table.sort(list, function(a, b)
        local an, bn = ResolveMechanicName(a.key, a.entry), ResolveMechanicName(b.key, b.entry)
        if an == bn then return a.key < b.key end
        return an < bn
    end)
    return list
end

-- callerEUI is the caller's own EUI proxy, so its RefreshPage re-renders that caller's list.
function ns.ShowCustomReminderEditor(encounterID, uid, callerEUI, initialTrigger)
    local EUI = callerEUI or ns.UI
    local W = EUI.Widgets

    local dimmer, panel = ns.MakeModal(480, 740, "customReminderEditor")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(uid and "Edit Reminder" or "New Reminder")

    local set = ns.CustomRemindersTable(false, encounterID)
    local existing = (set and uid) and set[uid] or nil
    local trig = (existing and existing.trigger)
        or { type = initialTrigger or "bwmsg" }

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

    local triggerBody = UI.Keep(panel, "triggerBody", function(p) return CreateFrame("Frame", nil, p) end)
    triggerBody:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -42)
    triggerBody:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -42)
    triggerBody:SetHeight(650)
    local messageBody = UI.Keep(triggerBody, "messageBody", function(p) return CreateFrame("Frame", nil, p) end)
    messageBody:SetSize(480, 230)

    local my = 0

    local function AddLabelM(text, tooltip)
        local l = UI.KeepFont(messageBody, "label", 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", messageBody, "TOPLEFT", PAD, my)
        l:SetText(text)
        if tooltip then
            local hit = UI.Keep(messageBody, "labelHit", function(p) return CreateFrame("Frame", nil, p) end)
            hit:SetPoint("TOPLEFT", l, "TOPLEFT", -4, 4)
            hit:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 4, -4)
            HoverTip(hit, tooltip)
        end
        my = my - 16
    end

    local function AddBoxM(maxLetters, numeric, rightInset)
        local box = UI.Keep(messageBody, "box", ns.NewEditBox)
        box:SetPoint("TOPLEFT", messageBody, "TOPLEFT", PAD, my)
        box:SetPoint("RIGHT", messageBody, "RIGHT", -(rightInset or PAD), 0)
        box:SetHeight(26)
        box:SetMaxLetters(maxLetters or 60)
        box:SetNumeric(numeric == true)
        my = my - 32
        return box
    end

    AddLabelM("Name")
    local nameBox = AddBoxM(40)
    nameBox:SetText((existing and existing.name) or "")

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

    AddLabelM("Linger (seconds)")
    local durBox = AddBoxM(3, true)
    durBox:SetText(tostring((existing and existing.dur) or 3))

    local healerVal = existing and existing.healerReminder == true or false
    local enabledVal = (existing == nil) or existing.enabled ~= false
    W:DualRow(messageBody, my,
        { type = "toggle", text = "Enabled",
          getValue = function() return enabledVal end,
          setValue = function(v) enabledVal = v end },
        { type = "toggle", text = "Healer Reminder",
          tooltip = "Mark this reminder so players can opt out with Enable Healer Reminders in Setup.",
          getValue = function() return healerVal end,
          setValue = function(v) healerVal = v end }
    )

    -------------------------------------------------------------------------
    --  Trigger tab: type, mechanic picker, dynamic fields.
    -------------------------------------------------------------------------
    -- Legacy records retain their data until saved explicitly in this editor.
    local trigVal = (trig.type == "caststart" or trig.type == "castend")
        and trig.type or "bwmsg"

    local spellIDText = (trig.spellID and tostring(trig.spellID)) or ""
    local counterText = (type(trig.counter) == "string" and trig.counter)
        or (type(trig.counter) == "number" and tostring(trig.counter)) or ""
        local delayText = (trig.type ~= "combat" and type(trig.delay) == "string" and trig.delay) or ""

    -- Rebuilt on every trigger change; typed values are saved to the *Text locals first.
    local dynFrame = UI.Keep(triggerBody, "dynFrame", function(p) return CreateFrame("Frame", nil, p) end)
    local spellBox, counterBox, delayBox
    local DYN_Y   -- set below, once the Trigger dropdown row's height is known
    local RebuildDynFields
    local triggerRow -- the Trigger dropdown's own row handle, so a picker pick can refresh its label

    local function SaveDynFieldsToText()
        if spellBox then spellIDText = spellBox:GetText() or "" end
        if counterBox then counterText = counterBox:GetText() or "" end
        if delayBox then delayText = delayBox:GetText() or "" end
    end

    -- A picker pick changes the trigger outside the dropdown's setValue, so its label is refreshed.
    local function RefreshTriggerLabel()
        local ctrl = triggerRow and triggerRow._leftRegion and triggerRow._leftRegion._control
        if ctrl and ctrl._refreshLabel then ctrl._refreshLabel() end
    end

    local triggerRowH
    triggerRow, triggerRowH = W:DualRow(triggerBody, 0,
        { type = "dropdown", text = "Trigger",
          values = TRIGGER_CHOICES,
          order = TRIGGER_ORDER,
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

    -- Picking a mechanic fills the Spell ID field exactly as typing it would.
    -- Anchored at DYN_Y, not 0: at 0 the picker sat on top of the Trigger dropdown.
    -- The rows live on the scroll frame, which outlasts this open, so the next one reuses them.
    local pickerScroll = UI.Keep(triggerBody, "pickerScroll", function(p)
        local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        sf.content = CreateFrame("Frame", nil, sf)
        sf.content:SetSize(418, 1)
        sf:SetScrollChild(sf.content)
        sf.rows = {}
        return sf
    end)
    pickerScroll:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, DYN_Y)
    pickerScroll:SetPoint("TOPRIGHT", triggerBody, "TOPRIGHT", -PAD - 22, DYN_Y)
    pickerScroll:SetHeight(120)
    local pickerContent, pickerRows = pickerScroll.content, pickerScroll.rows
    local function MakePickerRow(i)
        local row = CreateFrame("Button", nil, pickerContent)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", pickerContent, "TOPLEFT", 0, 0)
        row:SetPoint("RIGHT", pickerContent, "RIGHT", 0, 0)

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
        return row
    end
    local pickerHint = UI.KeepFont(triggerBody, "pickerHint", 10, nil, ns.THEME.muted)
    pickerHint:SetPoint("RIGHT", triggerBody, "RIGHT", -PAD, 0)
    pickerHint:SetJustifyH("LEFT")
    local PICKER_ROW_H = 24
    local PICKER_HEIGHT = 0

    local function RebuildPicker()
        for i = 1, #pickerRows do pickerRows[i]:Hide() end
        local list = ns.ReminderAbilityChoices(encounterID)
        pickerScroll:SetShown(#list > 0)
        pickerScroll:SetVerticalScroll(0)
        pickerContent:SetHeight(math.max(1, #list * PICKER_ROW_H))
        local height = math.min(120, #list * PICKER_ROW_H)
        pickerScroll:SetHeight(math.max(1, height))
        for i = 1, #list do
            local item = list[i]
            local row = pickerRows[i] or MakePickerRow(i)
            row:SetPoint("TOPLEFT", pickerContent, "TOPLEFT", 0, -(i - 1) * PICKER_ROW_H)
            row.icon:SetTexture(ResolveMechanicIcon(item.key))
            row.name:SetText(ResolveMechanicName(item.key, item.entry))
            row.tag:SetText(item.entry.mod or "Journal")
            row:SetScript("OnClick", function()
                SaveDynFieldsToText()
                spellIDText = tostring(item.key)
                RefreshTriggerLabel()
                RebuildDynFields()
            end)
            row:Show()
        end
        pickerHint:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, DYN_Y - height - 4)
        pickerHint:SetText(#list == 0 and "No BigWigs abilities available for this boss. Enter a spell ID below."
            or (trigVal == "bwmsg" and "Only abilities announced by BigWigs/DBM can trigger a message reminder." or "Select the spell the boss casts."))
        pickerHint:SetHeight(28)
        PICKER_HEIGHT = height + 36
    end

    RebuildDynFields = function()
        RebuildPicker()

        UI.BeginReusableRows(dynFrame)
        dynFrame:ClearAllPoints()
        dynFrame:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", 0, DYN_Y - PICKER_HEIGHT)
        dynFrame:SetSize(480, 210)
        spellBox, counterBox, delayBox = nil, nil, nil

        local dy = 0
        local function DLabel(text, tooltip)
            local l = UI.KeepFont(dynFrame, "label", 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", dynFrame, "TOPLEFT", PAD, dy)
            l:SetText(text)
            if tooltip then
                local hit = UI.Keep(dynFrame, "labelHit", function(p) return CreateFrame("Frame", nil, p) end)
                hit:SetPoint("TOPLEFT", l, "TOPLEFT", -4, 4)
                hit:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 4, -4)
                HoverTip(hit, tooltip)
            end
            dy = dy - 16
        end
        local function DBox(maxLetters, numeric, rightInset)
            local box = UI.Keep(dynFrame, "box", ns.NewEditBox)
            box:SetPoint("TOPLEFT", dynFrame, "TOPLEFT", PAD, dy)
            box:SetPoint("RIGHT", dynFrame, "RIGHT", -(rightInset or PAD), 0)
            box:SetHeight(26)
            box:SetMaxLetters(maxLetters or 60)
            box:SetNumeric(numeric == true)
            dy = dy - 32
            return box
        end

        DLabel(trigVal == "bwmsg" and "Message Spell ID / Key" or "Spell ID")
        spellBox = DBox(12)
        spellBox:SetText(spellIDText)
        DLabel("Counter", COUNTER_TIP)
        counterBox = DBox(40)
        counterBox:SetText(counterText)
        DLabel(trigVal == "bwmsg" and "Show seconds after the message" or "Show in",
            SHOW_IN_TIP)
        delayBox = DBox(60)
        delayBox:SetText(delayText)
        messageBody:ClearAllPoints()
        messageBody:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", 0,
            DYN_Y - PICKER_HEIGHT + dy - 12)
    end
    RebuildDynFields()

    local function BuildTrigger()
        SaveDynFieldsToText()
        local sid = tonumber(spellIDText)
        if not sid or sid == 0 or sid ~= math.floor(sid) then return nil end
        if trigVal ~= "bwmsg" and sid < 0 then return nil end
        if delayText ~= "" then
            local delay = tonumber(delayText)
            if not delay or delay < 0 then return nil end
        end
        local newTrig = { type = trigVal, spellID = sid,
            counter = (counterText ~= "" and counterText) or nil,
            delay = (delayText ~= "" and delayText) or nil }
        return newTrig
    end

    local function Save()
        local newTrig = BuildTrigger()
        if not newTrig then
            ns.Print("|cffff6060Enter a valid spell/key and a delay of zero or more seconds.|r")
            return
        end
        local name = nameBox:GetText()
        if not name or name == "" then name = "Reminder" end
        local dur = tonumber(durBox:GetText()) or 3
        local writeSet = ns.CustomRemindersTable(true, encounterID)
        local key = uid or ("r" .. math.floor(GetTime() * 1000) .. math.random(1, 9999))
        writeSet[key] = {
            name = name, preset = presetVal, trigger = newTrig,
            dur = math.max(1, dur), enabled = enabledVal, healerReminder = healerVal or nil,
            defensive = true, specID = editorSpecID,
        }
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end

    UI.KeepButton(panel, "save", "Save", 90, 26, Save):SetPoint("BOTTOM", panel, "BOTTOM", -10, 16)
    UI.KeepButton(panel, "cancel", "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 90, 16)

    dimmer:Show()
    -- Returned so a caller can set dimmer.onClose and refresh its own list.
    return dimmer, panel
end

function ns.BuildProfileSettings(parent, y)
    local EUI = ns.UI
    local W   = EUI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "PROFILES", y); y = y - h

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
        { type = "toggle", text = "Match My Spec",
          tooltip = "Loads the profile bound to whatever spec you switch to, on login and on "
          .. "every spec change. A whole-file import sets those bindings up; after that, "
          .. "picking a profile yourself binds it to the spec you are playing.",
          getValue = function() return ns.AutoSpecProfile() end,
          setValue = function(v)
              ns.AutoSpecProfile(v)
              if v and ns.ApplySpecProfile and ns.CurrentSpec then
                  ns.ApplySpecProfile((ns.CurrentSpec()))
              end
              EUI:RefreshPage(true)
          end }
    ); y = y - h

    -- Assigned below; the save buttons' closures need it in scope.
    local ConfirmOn

    local profRow
    profRow, h = W:DualRow(parent, y,
        { type = "label", text = "" },
        { type = "label", text = "" }
    ); y = y - h
    if profRow then
        local function AfterChange()
            EUI:RefreshPage(true)
        end
        -- The rows are reused, so their buttons are made once and re-pointed on each build.
        local left, right = profRow._leftRegion, profRow._rightRegion
        left._newBtn = left._newBtn or ns.Button(left, "New Profile", 110, 22)
        left._copyBtn = left._copyBtn or ns.Button(left, "Save As New Profile", 150, 22)
        right._mergeBtn = right._mergeBtn or ns.Button(right, "Merge a Profile In", 150, 22)

        local newBtn = left._newBtn
        newBtn._onClick = function()
            ShowNamePrompt("New Profile", "Create", "", function(text)
                local name = text:match("^%s*(.-)%s*$")
                if ns.ProfileExists and ns.ProfileExists(name) then
                    ConfirmOn("Replace", "It starts empty at default settings, on every "
                        .. "character standing in it. Cannot be undone.", "Replace", name,
                        function(n)
                            local ok, err = ns.CreateProfile(n, true)
                            if not ok then return false, err end
                            ns.SwitchProfile(n)
                            return true
                        end)
                    return
                end
                local ok, err = ns.CreateProfile(name)
                if not ok then ns.Print(err) return end
                ns.SwitchProfile(name)
                AfterChange()
            end)
        end
        newBtn:SetPoint("LEFT", profRow._leftRegion, "LEFT", 20, 0)
        ns.Tooltip(newBtn, "New Profile", "A fresh profile with default settings. It becomes "
            .. "the one every character on this account uses, including any you log into "
            .. "later. Switch a single character afterwards if you want it on its own.")
        -- No plain Save: every change is written into the profile as it is made.
        local copyBtn = left._copyBtn
        copyBtn._onClick = function()
            ShowNamePrompt("Save As New Profile", "Save", "", function(text)
                local name = text:match("^%s*(.-)%s*$")
                if ns.ProfileExists and ns.ProfileExists(name) then
                    ConfirmOn("Overwrite", "Everything set up right now replaces what is "
                        .. "stored under it, on every character standing in it. Cannot be "
                        .. "undone.", "Overwrite", name,
                        function(n)
                            local ok, err = ns.CopyProfile(ns.ActiveProfileName(), n, true)
                            if not ok then return false, err end
                            ns.SwitchProfile(n)
                            return true
                        end)
                    return
                end
                local ok, err = ns.CopyProfile(ns.ActiveProfileName(), name)
                if not ok then ns.Print(err) return end
                ns.SwitchProfile(name)
                AfterChange()
            end)
        end
        copyBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)
        ns.Tooltip(copyBtn, "Save As New Profile", "Stores everything set up right now as a "
            .. "new profile under a name you choose, and switches to it. Your current "
            .. "profile is left as it was.")

        -- Import always lands a new profile; this merges into an existing one.
        local mergeBtn = right._mergeBtn
        mergeBtn._onClick = function()
            if ns.ShowProfileMergeDialog then ns.ShowProfileMergeDialog() end
        end
        mergeBtn:SetPoint("LEFT", profRow._rightRegion, "LEFT", 20, 0)
        ns.Tooltip(mergeBtn, "Merge a Profile In", "Takes a profile string somebody else "
            .. "maintains and merges it into one of yours. A spec they look after "
            .. "replaces yours for that spec; specs they do not cover are left exactly "
            .. "as they are, and per-boss reminders are added rather than swapped.")
    end

    -- Reset and Delete pick their target, so deleting a profile does not mean loading it first.
    local pickValues, pickOrder = { [""] = "Choose a profile..." }, { "" }
    for i = 1, #profNames do
        pickValues[profNames[i]] = profNames[i]
        pickOrder[#pickOrder + 1] = profNames[i]
    end

    -- Confirms name the chosen profile, not the one in use.
    ConfirmOn = function(title, hintText, verb, chosen, act)
        local dimmer, panel = ns.MakeModal(360, 140, "profileActConfirm")
        local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
        head:SetPoint("TOP", panel, "TOP", 0, -16)
        head:SetText(("%s '%s'?"):format(title, chosen))
        local hint = UI.KeepFont(panel, "hint", 11, nil, ns.THEME.muted)
        hint:SetPoint("TOP", head, "BOTTOM", 0, -8)
        hint:SetPoint("LEFT", panel, "LEFT", 16, 0)
        hint:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
        hint:SetText(hintText)
        local yes = UI.KeepButton(panel, "yes", verb, 100, 24, function()
            local ok, err = act(chosen)
            if not ok and err then ns.Print(err) end
            dimmer:Hide()
            EUI:RefreshPage(true)
        end)
        yes:SetPoint("BOTTOM", panel, "BOTTOM", -56, 14)
        UI.KeepButton(panel, "cancel", "Cancel", 100, 24, function()
            dimmer:Hide()
            EUI:RefreshPage(true)
        end):SetPoint("BOTTOM", panel, "BOTTOM", 56, 14)
        dimmer:Show()
    end

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Reset Profile",
          values = pickValues, order = pickOrder,
          tooltip = "Wipes the chosen profile's settings back to defaults. Every other "
          .. "profile is untouched, and you do not have to be standing in it.",
          getValue = function() return "" end,
          setValue = function(v)
              if v == "" then return end
              ConfirmOn("Reset", "Every setting in it returns to default. Cannot be undone.",
                  "Reset", v, ns.ResetProfileNamed)
          end },
        { type = "dropdown", text = "Delete Profile",
          values = pickValues, order = pickOrder,
          tooltip = "Removes the chosen profile. Characters using it move to the account's "
          .. "default profile, and the last profile cannot be deleted.",
          getValue = function() return "" end,
          setValue = function(v)
              if v == "" then return end
              ConfirmOn("Delete", "Cannot be undone. Characters using it move to the "
                  .. "account's default profile.", "Delete", v, ns.DeleteProfile)
          end }
    ); y = y - h
    local packRow
    packRow, h = W:DualRow(parent, y,
        { type = "label", text = "      Share your Smart Reminders" },
        { type = "label", text = "" }
    ); y = y - h
    -- Not AttachInline: this right half has no control, so it would anchor off the row's
    -- midpoint and overlap the label.
    if packRow and packRow._rightRegion then
        local rgn = packRow._rightRegion
        rgn._btn = rgn._btn or ns.Button(rgn, "Share your Profile", 130, 22, function()
            if ns.ShowPackExport then ns.ShowPackExport() end
        end)
        local btn = rgn._btn
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
        local rgn = packRow2._rightRegion
        rgn._btn = rgn._btn or ns.Button(rgn, "Import Profile", 120, 22, function()
            if ns.ShowPackImport then ns.ShowPackImport() end
        end)
        local btn = rgn._btn
        btn:SetPoint("RIGHT", packRow2._rightRegion, "RIGHT", -14, 0)
        ns.Tooltip(btn, "Import Profile",
            "Paste a profile string. Nothing applies until you press Import, and a damaged "
            .. "string is refused outright.")
    end

    return y
end

-- Module-level so the selection survives a RefreshPage; per tab, so a dungeon pick
-- leaves the raid selection alone.
local selectedInst = { dungeon = nil, raid = nil }
local selectedBossIdx = {}   -- keyed by instance.id

-------------------------------------------------------------------------------
--  Per-ability reminder picker, built on the Raid Reminder engine
--  (NaowhForever_RaidReminders.lua).
-------------------------------------------------------------------------------
local RR_ROLE_VALUES = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local RR_ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

-- Categories join with " + " (AND), values within one with "/" (OR), matching
-- ns.RaidReminderTargetsMe.
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
    p = Joined(target.specs, ns.SpecName); if p then parts[#parts + 1] = p end
    p = Joined(target.names, nil, ", "); if p then parts[#parts + 1] = p end
    p = Joined(target.subgroups, function(k) return "Group " .. k end); if p then parts[#parts + 1] = p end

    if #parts == 0 then return "Everyone" end
    return table.concat(parts, " + ")
end

-- abilitySpellID is the journal spellID, which can differ from trigger.spellID (the
-- BigWigs key). One per ability; first match wins.
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
-- LOCALIZED_CLASS_NAMES_MALE includes unplayable tokens (Adventurer, Traveler);
-- GetClassInfo over GetNumClasses walks only the playable set.
function ns.PlayableClasses()
    local out = {}
    if GetNumClasses and GetClassInfo then
        for i = 1, GetNumClasses() do
            local displayName, token = GetClassInfo(i)
            if token and displayName then out[#out + 1] = { token, displayName } end
        end
    end
    if #out == 0 then
        for token, displayName in pairs(_G.LOCALIZED_CLASS_NAMES_MALE or {}) do
            out[#out + 1] = { token, displayName }
        end
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

-- A binding's own spec always loads it, so this only describes the extra role/class shares.
function ns.DescribeBindingScope(scope)
    if type(scope) ~= "table" or not next(scope) then return "this spec only" end
    local parts = { "this spec" }

    local roles = {}
    for role in pairs(scope.roles or {}) do
        roles[#roles + 1] = (role == "DAMAGER" and "DPS") or (role:sub(1, 1) .. role:sub(2):lower())
    end
    table.sort(roles)
    if #roles > 0 then parts[#parts + 1] = "any " .. table.concat(roles, "/") end

    local classes = {}
    local names = _G.LOCALIZED_CLASS_NAMES_MALE or {}
    for token in pairs(scope.classes or {}) do
        classes[#classes + 1] = names[token] or token
    end
    table.sort(classes)
    if #classes > 0 then parts[#parts + 1] = "any " .. table.concat(classes, "/") end

    return table.concat(parts, " + ")
end

-- Roles and classes only; a per-spec list would not fit this modal.
function ns.ShowBindingScopePicker(scope, onAccept)
    local dimmer, panel = ns.MakeModal(400, 470, "bindingScopePicker")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("Loads for")

    local hint = UI.KeepFont(panel, "hint", 10, nil, ns.THEME.muted)
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -40)
    hint:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("The spec that made this always loads it. Tick anything here to share it with other specs as well.")

    -- Working copies, so Cancel leaves the saved scope untouched.
    local roles, classes = {}, {}
    for k in pairs(type(scope) == "table" and scope.roles or {}) do roles[k] = true end
    for k in pairs(type(scope) == "table" and scope.classes or {}) do classes[k] = true end

    local y = -74
    local function Label(text)
        local l = UI.KeepFont(panel, "label", 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
        l:SetText(text)
        y = y - 18
    end
    local function Grid(items, set, perRow, itemW, colorFn)
        for i = 1, #items do
            local key, label = items[i][1], items[i][2]
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            local check = UI.Keep(panel, "check", function(p)
                local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
                c:SetSize(18, 18)
                return c
            end)
            check:SetPoint("TOPLEFT", panel, "TOPLEFT", 20 + col * itemW, y - row * 22)
            check:SetChecked(set[key])
            check:SetScript("OnClick", function(self)
                set[key] = self:GetChecked() and true or nil
            end)
            local lbl = UI.KeepFont(panel, "checkLabel", 10, nil, ns.THEME.fg)
            lbl:SetPoint("LEFT", check, "RIGHT", 2, 0)
            lbl:SetWordWrap(false)
            lbl:SetText(label)
            if colorFn then
                local r, g, b = colorFn(key)
                if r then lbl:SetTextColor(r, g, b, 1) end
            end
        end
        y = y - math.ceil(#items / perRow) * 22 - 10
    end

    Label("Also load for any of these roles")
    Grid({ { "TANK", "Tank" }, { "HEALER", "Healer" }, { "DAMAGER", "DPS" } }, roles, 3, 110)

    Label("...or any of these classes")
    do
        local items = ns.PlayableClasses()
        local colors = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS
        Grid(items, classes, 3, 120, function(token)
            local c = colors and colors[token]
            if c then return c.r, c.g, c.b end
        end)
    end

    UI.KeepButton(panel, "accept", "Accept", 90, 26, function()
        local out = {}
        if next(roles) then out.roles = roles end
        if next(classes) then out.classes = classes end
        -- nil rather than an empty table, so it stays out of SavedVariables.
        onAccept(next(out) and out or nil)
        dimmer:Hide()
    end):SetPoint("BOTTOM", panel, "BOTTOM", -50, 16)
    UI.KeepButton(panel, "cancel", "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 50, 16)

    dimmer:Show()
end



function ns.ShowAbilityReminderPicker(encounterID, ability, callerEUI)
    local EUI = callerEUI or ns.UI

    local dimmer, panel = ns.MakeModal(440, 640, "abilityReminderPicker")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(ability.title or "Ability")

    local PAD = 20
    local TAB_TOP = -46

    local binding = ns.EnsureBinding(encounterID, ability.spellID)
    local specID = ns.CurrentSpec and ns.CurrentSpec()
    -- Held until Save, so Cancel discards a scope change too.
    local scopeVal = binding.scope
    local healerVal = binding.healerReminder == true
    -- These are lazily initialized in RebuildBody and outlive it: re-deriving them on a
    -- rebuild (tab or preset switch) would stomp an unsaved choice.
    local leadTimeVal
    local externalVal

    local body = UI.Keep(panel, "body", function(p) return CreateFrame("Frame", nil, p) end)
    local presetVal

    local RebuildBody

    -- The tabs are independent, not a mode switch: an ability can carry both.
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
        local btn = UI.Keep(panel, "tab", function(p)
            local b = CreateFrame("Button", nil, p)
            b.label = ns.Font(b, 12, nil, ns.THEME.muted)
            b.label:SetPoint("CENTER")
            b.marker = ns.Solid(b, "OVERLAY", ns.THEME.accent, 1)
            b.marker:SetPoint("BOTTOMLEFT", 0, -3)
            b.marker:SetPoint("BOTTOMRIGHT", 0, -3)
            b.marker:SetHeight(2)
            return b
        end)
        btn.label:SetText(text)
        btn.label:SetTextColor(ns.THEME.muted.r, ns.THEME.muted.g, ns.THEME.muted.b, 1)
        btn:SetSize(btn.label:GetStringWidth() + 4, 22)
        if anchorTo then btn:SetPoint("LEFT", anchorTo, "RIGHT", 18, 0)
        else btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP) end
        btn.marker:Hide()
        btn:SetScript("OnClick", function() SelectPageTab(id) end)
        tabBtns[id] = btn
        return btn
    end
    local defTabBtn = AddPageTab("defensive", "Cooldown Preset")
    AddPageTab("custom", "Ability Reminder", defTabBtn)
    defTabBtn.marker:Show()
    defTabBtn.label:SetTextColor(ns.THEME.fg.r, ns.THEME.fg.g, ns.THEME.fg.b, 1)

    RebuildBody = function()
        UI.BeginReusableRows(body)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP - 30)
        body:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, TAB_TOP - 30)
        -- A frame anchored on only its top edge never resolves a height on its own.
        body:SetHeight(480)

        -- Wrapped so a throw shows an error instead of a silent blank panel.
        local ok, err = pcall(function()
        local by = 0

        -- One-column helpers: W:DualRow always reserves a right half this popup cannot spare.
        local function Label(text)
            local lbl = UI.KeepFont(body, "label", 11, nil, ns.THEME.muted)
            lbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            lbl:SetText(text)
            by = by - 16
        end
        local FIELD_W = 260
        local function DropdownRow(values, order, getValue, setValue)
            local ddBtn = UI.KeepDropdown(body, "dropdown", FIELD_W, values, order,
                getValue, setValue)
            ddBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            by = by - 32
            return ddBtn
        end

        if pageTab == "defensive" then
            local presets = ns.ListPresets(specID)
            if #presets == 0 then
                local hint = UI.KeepFont(body, "noPresets", 11, nil, ns.THEME.muted)
                hint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                hint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                hint:SetWordWrap(true)
                hint:SetText(ns.Color("muted", "No presets yet -- add one on the Setup page "
                    .. "first."))
                by = by - 34
            else
                local presetValues, presetOrder = {}, {}
                for i = 1, #presets do
                    presetValues[presets[i].key] = presets[i].name
                    presetOrder[i] = presets[i].key
                end
                -- First build only: binding.preset keeps the old value until Save, and
                -- re-reading it on a rebuild left the dropdown stuck on the old preset.
                if presetVal == nil then
                    presetVal = binding.preset or ns.BossPresetKey(specID, encounterID)
                        or ns.ActivePresetKey(specID) or presetOrder[1]
                end
                Label("Cooldown Preset")
                DropdownRow(presetValues, presetOrder,
                    function() return presetVal end,
                    function(v) presetVal = v end)
            end

            local note = UI.KeepFont(body, "note", 10, nil, ns.THEME.muted)
            note:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            note:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            note:SetJustifyH("LEFT")
            note:SetWordWrap(true)
            note:SetText("Calls out the highest defensive on that preset still ready "
                .. "when this ability is cast.")
            by = by - 30

            if leadTimeVal == nil then
                leadTimeVal = binding.leadTime or (ns.DB().leadTime or 3)
            end
            Label("Warning Time (+before / -after impact)")
            -- Negative calls after impact (ScheduleBWFire handles the sign); the spec-wide
            -- default on the Setup page stays positive-only.
            local trackFrame, valBox = UI.KeepSlider(body, "lead", 200, 4, 12, 40, 22, 12,
                1, -30, 10, 1,
                function() return leadTimeVal end,
                function(v) leadTimeVal = v end)
            trackFrame:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            valBox:SetPoint("LEFT", trackFrame, "RIGHT", 10, 0)
            by = by - 32

            local leadHint = UI.KeepFont(body, "leadHint", 10, nil, ns.THEME.muted)
            leadHint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            leadHint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            leadHint:SetJustifyH("LEFT")
            leadHint:SetWordWrap(true)
            leadHint:SetText("Positive calls out before the hit lands, as usual. Negative "
                .. "waits until that many seconds AFTER it lands instead -- for a defensive "
                .. "that only matters once the mechanic is over.")
            by = by - math.ceil(leadHint:GetStringHeight()) - 16

            if externalVal == nil then
                externalVal = ns.ExternalCallFor(encounterID, ability.spellID)
            end
            Label("|cff6DD09AHealer|r Reminder")
            local healerCheck = UI.KeepToggle(body, "healer",
                function() return healerVal end,
                function(v) healerVal = v and true or false end)
            healerCheck:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            ns.Tooltip(healerCheck, "Healer Reminder",
                "Mark this preset callout for the healer-reminder switch. General defensive callouts should stay unmarked.")
            by = by - 38

            Label("Call for an External when nothing of yours is up")
            local extHint = UI.KeepFont(body, "extHint", 10, nil, ns.THEME.muted)
            extHint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            extHint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            extHint:SetJustifyH("LEFT")
            extHint:SetWordWrap(true)
            extHint:SetText("Off means this ability stays silent when your list is empty, "
                .. "instead of asking the raid for help on a hit nobody was going to answer. "
                .. "Untouched, it follows the spec-wide setting on the Setup page.")
            by = by - math.ceil(extHint:GetStringHeight()) - 10

            local extCheck = UI.KeepToggle(body, "external",
                function() return externalVal end,
                function(v) externalVal = v and true or false end)
            extCheck:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
            by = by - 26

        else
            local hint = UI.KeepFont(body, "customHint", 11, nil, ns.THEME.muted)
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
                local nameLbl = UI.KeepFont(body, "name", 12, nil, ns.THEME.fg)
                nameLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                nameLbl:SetText(entry.name or "Reminder")
                by = by - 18

                local descLbl = UI.KeepFont(body, "desc", 11, nil, ns.THEME.muted)
                descLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                descLbl:SetText(RaidReminderTargetDesc(entry.target) .. "  -- "
                    .. (RR_DISPLAY_VALUES[entry.display and entry.display.type] or "Message"))
                by = by - 30

                local editBtn = UI.KeepButton(body, "edit", "Edit", 100, 26, function()
                    local nestedDimmer = ns.ShowRaidReminderEditor(
                        encounterID, uid, EUI, nil, ability.spellID)
                    if nestedDimmer then nestedDimmer.onClose = RebuildBody end
                end)
                editBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                local removeBtn = UI.KeepButton(body, "remove", "Remove", 100, 26, function()
                    local writeSet = ns.RaidRemindersTable(false, encounterID)
                    if writeSet then writeSet[uid] = nil end
                    RebuildBody()
                end)
                removeBtn:SetPoint("LEFT", editBtn, "RIGHT", 10, 0)
                by = by - 32
            else
                local noneLbl = UI.KeepFont(body, "none", 11, nil, ns.THEME.muted)
                noneLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                noneLbl:SetText("None yet for this ability.")
                by = by - 26

                local addBtn = UI.KeepButton(body, "add", "+ Add a Ability Reminder", 200, 26, function()
                    local nestedDimmer = ns.ShowRaidReminderEditor(
                        encounterID, nil, EUI, nil, ability.spellID)
                    if nestedDimmer then nestedDimmer.onClose = RebuildBody end
                end)
                addBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, by)
                by = by - 32
            end
        end
        end)
        if not ok then
            local errText = UI.KeepFont(body, "error", 11, nil, { r = 1, g = 0.35, b = 0.35 })
            errText:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
            errText:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            errText:SetJustifyH("LEFT")
            errText:SetWordWrap(true)
            errText:SetText("Failed to build this panel: " .. tostring(err))
            ns.Print("|cffff6060ability reminder picker|r: " .. tostring(err))
        end
    end

    RebuildBody()

    -- The Ability Reminder tab saves through its own nested editor.
    local function Save()
        -- Heals a stale "custom" mode from older builds, which HandleBigWigsAbility
        -- would otherwise read as suppressing the preset pick.
        binding.mode = "defensive"
        binding.preset = presetVal
        -- leadTimeBySpell is a dropped older field, cleared on save.
        binding.leadTimeBySpell = nil
        binding.leadTime = (leadTimeVal ~= (ns.DB().leadTime or 3)) and leadTimeVal or nil
        -- nil when it agrees with the spec-wide toggle, so it keeps following that toggle.
        if externalVal == nil or externalVal == (ns.DB().fallbackOn ~= false) then
            binding.external = nil
        else
            binding.external = externalVal
        end
        binding.scope = scopeVal
        binding.healerReminder = healerVal or nil
        ns.ApplyReminderFilter()
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end

    -- Outside the tabs: the scope belongs to the binding.
    local scopeText = UI.KeepFont(panel, "scope", 10, nil, ns.THEME.muted)
    scopeText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, 52)
    scopeText:SetPoint("RIGHT", panel, "RIGHT", -PAD - 76, 0)
    scopeText:SetJustifyH("LEFT")
    scopeText:SetWordWrap(false)
    local function RefreshScopeText()
        scopeText:SetText("Loads for: " .. ns.DescribeBindingScope(scopeVal))
    end
    RefreshScopeText()

    UI.KeepButton(panel, "change", "Change", 70, 22, function()
        ns.ShowBindingScopePicker(scopeVal, function(newScope)
            scopeVal = newScope
            RefreshScopeText()
        end)
    end):SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 48)

    UI.KeepButton(panel, "save", "Save", 90, 26, Save):SetPoint("BOTTOM", panel, "BOTTOM", -50, 16)
    UI.KeepButton(panel, "cancel", "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 50, 16)

    dimmer:Show()
end

-- Fixed height: GetStringHeight right after SetText depends on the parent chain's width
-- having resolved, which caused overlaps before. Long descriptions clip instead.
local ABILITY_ROW_H = 62

local function NewAbilityRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ABILITY_ROW_H)
    row.check = UI.BuildToggleControl(row, row:GetFrameLevel() + 1,
        function() return false end, function() end)
    row.check:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -6)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 8, 6)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.cog = ns.Button(row, "...", 30, 26)
    row.cog:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)
    row.test = ns.Button(row, "Test", 44, 26)
    row.test:SetPoint("TOPRIGHT", row.cog, "TOPLEFT", -4, 0)
    row.remove = ns.Button(row, "X", 26, 26)
    row.remove:SetPoint("TOPRIGHT", row.test, "TOPLEFT", -4, 0)
    row.remove.label:SetTextColor(1, 0.38, 0.38, 1)
    ns.Tooltip(row.remove, "Remove Ability",
        "Take this ability off the boss. Its preset and warning time go with it.")
    row.title = ns.Font(row, 13, nil, ns.THEME.fg)
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.title:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
    row.title:SetJustifyH("LEFT")
    row.desc = ns.Font(row, 11, nil, ns.THEME.muted)
    row.desc:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -20)
    row.desc:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
    row.desc:SetHeight(ABILITY_ROW_H - 24)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetWordWrap(true)
    local div = ns.Solid(row, "ARTWORK", ns.THEME.line, 1)
    div:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    div:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    ns.Hairline(div, "h")
    return row
end

local function RenderAbilityRow(parent, y, encounterID, ability, specID, EUI)
    local row = UI.Keep(parent, "abilityRow", NewAbilityRow)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    -- Unticking silences the ability but keeps its settings; the X removes it.
    local enabled = ability.spellID and ns.AbilityEnabledForBinding(encounterID, ability.spellID, true)

    row.check._get = function() return enabled end
    row.check._set = function(v)
        if not ability.spellID then return end
        enabled = v and true or false
        ns.EnsureBinding(encounterID, ability.spellID).enabled = enabled
        ns.RefreshRuntime()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end
    row.check._refreshValue()

    row.icon:SetTexture(ability.icon)

    row.cog._onClick = function()
        if not ability.spellID then
            ns.Print("|cffff6060this journal entry has no spell id to bind to|r")
            return
        end
        ns.ShowAbilityReminderPicker(encounterID, ability, EUI)
    end

    row.test._onClick = function()
        if not ability.spellID then
            ns.Print("|cffff6060this journal entry has no spell id to bind to|r")
            return
        end
        ns.TestFireAbility(encounterID, ability.spellID)
    end

    row.remove._onClick = function()
        ns.ConfirmRemoveAbility(encounterID, ability, EUI)
    end

    -- Roles go on the title; other flags fold into the description, not a second row.
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

    local binding = ability.spellID and ns.BindingForBossModKey(encounterID, ability.spellID)
    local healerTag = binding and binding.healerReminder and "  |cff6DD09A[Healer Reminder]|r" or ""
    row.title:SetText((ability.title or "?") .. (roleTag and ("  " .. roleTag) or "") .. healerTag)

    local descText = ability.description or ns.Color("muted", "No description in the journal.")
    if restTag then descText = (ns.Color("muted", "[%s]") .. "  "):format(restTag) .. descText end
    row.desc:SetText(descText)

    return y - ABILITY_ROW_H
end

local function RenderBossMessageSection(parent, y, EUI, encounterID)
    local PADR = EUI.CONTENT_PAD or 16
    local function Refresh() EUI:RefreshPage(true) end
    local function Edit(uid)
        local d = ns.ShowCustomReminderEditor(encounterID, uid, EUI, "bwmsg")
        if d then d.onClose = Refresh end
    end

    local head = UI.KeepFont(parent, "bmHead", 12, nil, ns.THEME.accent)
    head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    head:SetText("BOSS REMINDERS")
    y = y - 20

    local note = UI.KeepFont(parent, "bmNote", 11, nil, ns.THEME.muted)
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    note:SetPoint("RIGHT", parent, "RIGHT", -PADR, 0)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText("Your own reminders for this boss. A reminder can start from a BigWigs or "
        .. "DBM message, or from the boss beginning or finishing a cast -- pick which in the "
        .. "editor. A message trigger needs Messages enabled for that ability in BigWigs. "
        .. "Bars keep using the ability's own preset and warning time, so both can run "
        .. "together. Test previews the saved output immediately, without waiting.")
    note:SetHeight(math.max(16, note:GetStringHeight() + 4))
    y = y - note:GetHeight() - 8

    local set = ns.CustomRemindersTable and ns.CustomRemindersTable(false, encounterID)
    local list = {}
    if set then
        for uid, r in pairs(set) do
            if r.trigger and (r.trigger.type == "bwmsg" or r.defensive)
                and (not r.specID or r.specID == ns.CurrentSpec()) then
                list[#list + 1] = { uid = uid, r = r }
            end
        end
        table.sort(list, function(a, b) return (a.r.name or "") < (b.r.name or "") end)
    end

    if #list == 0 then
        local none = UI.KeepFont(parent, "bmNone", 11, nil, ns.THEME.muted)
        none:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        none:SetText("None yet for this boss.")
        y = y - 20
    else
        for i = 1, #list do
            local uid, r = list[i].uid, list[i].r
            local row = UI.Keep(parent, "bmRow", function(host)
                local f = CreateFrame("Frame", nil, host)
                f:SetHeight(24)
                f.check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
                f.check:SetSize(20, 20)
                f.check:SetPoint("LEFT", f, "LEFT", 0, 0)
                f.del = ns.Button(f, "Delete", 56, 22)
                f.del:SetPoint("RIGHT", f, "RIGHT", 0, 0)
                f.edit = ns.Button(f, "Edit", 46, 22)
                f.edit:SetPoint("RIGHT", f.del, "LEFT", -4, 0)
                f.test = ns.Button(f, "Test", 44, 22)
                f.test:SetPoint("RIGHT", f.edit, "LEFT", -4, 0)
                f.lbl = ns.Font(f, 11, nil, ns.THEME.fg)
                f.lbl:SetPoint("LEFT", f.check, "RIGHT", 4, 0)
                f.lbl:SetPoint("RIGHT", f.test, "LEFT", -8, 0)
                f.lbl:SetJustifyH("LEFT")
                return f
            end)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", parent, "RIGHT", -PADR, 0)

            row.check:SetChecked(r.enabled ~= false)
            row.check:SetScript("OnClick", function(self)
                r.enabled = self:GetChecked() and true or false
                ns.RefreshRuntime()
            end)
            row.del._onClick = function()
                local writeSet = ns.CustomRemindersTable(false, encounterID)
                if writeSet then writeSet[uid] = nil end
                ns.RefreshRuntime()
                Refresh()
            end
            row.edit._onClick = function() Edit(uid) end
            row.test._onClick = function()
                if r.defensive then
                    ns.TestFireAbility(encounterID, r.trigger.spellID, r)
                else
                    ns.PreviewCustomReminder(r)
                end
            end

            local delay = r.trigger.delay
            row.lbl:SetText((r.name or "Reminder") .. "  " .. ns.Color("muted", "("
                .. ((TRIGGER_CHOICES[r.trigger.type] or r.trigger.type)
                    .. (delay and (" +" .. tostring(delay) .. "s") or ""))
                .. ")"))
            y = y - 26
        end
    end
    y = y - 6

    local add = UI.KeepButton(parent, "bmAdd", "+ Add Reminder", 230, 26,
        function() Edit(nil) end)
    add:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    return y - 34
end

local function RenderInstanceDetail(parent, y, W, EUI, inst, specID)
    local boss = inst.bosses[selectedBossIdx[inst.id] or 1]

    if not boss then
        local hint = UI.KeepFont(parent, "noBoss", 12, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        hint:SetText("This instance has no bosses in the journal yet.")
        return y - 20
    end

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
    -- Read from the installed modules at runtime; a shipped GetOptions-derived list was
    -- dropped in 0824t for missing abilities.
    local abilities = BigWigsAbilities(boss.encounterID, boss.abilities, inst.mapID) or boss.abilities
    if not (abilities and #abilities > 0) then
        local hint = UI.KeepFont(parent, "noAbilities", 12, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        hint:SetText("No abilities listed in the journal for this boss.")
        return RenderBossMessageSection(parent, y - 26, EUI, boss.encounterID)
    end

    -- Only what the player has added; a boss starts blank.
    local added = {}
    for i = 1, #abilities do
        local a = abilities[i]
        if a.spellID and ns.AbilityAdded(boss.encounterID, a.spellID) then
            added[#added + 1] = a
        end
    end

    local addBtn = UI.KeepButton(parent, "addAbility", "+ Add Ability", 130, 24, function()
        ns.ShowAbilityPicker(boss.encounterID, abilities, EUI)
    end)
    addBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    local copyBtn = UI.KeepButton(parent, "copyFromSpec", "Copy From Spec", 130, 24, function()
        -- Keeps the popup's "every boss" tick on the same side of the raid/dungeon split.
        local set, word = ns.EncounterSetForKind(inst.isRaid)
        ns.ShowCopyBindingsPopup(boss.encounterID, boss.name, EUI, set, word)
    end)
    copyBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    ns.Tooltip(copyBtn, "Copy From Spec",
        "Brings another spec's abilities for this boss over to this one. Abilities are saved "
        .. "per spec, so a spec you have not set up yet starts empty. Anything already set up "
        .. "here is left alone.")
    y = y - 30

    if #added == 0 then
        local hint = UI.KeepFont(parent, "noneAdded", 12, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        hint:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        hint:SetText("No abilities picked for this boss yet. Add Ability lists everything "
            .. "the journal has for the fight, with the known tank hits marked.")
        return RenderBossMessageSection(parent, y - 40, EUI, boss.encounterID)
    end

    local lastStage
    for i = 1, #added do
        local a = added[i]
        if a.stage and a.stage ~= lastStage then
            lastStage = a.stage
            local hdr = UI.KeepFont(parent, "stage", 11, nil, ns.THEME.muted)
            hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 6)
            hdr:SetText(a.stage)
            y = y - 24
        end
        y = RenderAbilityRow(parent, y, boss.encounterID, a, specID, EUI)
    end

    return RenderBossMessageSection(parent, y - 6, EUI, boss.encounterID)
end

function ns.ConfirmRemoveAbility(encounterID, ability, callerEUI)
    local EUI = callerEUI or ns.UI
    local dimmer, panel = ns.MakeModal(400, 190, "abilityRemoveConfirm")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("Remove Ability")

    local body = UI.KeepFont(panel, "body", 12, nil, ns.THEME.fg)
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -48)
    body:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    body:SetText(("Remove " .. ns.Color("accent", "%s") .. " from this boss?"):format(ability.title or "this ability"))

    local warn = UI.KeepFont(panel, "warn", 11, nil, ns.THEME.muted)
    warn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -84)
    warn:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    warn:SetJustifyH("LEFT")
    warn:SetWordWrap(true)
    warn:SetText("Its cooldown preset and warning time go with it. Adding it back later "
        .. "starts that ability fresh.")

    local remove = UI.KeepButton(panel, "remove", "Remove", 110, 26, function()
        -- EnsureBinding migrates a journal-alias binding onto this id, so the nil removes it.
        ns.EnsureBinding(encounterID, ability.spellID)
        local set = ns.AbilityBindingsTable(false, encounterID)
        if set then set[ability.spellID] = nil end
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end)
    remove:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -6, 16)
    remove.label:SetTextColor(1, 0.38, 0.38, 1)

    local cancel = UI.KeepButton(panel, "cancel", "Cancel", 110, 26, function() dimmer:Hide() end)
    cancel:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 6, 16)

    dimmer:Show()
    return dimmer
end

function ns.BuildBossListPage(parent, y, isRaid)
    local EUI = ns.UI
    local W   = EUI.Widgets
    local _, h
    local specID, isTank = ns.CurrentSpec()

    -- Hand-built: W:SectionHeader cannot center or recolour, and its 40px band left a gap.
    local pageHead = UI.KeepFont(parent, "pageHead", 14, nil, ns.THEME.accent)
    pageHead:SetPoint("TOP", parent, "TOP", 0, y)
    pageHead:SetJustifyH("CENTER")
    pageHead:SetText(isRaid and "Raid Bosses" or "Dungeon Bosses")
    y = y - 22

    -- Raid-only: a five-man has one tank, so the gate changes nothing there. It follows
    -- the spec's role; a manual toggle could be left on after a respec and kill every callout.
    if isRaid then
        local note = UI.KeepFont(parent, "tankNote", 11, nil, ns.THEME.accentSoft)
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", EUI.CONTENT_PAD, y)
        note:SetPoint("RIGHT", parent, "RIGHT", -EUI.CONTENT_PAD, 0)
        note:SetJustifyH("LEFT")
        note:SetWordWrap(true)
        note:SetText(isTank
            and "Only While I Have the Boss: on. Stays quiet when the boss is on the "
                .. "other tank."
            or "Only While I Have the Boss: off. This spec does not tank, so calls fire "
                .. "regardless of aggro.")
        y = y - 30
    end

    -- Here rather than on Setup: it only reaches reminders authored from this page.
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Target on Boss Casts",
          tooltip = "When a boss cast you have a Boss Cast Starts reminder for names a "
          .. "player, puts that player's name on the alert in their class colour. Only "
          .. "while the cast is going out, since that is the only moment the game will say "
          .. "who is being targeted, and only for the abilities that name anybody at all.",
          getValue = function() return ns.DB().castTargetBoss == true end,
          setValue = function(v)
              ns.DB().castTargetBoss = v or nil
              -- Otherwise the cast watch would not rearm until the next pull.
              if ns.RefreshCastWatch then ns.RefreshCastWatch() end
          end }
    ); y = y - h

    local data = ns.ScrapeBosses(false)
    if not data or #data.instances == 0 then
        local why = (scrapeFailed == "busy")
            and "Close the Dungeon Journal and reopen this page."
            or "No bosses listed yet. They appear once the game publishes this season's "
                .. "Dungeon Journal data; open the Adventure Guide once, then use Refresh below."
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
    -- Matched by id: a forced rescan builds new tables, which would drop the selection.
    if sel then
        local found
        for i = 1, #list do if list[i].id == sel.id then found = list[i]; break end end
        sel = found
        selectedInst[key] = found
    end

    -- Copies are confined to this page's bosses, so Raid Bosses cannot drag dungeons along.
    local encSet, scopeWord = ns.EncounterSetForKind(isRaid)

    -- Bindings filed under another spec look like a lost profile; say which it is.
    local others = (specID and specID ~= 0 and ns.SpecsWithBindings)
        and ns.SpecsWithBindings(nil, encSet) or {}
    if specID and specID ~= 0 and ns.OwnBindingCount
        and ns.OwnBindingCount(encSet) == 0 and #others > 0 then
        local total = 0
        for i = 1, #others do total = total + (others[i].total or 0) end
        local note = UI.KeepFont(parent, "otherSpecsNote", 11, nil, ns.THEME.accentSoft)
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", EUI.CONTENT_PAD + 20, y)
        note:SetPoint("RIGHT", parent, "RIGHT", -EUI.CONTENT_PAD, 0)
        note:SetJustifyH("LEFT")
        note:SetWordWrap(true)
        note:SetText(("This profile has %d %s set up, but none of them on %s -- abilities are "
            .. "saved per spec. Copy them across below, or switch to a spec that has them.")
            :format(total, total == 1 and "ability" or "abilities",
                ns.SpecName(specID) or "this spec"))
        y = y - 30
    end

    if specID and specID ~= 0 and #others > 0 then
        -- Not W:Button: its hardcoded 200px width is too narrow for this label.
        local row = UI.Keep(parent, "copyAllRow", function(host)
            local f = CreateFrame("Frame", nil, host)
            f:SetHeight(34)
            f.btn = ns.Button(f, "", 220, 26)
            f.btn:SetPoint("LEFT", f, "LEFT", 20, 0)
            f.cap = ns.Font(f, 11, nil, ns.THEME.muted)
            f.cap:SetPoint("LEFT", f.btn, "RIGHT", 12, 0)
            f.cap:SetPoint("RIGHT", f, "RIGHT", -8, 0)
            f.cap:SetJustifyH("LEFT")
            return f
        end)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", EUI.CONTENT_PAD, y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -EUI.CONTENT_PAD, y)

        local label = isRaid and "Copy All Raids From a Spec" or "Copy All Dungeons From a Spec"
        local btn = row.btn
        ns.SetButtonText(btn, label)
        btn._onClick = function()
            ns.ShowCopyBindingsPopup(nil, nil, EUI, encSet, scopeWord)
        end
        ns.Tooltip(btn, label, ("Brings another spec's abilities across for every %s at once, "
            .. "instead of repeating the per-boss copy on each in turn. %s are left to their "
            .. "own page, and anything this spec already has is left alone."):format(
            scopeWord:lower(), isRaid and "Dungeons" or "Raids"))

        row.cap:SetText(("Sets a new spec up in one press. %s only, nothing already here is "
            .. "replaced."):format(isRaid and "Raids" or "Dungeons"))

        y = y - 40
    end

    local LEFT_W = 190
    local topY = y

    local leftHead = UI.KeepFont(parent, "leftHead", 12, nil, ns.THEME.muted)
    leftHead:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, topY)
    leftHead:SetJustifyH("LEFT")
    leftHead:SetText(isRaid and "Select a Raid" or "Select a Dungeon")
    local listTop = topY - 18

    local leftPane = UI.Keep(parent, "leftPane", function(p) return CreateFrame("Frame", nil, p) end)
    leftPane:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, listTop)
    leftPane:SetSize(LEFT_W, math.max(1, #list * 26))

    for i = 1, #list do
        local inst = list[i]
        local row = UI.Keep(leftPane, "instance", function(host)
            local b = CreateFrame("Button", nil, host)
            b:SetSize(LEFT_W, 26)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.lbl = ns.Font(b, 12, nil, ns.THEME.muted)
            b.lbl:SetPoint("LEFT", b, "LEFT", 6, 0)
            b.lbl:SetPoint("RIGHT", b, "RIGHT", -6, 0)
            b.lbl:SetJustifyH("LEFT")
            return b
        end)
        row:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -(i - 1) * 26)

        local isSel = (sel == inst)
        local a, c = ns.THEME.accent, isSel and ns.THEME.fg or ns.THEME.muted
        row.bg:SetColorTexture(a.r, a.g, a.b, isSel and 0.16 or 0)
        row.lbl:SetTextColor(c.r, c.g, c.b, 1)
        row.lbl:SetText(inst.name)

        row:SetScript("OnClick", function()
            selectedInst[key] = inst
            EUI:RefreshPage(true)
        end)
    end

    -- Inset by CONTENT_PAD, or the row cogs sit under the scrollbar and cannot be clicked.
    local rightPane = UI.Keep(parent, "rightPane", function(p) return CreateFrame("Frame", nil, p) end)
    rightPane:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_W + 16, topY)
    rightPane:SetPoint("RIGHT", parent, "RIGHT", -(EUI.CONTENT_PAD or 16), 0)

    local rightBottom
    if sel then
        rightBottom = RenderInstanceDetail(rightPane, 0, W, EUI, sel, specID)
    else
        rightBottom = 0
    end

    local leftBottom = listTop - (#list * 26)
    return math.min(leftBottom, topY + rightBottom)
end

-- Encounter keys on one side of the raid/dungeon split; both copy entry points confine
-- themselves to it.
function ns.EncounterSetForKind(isRaid)
    local data = ns.ScrapeBosses(false)
    local set = {}
    if not data then return set, isRaid and "Raid Boss" or "Dungeon Boss" end
    for i = 1, #data.instances do
        local inst = data.instances[i]
        if (inst.isRaid or false) == (isRaid and true or false) then
            for j = 1, #inst.bosses do
                local eid = inst.bosses[j].encounterID
                if eid then set[tostring(eid)] = true end
            end
        end
    end
    return set, isRaid and "Raid Boss" or "Dungeon Boss"
end

-- Additive copy of another spec's bindings. encounterID nil copies the whole spec.
function ns.ShowCopyBindingsPopup(encounterID, bossName, callerEUI, encSet, scopeWord)
    local EUI = callerEUI or ns.UI
    local specs = ns.SpecsWithBindings(encounterID, encSet)
    local allMode = (encounterID == nil)

    local dimmer, panel = ns.MakeModal(420, 150 + math.max(1, #specs) * 30, "copyBindings")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText(allMode
        and ("Copy Every %s From"):format(scopeWord or "Boss")
        or "Copy Abilities From")

    local y = -46
    if #specs == 0 then
        local none = UI.KeepFont(panel, "none", 12, nil, ns.THEME.muted)
        none:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
        none:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
        none:SetJustifyH("LEFT")
        none:SetWordWrap(true)
        none:SetText("No other spec has any abilities saved yet.")
    else
        local hint = UI.KeepFont(panel, "hint", 11, nil, ns.THEME.muted)
        hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
        hint:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        hint:SetText(allMode
            and ("Every %s that spec has set up is copied, and nothing outside them. "
                .. "Anything this spec already has is left alone."):format(
                (scopeWord or "boss"):lower())
            or "Anything this spec already has is left alone.")
        y = y - (allMode and 38 or 26)

        local allBosses = allMode
        if not allMode then
            local chk = UI.Keep(panel, "allBosses", function(p)
                local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
                c:SetSize(20, 20)
                return c
            end)
            chk:SetChecked(false)
            chk:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
            chk:SetScript("OnClick", function(self) allBosses = self:GetChecked() and true or false end)
            local chkLbl = UI.KeepFont(panel, "allBossesLabel", 11, nil, ns.THEME.fg)
            chkLbl:SetPoint("LEFT", chk, "RIGHT", 4, 0)
            chkLbl:SetText(("Every %s, not just %s"):format(
                (scopeWord or "boss"):lower(), bossName or "this one"))
            y = y - 28
        end

        for i = 1, #specs do
            local s = specs[i]
            local label = allMode and ("%s  (%d)"):format(s.name, s.total) or s.name
            local btn = UI.KeepButton(panel, "spec", label, 200, 24, function()
                local copied, skipped, reminders = ns.CopyBindingsFromSpec(
                    s.key, (not allBosses) and encounterID or nil, encSet)
                ns.Print(("copied " .. ns.Color("accent", "%d") .. " abilities%s from %s%s.")
                    :format(copied,
                        reminders > 0 and (" and " .. ns.Color("accent", reminders) .. " message reminders") or "",
                        s.name,
                        skipped > 0 and (", left " .. skipped .. " already here alone") or ""))
                ns.RefreshRuntime()
                dimmer:Hide()
                if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
            end)
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
            local count = UI.KeepFont(panel, "count", 11, nil, ns.THEME.muted)
            count:SetPoint("LEFT", btn, "RIGHT", 10, 0)
            count:SetText(("%d here, %d total"):format(s.here, s.total))
            y = y - 30
        end
    end

    UI.KeepButton(panel, "cancel", "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)
    dimmer:Show()
end

-- The curated tank list marks rows here instead of pre-selecting them.
function ns.ShowAbilityPicker(encounterID, abilities, callerEUI)
    local EUI = callerEUI or ns.UI
    local PANEL_W = 460
    local dimmer, panel = ns.MakeModal(PANEL_W, 560, "abilityPicker")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText("Add Abilities")

    local hint = UI.KeepFont(panel, "hint", 11, nil, ns.THEME.muted)
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -42)
    hint:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("Tick the abilities you want reminders for. Marked ones are what the "
        .. "addon knows to be tank hits on this boss. Unticking one drops it from the "
        .. "boss, along with any warning time or reminder set up on it.")

    local scroll = UI.Keep(panel, "scroll", function(p)
        local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        sf.content = CreateFrame("Frame", nil, sf)
        -- Sized off the panel, not scroll:GetWidth(): the scroll frame is anchor-derived and
        -- still reads 0 wide until a layout pass has run.
        sf.content:SetSize(PANEL_W - 62, 1)
        sf:SetScrollChild(sf.content)
        return sf
    end)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -82)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -40, 54)
    scroll:SetVerticalScroll(0)
    local content = scroll.content
    UI.BeginReusableRows(content)

    local ok, err = pcall(function()
        local y, shown = 0, 0
        for i = 1, #abilities do
            local a = abilities[i]
            if a.spellID then
                shown = shown + 1
                local row = UI.Keep(content, "row", function(parent)
                    local r = CreateFrame("Frame", nil, parent)
                    r:SetHeight(26)
                    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
                    r.check:SetSize(22, 22)
                    r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
                    r.icon = r:CreateTexture(nil, "ARTWORK")
                    r.icon:SetSize(20, 20)
                    r.icon:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
                    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    r.lbl = ns.Font(r, 11, nil, ns.THEME.fg)
                    r.lbl:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                    r.lbl:SetPoint("RIGHT", r, "RIGHT", 0, 0)
                    r.lbl:SetJustifyH("LEFT")
                    r.lbl:SetWordWrap(false)
                    return r
                end)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

                -- Two-way, read from the box's own state: assuming the click meant "add"
                -- once made unticking silently re-add the ability.
                local check = row.check
                check:SetChecked(ns.AbilityAdded(encounterID, a.spellID))
                check:SetScript("OnClick", function(self)
                    if self:GetChecked() then
                        ns.EnsureBinding(encounterID, a.spellID).enabled = true
                    else
                        ns.RemoveBinding(encounterID, a.spellID)
                    end
                    ns.RefreshRuntime()
                    if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
                end)

                row.icon:SetTexture(a.icon)

                local curated = ns.TANK_ABILITIES and ns.TANK_ABILITIES[a.spellID]
                local roleTag
                if a.extras then
                    local roles = {}
                    for label in a.extras:gmatch("[^,]+") do
                        label = label:match("^%s*(.-)%s*$")
                        if ROLE_COLOR[label] then
                            roles[#roles + 1] = ROLE_COLOR[label] .. label .. "|r"
                        end
                    end
                    if #roles > 0 then roleTag = table.concat(roles, " ") end
                end
                row.lbl:SetText((a.title or ("Spell " .. a.spellID))
                    .. (roleTag and ("  " .. roleTag) or "")
                    .. (curated and ("  " .. ns.Color("accent", "[tank hit]")) or ""))

                y = y - 28
            end
        end
        if shown == 0 then
            local none = UI.KeepFont(content, "none", 11, nil, ns.THEME.muted)
            none:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            none:SetText("Nothing in the journal for this boss carries a spell id.")
        end
        content:SetHeight(math.max(1, math.abs(y)))
    end)
    if not ok then
        local errText = UI.KeepFont(content, "error", 11, nil, { r = 1, g = 0.35, b = 0.35 })
        errText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        errText:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        errText:SetJustifyH("LEFT")
        errText:SetWordWrap(true)
        errText:SetText("Failed to build this: " .. tostring(err))
        ns.Print("|cffff6060ability add picker|r: " .. tostring(err))
    end

    UI.KeepButton(panel, "close", "Close", 100, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)
    dimmer:Show()
    return dimmer
end

-------------------------------------------------------------------------------
--  Boss-wide reminder lists, authoring UI over NaowhForever_RaidReminders.lua.
--  Ability-bound reminders (r.abilitySpellID set) live on their ability's cog instead.
-------------------------------------------------------------------------------
-- Per encounter, unsaved: a viewing choice, not a setting.
local observedDiffPick = {}

-- Each observed occurrence is a time chip that opens the editor pointed at that moment.
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

    -- Renders in both the 480px modal and the wide options tab, so chips are capped to fit.
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
                -- Later-phase pull-relative times only hold for a pull of the same speed.
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
                if d then d.onClose = onChanged end
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

-- Shared by the cog picker modal and the Custom Reminders tab. Returns the final y;
-- opts.onChanged becomes each nested editor's onClose.
function ns.BuildBossReminderSections(content, encounterID, isRaid, startY, opts)
    local EUI = (opts and opts.EUI) or ns.UI
    local onChanged = (opts and opts.onChanged) or function() end

    local function EditRaidReminder(uid)
        local nestedDimmer = ns.ShowRaidReminderEditor(encounterID, uid, EUI, isRaid)
        if nestedDimmer then nestedDimmer.onClose = onChanged end
    end
    local function EditCustomReminder(uid)
        local nestedDimmer = ns.ShowCustomReminderEditor(encounterID, uid, EUI)
        if nestedDimmer then nestedDimmer.onClose = onChanged end
    end

    -- "Any Combat" bucket: observed timings and raid reminders both need an encounter.
    local anyCombat = (encounterID == 0)

    local y = startY or 0

    -- Hand-rolled rows: W:SectionHeader/W:DualRow are built for a full-width page.
    local function Header(text)
        local lbl = ns.Font(content, 12, nil, ns.THEME.accent)
        lbl:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        lbl:SetText(text)
        y = y - 20
    end

    local function NoneRow()
        local lbl = ns.Font(content, 11, nil, ns.THEME.muted)
        lbl:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        lbl:SetText(anyCombat and "None yet." or "None yet for this boss.")
        y = y - 20
    end

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
        lbl:SetText(name .. "  " .. ns.Color("muted", "(" .. desc .. ")"))

        y = y - 26
    end

    if not anyCombat then
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
                -- Difficulties cast on different schedules and are never merged.
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
            local src = ns.BossSource and ns.BossSource() or "timeline"
            local why = ns.Font(content, 11, nil, ns.THEME.muted)
            why:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            why:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            why:SetJustifyH("LEFT")
            why:SetWordWrap(true)
            if src ~= "bigwigs" and src ~= "dbm" then
                if not (_G.BigWigsLoader or _G.DBM) then
                    why:SetText("Recording rides BigWigs or DBM broadcasts and neither is "
                        .. "installed. With one of them running, every boss you pull records "
                        .. "itself here -- there is nothing to switch on.")
                else
                    why:SetText("Boss Addon is set to Blizzard Timeline, which keeps ability "
                        .. "identity secret, so there is nothing to record from. Switch it to "
                        .. "BigWigs or DBM on the Smart Reminders > Setup tab.")
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
                -- WoW hides script errors by default, so a throw would look like a dead button.
                local okClick, clickErr = pcall(EditRaidReminder, nil)
                if not okClick then
                    ns.Print("|cffff6060could not open the raid reminder editor|r: "
                        .. tostring(clickErr))
                end
            end)
        addRRBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        y = y - 34
    end

    -- "spell" entries belong to the ability picker; deleting one here would leave its
    -- binding on "custom" and the ability unable to fire either callout.
    Header("ABILITY REMINDERS")
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
            elseif trig and trig.type == "combat" then
                trigDesc = trig.delay and ("In Combat +" .. tostring(trig.delay) .. "s")
                    or "In Combat"
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
            elseif trig and (trig.type == "caststart" or trig.type == "castend") then
                local info = C_Spell and C_Spell.GetSpellInfo
                    and C_Spell.GetSpellInfo(trig.spellID)
                trigDesc = (trig.type == "castend" and "Cast Finishes: " or "Cast Starts: ")
                    .. ((info and info.name) or tostring(trig.spellID))
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

    local addCRBtn = ns.Button(content,
        anyCombat and "+ Add Reminder" or "+ Add an Ability Reminder",
        anyCombat and 230 or 190, 26, function()
            EditCustomReminder(nil)
        end)
    addCRBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - 34

    return y
end


-- abilitySpellID binds a new entry to that ability and seeds the Spell ID field; the
-- BigWigs key can still differ from the journal spellID, so it stays editable.
-- seed (optional): { trigger = {...}, name = "..." } for a new entry; ignored when editing.
function ns.ShowRaidReminderEditor(encounterID, uid, callerEUI, isRaid, abilitySpellID, seed)
    local EUI = callerEUI or ns.UI
    local W = EUI.Widgets
    local kind = isRaid and "Raid" or "Dungeon"

    -- Tall because none of the tab bodies scroll.
    local dimmer, panel = ns.MakeModal(480, 860, "raidReminderEditor")

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", panel, "TOP", 0, -16)
    head:SetText((uid and "Edit " or "New ")
        .. (abilitySpellID and "Ability Reminder" or (kind .. " Reminder")))

    local set = ns.RaidRemindersTable and ns.RaidRemindersTable(false, encounterID)
    local existing = (set and uid) and set[uid] or nil
    local boundAbilitySpellID = (existing and existing.abilitySpellID) or abilitySpellID
    local trig = (existing and existing.trigger) or (seed and seed.trigger) or { type = "bwtimer" }
    -- Editor starting state only; a saved reminder with no target still means everyone.
    local target = (existing and existing.target) or { all = false }
    local display = (existing and existing.display) or { type = "text" }

    local PAD = 20

    -- A kept box can still carry another field's text handler, which SetText would fire.
    local function KeptBox(parent)
        local box = UI.Keep(parent, "box", ns.NewEditBox)
        box:SetScript("OnTextChanged", nil)
        box:SetScript("OnEnterPressed", nil)
        return box
    end

    -- Wrapped so a throw shows an error instead of a silent blank panel.
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
    --  Tabs
    -------------------------------------------------------------------------
    local TAB_TOP = -40
    local BODY_TOP = TAB_TOP - 30

    local tabBar = UI.Keep(panel, "tabBar", function(p) return CreateFrame("Frame", nil, p) end)
    tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TAB_TOP)
    -- With one anchor and no width, the tab buttons' geometry never resolved (nil GetLeft).
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, TAB_TOP)
    tabBar:SetHeight(24)

    local tabDivider = UI.Keep(panel, "tabDivider", function(p) return ns.Solid(p, "ARTWORK", ns.THEME.line, 1) end)
    tabDivider:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, BODY_TOP + 6)
    tabDivider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, BODY_TOP + 6)
    ns.Hairline(tabDivider, "h")

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
        local btn = UI.Keep(tabBar, "tab", function(parent)
            local b = CreateFrame("Button", nil, parent)
            b.label = ns.Font(b, 12, nil, ns.THEME.muted)
            b.label:SetPoint("CENTER")
            b.marker = ns.Solid(b, "OVERLAY", ns.THEME.accent, 1)
            b.marker:SetPoint("BOTTOMLEFT", 0, -3)
            b.marker:SetPoint("BOTTOMRIGHT", 0, -3)
            b.marker:SetHeight(2)
            return b
        end)
        btn.label:SetText(text)
        btn:SetSize(btn.label:GetStringWidth() + 4, 24)
        if anchorTo then btn:SetPoint("LEFT", anchorTo, "RIGHT", 18, 0)
        else btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0) end
        btn.marker:Hide()
        btn:SetScript("OnClick", function() SelectTab(id) end)
        tabButtons[id] = btn

        local body = UI.Keep(panel, "tabBody", function(p) return CreateFrame("Frame", nil, p) end)
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
        local l = UI.KeepFont(triggerBody, "label", 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, ty)
        l:SetText(text)
        if tooltip then
            local hit = UI.Keep(triggerBody, "labelHit", function(p) return CreateFrame("Frame", nil, p) end)
            hit:SetPoint("TOPLEFT", l, "TOPLEFT", -4, 4)
            hit:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 4, -4)
            HoverTip(hit, tooltip)
        end
        ty = ty - 16
    end
    local function TBox(maxLetters, numeric, rightInset)
        local box = KeptBox(triggerBody)
        box:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, ty)
        box:SetPoint("RIGHT", triggerBody, "RIGHT", -(rightInset or PAD), 0)
        box:SetHeight(26)
        box:SetMaxLetters(maxLetters or 60)
        box:SetNumeric(numeric == true)
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

    -- Every boss-mod key seen live for this boss (RecordBossModKey), most frequent first.
    local MECHANIC_ROWS = 6
    local pickerRows = {}
    for i = 1, MECHANIC_ROWS do
        local row = UI.Keep(triggerBody, "mechanicRow", function(parent)
            local r = CreateFrame("Button", nil, parent)
            r:SetHeight(22)
            r.hl = ns.Solid(r, "BACKGROUND", ns.THEME.accent, 0.14)
            r.hl:SetAllPoints()
            r:SetScript("OnEnter", function(s) s.hl:Show() end)
            r:SetScript("OnLeave", function(s) s.hl:Hide() end)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16)
            r.icon:SetPoint("LEFT", 2, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.name = ns.Font(r, 11, nil, ns.THEME.fg)
            r.name:SetPoint("LEFT", 22, 0)
            r.name:SetPoint("RIGHT", -34, 0)
            r.name:SetJustifyH("LEFT")
            r.tag = ns.Font(r, 9, nil, ns.THEME.muted)
            r.tag:SetPoint("RIGHT", -2, 0)
            return r
        end)
        row:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, 0)
        row:SetPoint("RIGHT", triggerBody, "RIGHT", -PAD, 0)
        row.hl:Hide()
        row:Hide()
        pickerRows[i] = row
    end
    local pickerHint = UI.KeepFont(triggerBody, "pickerHint", 10, nil, ns.THEME.muted)
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

    local RebuildTriggerFields

    local function RebuildPicker()
        for i = 1, MECHANIC_ROWS do pickerRows[i]:Hide() end
        pickerHint:SetText("")
        local cat = ns.BossModCatalogueTable and ns.BossModCatalogueTable(false, encounterID)
        local list = {}
        if cat then
            -- BigWigs only: raid reminder triggers are BigWigs Message/Timer.
            for key, entry in pairs(cat) do
                if entry.mod ~= "DBM" then list[#list + 1] = { key = key, entry = entry } end
            end
        end
        table.sort(list, function(a, b) return (a.entry.seen or 0) > (b.entry.seen or 0) end)

        if #list == 0 then
            pickerHint:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", PAD, PICKER_TOP)
            pickerHint:SetText(ns.Color("muted", "Nothing recorded for this boss yet -- pull it with "
                .. "BigWigs running, or type a Spell ID below."))
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
            pickerHint:SetText((ns.Color("muted", "+%d more not shown -- type the Spell ID below."))
                :format(#list - shown))
            pickerHint:SetHeight(16)
            return shown * PICKER_ROW_H + 20
        end
        pickerHint:SetHeight(4)
        return shown * PICKER_ROW_H + 4
    end

    local typeHost = UI.Keep(triggerBody, "typeHost", function(p) return CreateFrame("Frame", nil, p) end)
    local dynFrame = UI.Keep(triggerBody, "dynFrame", function(p) return CreateFrame("Frame", nil, p) end)
    local spellBox, leadTimeBox, pullDelayBox

    -- RebuildTriggerFields re-anchors the Target section, since trigger fields change height.
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
    local targetSection = UI.Keep(triggerBody, "targetSection", function(p) return CreateFrame("Frame", nil, p) end)
    local RebuildTargetSection

    RebuildTriggerFields = function()
        -- RebuildPicker returns a positive height; adding it once threw the fields above
        -- the picker. No picker for pull/aura, which are not boss-mod mechanics.
        if trigTypeVal == "pull" or trigTypeVal == "aura" then
            for i = 1, MECHANIC_ROWS do pickerRows[i]:Hide() end
            pickerHint:SetText("")
            ty = PICKER_TOP
        else
            ty = PICKER_TOP - RebuildPicker()
        end
        UI.BeginReusableRows(typeHost)
        typeHost:ClearAllPoints()
        typeHost:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", 0, ty)
        typeHost:SetPoint("RIGHT", triggerBody, "RIGHT", 0, 0)
        typeHost:SetHeight(1)

        local auraOK = trigTypeVal == "aura"
            or (C_CombatLog and C_CombatLog.GetCurrentEventInfo) ~= nil
        local _, typeRowH = W:DualRow(typeHost, 0,
            { type = "dropdown", text = "Trigger Type",
              values = { bwmsg = "BigWigs Message", bwtimer = "BigWigs Timer",
                  pull = "Time After Pull", aura = "Gain/Lose a Buff or Debuff",
                  stage = "Phase Start" },
              order = auraOK and { "bwmsg", "bwtimer", "pull", "aura", "stage" }
                  or { "bwmsg", "bwtimer", "pull", "stage" },
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

        UI.BeginReusableRows(dynFrame)
        dynFrame:ClearAllPoints()
        dynFrame:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", 0, ty)
        dynFrame:SetSize(440, 120)
        local dy = 0
        local function DLabel(text)
            local l = UI.KeepFont(dynFrame, "label", 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", dynFrame, "TOPLEFT", PAD, dy)
            l:SetText(text)
            dy = dy - 16
        end
        local function DBox(maxLetters, numeric, rightInset)
            local box = KeptBox(dynFrame)
            box:SetPoint("TOPLEFT", dynFrame, "TOPLEFT", PAD, dy)
            box:SetPoint("RIGHT", dynFrame, "RIGHT", -(rightInset or PAD), 0)
            box:SetHeight(26)
            box:SetMaxLetters(maxLetters or 60)
            box:SetNumeric(numeric == true)
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
            local okBtn = UI.KeepButton(dynFrame, "ok", "OK", 54, 26, function() spellBox:ClearFocus() end)
            okBtn:SetPoint("LEFT", spellBox, "RIGHT", 6, 0)
            local feedback = UI.KeepFont(dynFrame, "feedback", 10, nil, ns.THEME.muted)
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
            local okBtn = UI.KeepButton(dynFrame, "ok", "OK", 54, 26, function() spellBox:ClearFocus() end)
            okBtn:SetPoint("LEFT", spellBox, "RIGHT", 6, 0)
            local feedback = UI.KeepFont(dynFrame, "feedback", 10, nil, ns.THEME.muted)
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
                    feedback:SetText(ns.Color("muted", "no spell name found -- boss-mod keys aren't "
                        .. "always real spell ids, that's fine"))
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

        -- Carries dynFrame's height into ty, or the Target section overlaps it.
        ty = ty + dy
        RebuildTargetSection()
    end

    RebuildTargetSection = function()
        UI.BeginReusableRows(targetSection)
        targetSection:ClearAllPoints()
        targetSection:SetPoint("TOPLEFT", triggerBody, "TOPLEFT", 0, ty - 10)
        targetSection:SetPoint("RIGHT", triggerBody, "RIGHT", 0, 0)

        local tgy = 0
        local function TargetLabel(text)
            local l = UI.KeepFont(targetSection, "label", 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", targetSection, "TOPLEFT", PAD, tgy)
            l:SetText(text)
            tgy = tgy - 16
        end
        TargetLabel("Target")

        local allCheck = UI.Keep(targetSection, "allCheck", function(parent)
            local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            c:SetSize(20, 20)
            return c
        end)
        allCheck:SetPoint("TOPLEFT", targetSection, "TOPLEFT", PAD, tgy)
        allCheck:SetChecked(targetAllVal)
        local allLbl = UI.KeepFont(targetSection, "allLabel", 11, nil, ns.THEME.fg)
        allLbl:SetPoint("LEFT", allCheck, "RIGHT", 4, 0)
        allLbl:SetText("Everyone")
        tgy = tgy - 28

        local restFrame = UI.Keep(targetSection, "rest", function(p) return CreateFrame("Frame", nil, p) end)
        restFrame:SetPoint("TOPLEFT", targetSection, "TOPLEFT", 0, tgy)
        restFrame:SetPoint("RIGHT", targetSection, "RIGHT", 0, 0)

        local ry = 0
        local function RestLabel(text)
            local l = UI.KeepFont(restFrame, "label", 11, nil, ns.THEME.muted)
            l:SetPoint("TOPLEFT", restFrame, "TOPLEFT", PAD, ry)
            l:SetText(text)
            ry = ry - 16
        end
        local function CheckGrid(items, set, perRow, itemW, colorFn)
            for i = 1, #items do
                local key, label = items[i][1], items[i][2]
                local col = (i - 1) % perRow
                local row = math.floor((i - 1) / perRow)
                local check = UI.Keep(restFrame, "check", function(parent)
                    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
                    c:SetSize(18, 18)
                    return c
                end)
                check:SetPoint("TOPLEFT", restFrame, "TOPLEFT", PAD + col * itemW, ry - row * 22)
                check:SetChecked(set[key])
                check:SetScript("OnClick", function(self)
                    if self:GetChecked() then set[key] = true else set[key] = nil end
                end)
                local lbl = UI.KeepFont(restFrame, "checkLabel", 10, nil, ns.THEME.fg)
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
            local items = ns.PlayableClasses()
            local classColors = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS
            CheckGrid(items, targetClasses, 3, 140, function(token)
                local c = classColors and classColors[token]
                if c then return c.r, c.g, c.b end
            end)
        end

        RestLabel("Raid Group")
        do
            local items = {}
            for i = 1, 4 do items[i] = { i, tostring(i) } end
            -- Groups 5-8 appear only when already assigned, so old assignments stay editable.
            for i = 5, 8 do
                if targetSubgroups[i] then items[#items + 1] = { i, tostring(i) } end
            end
            CheckGrid(items, targetSubgroups, 8, 52)
        end

        local function RestBox(labelText, existingText, onChange)
            RestLabel(labelText)
            local box = KeptBox(restFrame)
            box:SetPoint("TOPLEFT", restFrame, "TOPLEFT", PAD, ry)
            box:SetPoint("RIGHT", restFrame, "RIGHT", -PAD, 0)
            box:SetHeight(26)
            box:SetMaxLetters(200)
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
        local l = UI.KeepFont(displayBody, "label", 11, nil, ns.THEME.muted)
        l:SetPoint("TOPLEFT", displayBody, "TOPLEFT", PAD, dsy)
        l:SetText(text)
        dsy = dsy - 16
    end
    local function DsBox(maxLetters, numeric, rightInset)
        local box = KeptBox(displayBody)
        box:SetPoint("TOPLEFT", displayBody, "TOPLEFT", PAD, dsy)
        box:SetPoint("RIGHT", displayBody, "RIGHT", -(rightInset or PAD), 0)
        box:SetHeight(26)
        box:SetMaxLetters(maxLetters or 60)
        box:SetNumeric(numeric == true)
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
              .. "below. Nameplate Glow does nothing inside dungeons and raids, where the "
              .. "game keeps friendly nameplates from addons; use Raid-Frame Glow there.",
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
    local iconPreview = UI.Keep(displayBody, "iconPreview", function(parent)
        local t = parent:CreateTexture(nil, "ARTWORK")
        t:SetSize(24, 24)
        return t
    end)
    iconPreview:SetPoint("LEFT", iconBox, "RIGHT", 6, 0)
    iconPreview:Hide()
    local iconFeedback = UI.KeepFont(displayBody, "iconFeedback", 10, nil, ns.THEME.muted)
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

    -- MRT's event-13 "hide after use": your successful cast hides it before Linger ends.
    DsLabel("Hide Once I Cast (Spell ID, optional)")
    local hideCastBox = DsBox(9, true, PAD + 34)
    local hideCastFeedback = UI.KeepFont(displayBody, "hideCastFeedback", 10, nil, ns.THEME.muted)
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

    local healerVal = existing and existing.healerReminder == true or false
    local enabledVal = (existing == nil) or existing.enabled ~= false
    W:DualRow(displayBody, dsy,
        { type = "toggle", text = "Enabled",
          getValue = function() return enabledVal end,
          setValue = function(v) enabledVal = v end },
        { type = "toggle", text = "Healer Reminder",
          tooltip = "Mark this reminder so players can opt out with Enable Healer Reminders in Setup.",
          getValue = function() return healerVal end,
          setValue = function(v) healerVal = v end }
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
            healerReminder = healerVal or nil,
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
        -- Also refreshes the cached has-reminders flags the combat log hot path reads.
        ns.RefreshRuntime()
        dimmer:Hide()
        if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
    end

    UI.KeepButton(panel, "preview", "Preview", 90, 26, function()
        -- Bypasses targeting, so a curator sees it whoever it is for.
        local entry, buildErr = BuildEntry()
        if entry then
            if ns.PreviewRaidReminder then ns.PreviewRaidReminder(entry) end
        else
            ns.Print("|cffff6060" .. (buildErr or "could not preview this reminder") .. "|r")
        end
    end):SetPoint("BOTTOM", panel, "BOTTOM", -110, 16)
    UI.KeepButton(panel, "save", "Save", 90, 26, Save):SetPoint("BOTTOM", panel, "BOTTOM", -10, 16)
    UI.KeepButton(panel, "cancel", "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 90, 16)

    end)
    if not ok then
        -- Fixed offset: TAB_TOP is local to the closure that failed.
        local errText = UI.KeepFont(panel, "error", 11, nil, { r = 1, g = 0.35, b = 0.35 })
        errText:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -70)
        errText:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
        errText:SetJustifyH("LEFT")
        errText:SetWordWrap(true)
        errText:SetText("Failed to build this panel: " .. tostring(err))
        ns.Print("|cffff6060raid reminder editor|r: " .. tostring(err))
    end

    dimmer:Show()
    -- Returned so a caller can set dimmer.onClose and refresh its own list.
    return dimmer, panel
end

-------------------------------------------------------------------------------
--  Diagnostics
-------------------------------------------------------------------------------
-- The journal's Tank flag may not match the HUD's TankRole bit (both are DB2 data), so
-- this prints totals to compare against a known boss.
function ns.PrintBossSummary()
    local data = ns.ScrapeBosses(false)
    if not data then
        ns.Print("could not read the journal (" .. tostring(scrapeFailed) .. ").")
        return
    end

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
