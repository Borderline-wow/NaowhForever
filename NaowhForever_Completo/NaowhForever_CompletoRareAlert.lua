-------------------------------------------------------------------------------
--  NaowhForever_CompletoRareAlert.lua -- Rare Alerts: a warning when a rare is near you, as
--  RareScanner gives, and a raid mark on it (a skull unless you pick another). Any creature the game calls rare or rare elite
--  counts, in the data or not.
--
--  A rare is seen when its nameplate comes up, when you mouse over it or target it, and
--  where the game marks it on the minimap (a vignette, if Forever gives rares one). The
--  alert is a card with the rare's portrait, its name, level and whether you killed it, on a
--  spot of its own (drag it there); its border glows and pulses, it plays a sound and flashes
--  the game's taskbar icon. Its pin (top right) sets a waypoint to the rare; it goes after a
--  while, on a right-click, or once the rare is killed. Each rare alerts once in a while, not every time
--  its nameplate comes back.
--
--  The mark goes on a rare you can see as a unit (nameplate, mouseover or target, not a
--  minimap mark), once per creature, and only where it has no mark yet and you may mark: on
--  your own, in a party, or as a raid's leader or assistant.
--
--  Off until Rare Alerts is switched on: then the events above, and nothing more.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.CompletoSettings
local R = ns.Completo.Rares

-- The raid marks Mark Rare offers: key, the game's index, name. "none" puts none on.
local MARKS = {
    { "star", 1, "Star" }, { "circle", 2, "Circle" }, { "diamond", 3, "Diamond" },
    { "triangle", 4, "Triangle" }, { "moon", 5, "Moon" }, { "square", 6, "Square" },
    { "cross", 7, "Cross" }, { "skull", 8, "Skull" },
}
local MARK_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

-- The raid mark's index Mark Rare picked, nil for none.
local function Marker()
    local key = S.Get("rareMarker")
    for _, mark in ipairs(MARKS) do
        if mark[1] == key then return mark[2] end
    end
end
local SHOW_FOR = 20       -- seconds the alert stays up
local AGAIN_AFTER = 300   -- seconds before the same rare alerts again
-- The glow around the card: GLOW wide, from GLOW_ALPHA at the card's edge to nothing, in the
-- theme's accent; it breathes between PULSE_LOW and full every PULSE seconds while shown.
local GLOW, GLOW_ALPHA = 12, 0.55
local GLOW_CORNER = "Interface\\AddOns\\NaowhForever_Completo\\Media\\GlowCorner"
local PULSE, PULSE_LOW = 0.9, 0.25

local function On()
    return S.Get("enabled") and S.Get("rareAlert")
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-------------------------------------------------------------------------------
--  The alert
-------------------------------------------------------------------------------
-- The game's own alert sounds, offered before the addon's sound files: key, how it plays,
-- what, label. "name": a SOUNDKIT name (left out where the client lacks it); "kit": a sound
-- kit's ID SOUNDKIT has no name for (the battleground flag sounds); "file": a sound file's ID,
-- as rare scanners use them (SilverDragon's IDs; the Gruntling Horn is RareScanner's default,
-- the War Drums the old _NPCScan's).
local GAME_SOUNDS = {
    { "file:gruntlinghorn", "file", 598196, "Gruntling Horn" },
    { "game:raidwarning", "name", "RAID_WARNING", "Raid Warning" },
    { "game:legendary", "name", "UI_LEGENDARY_LOOT_TOAST", "Legendary Loot" },
    { "file:squirehorn", "file", 598079, "Squire Horn" },
    { "file:wardrums", "file", 567275, "War Drums" },
    { "game:flagalliance", "kit", 8174, "Flag Taken, Alliance" },
    { "game:flaghorde", "kit", 8212, "Flag Taken, Horde" },
}

local function Find(key)
    for _, sound in ipairs(GAME_SOUNDS) do
        if sound[1] == key then return sound end
    end
end

-- Whether the client has it: a kit or file ID always; a SOUNDKIT name only where it is known.
local function Has(sound)
    return sound[2] ~= "name" or (SOUNDKIT ~= nil and SOUNDKIT[sound[3]] ~= nil)
end

-- Plays a GAME_SOUNDS entry; false when the client has no such sound.
local function PlayGame(sound)
    if not sound or not Has(sound) then return false end
    if sound[2] == "file" then
        PlaySoundFile(sound[3], "Master")
    else
        PlaySound(sound[2] == "kit" and sound[3] or SOUNDKIT[sound[3]], "Master")
    end
    return true
end

local DEFAULT_SOUND = "file:gruntlinghorn"

-- key: a game sound's, an addon sound file's, or one no longer offered ("none", an older
-- pick) for the default.
local function PlaySoundKey(key)
    if PlayGame(Find(key)) then return end
    if ns.UI.SoundPathFor(key) then return ns.UI.PlaySoundKey(key) end
    PlayGame(Find(DEFAULT_SOUND))
end

local alert, flash, hideTimer
local shownNpc   -- the rare the alert is about, by npcID; nil for one not in the data

local CARD_W, CARD_H, PORTRAIT, PAD = 300, 78, 58, 10
local BLACK = { r = 0, g = 0, b = 0 }
local STAR_ATLAS = "VignetteKill"

local function HideAlert()
    if not alert then return end
    if hideTimer then hideTimer:Cancel() end
    hideTimer = nil
    flash:Stop()
    alert:Hide()
    shownNpc = nil
end

-- Where the card sits: where you last dragged it, else above the middle of the screen. Kept
-- as its middle's offset from the screen's, in the screen's units, so it stays put when its
-- size changes.
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 260 }

local function Place()
    local pos = S.Get("rareAlertPos") or DEFAULT_POS
    local scale = S.Get("rareAlertScale") or 1
    alert:SetScale(scale)
    alert:ClearAllPoints()
    alert:SetPoint("CENTER", UIParent, "CENTER", pos.x / scale, pos.y / scale)
end

local function DragStart(card)
    card.dragged = true
    card:StartMoving()
end

local function DragStop(card)
    card:StopMovingOrSizing()
    local cx, cy = card:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local ratio = card:GetEffectiveScale() / UIParent:GetEffectiveScale()
    S.Set("rareAlertPos", { point = "CENTER", relPoint = "CENTER",
        x = math.floor(cx * ratio - ux + 0.5), y = math.floor(cy * ratio - uy + 0.5) })
    Place()
end

-- Right-click puts the card away; the end of a drag is no click.
local function CardClicked(card, button)
    if card.dragged then
        card.dragged = false
        return
    end
    if button == "RightButton" then HideAlert() end
end

-- The pin: a waypoint to the rare, where the minimap saw it, else its spawn spot or way
-- nearest you.
local function PinClicked()
    local spot = alert.spot
    if spot.map then ns.PlaceWaypoint(alert.name:GetText(), spot.map, spot.x, spot.y) end
end

local function CardEnter(card)
    GameTooltip:SetOwner(card, "ANCHOR_TOP")
    GameTooltip:SetText(card.name:GetText() or "Rare", 1, 1, 1)
    GameTooltip:AddLine("Drag to move it. Right-click to close it.", 0.62, 0.62, 0.62)
    GameTooltip:Show()
end

local function CardLeave()
    GameTooltip:Hide()
end

-- The face of the rare: its model zoomed in to the head, as a unit frame's portrait.
local function Zoom(model)
    model:SetPortraitZoom(1)
end

local function BuildAlert()
    alert = CreateFrame("Button", "NaowhForeverRareAlert", UIParent)
    alert:SetSize(CARD_W, CARD_H)
    alert:SetMovable(true)
    alert:SetClampedToScreen(true)
    alert:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    alert:SetScript("OnClick", CardClicked)
    alert:RegisterForDrag("LeftButton")
    alert:SetScript("OnDragStart", DragStart)
    alert:SetScript("OnDragStop", DragStop)
    alert:SetScript("OnEnter", CardEnter)
    alert:SetScript("OnLeave", CardLeave)
    ns.Solid(alert, "BACKGROUND", T.panel, 0.94):SetAllPoints()
    ns.Border(alert, BLACK)
    alert.spot = {}

    local frame = CreateFrame("Frame", nil, alert)
    frame:SetSize(PORTRAIT, PORTRAIT)
    frame:SetPoint("LEFT", PAD, 0)
    ns.Solid(frame, "BACKGROUND", BLACK, 1):SetAllPoints()
    ns.Border(frame, T.accent)
    alert.model = CreateFrame("PlayerModel", nil, frame)
    alert.model:SetPoint("TOPLEFT", 1, -1)
    alert.model:SetPoint("BOTTOMRIGHT", -1, 1)
    alert.model:SetScript("OnModelLoaded", Zoom)
    -- The rare star where there is no model to show.
    alert.star = frame:CreateTexture(nil, "ARTWORK")
    alert.star:SetPoint("CENTER")
    alert.star:SetSize(PORTRAIT * 0.6, PORTRAIT * 0.6)
    alert.star:SetAtlas(STAR_ATLAS)

    local Parts, St = ns.Shared.Parts, ns.Shared.Style
    alert.pin = Parts.IconButton(alert, PinClicked, St.PIN, 0, "Waypoint")
    alert.pin.hint = "To the rare: where it was seen, else its nearest spot."
    alert.pin:SetPoint("TOPRIGHT", -PAD + 2, -PAD + 2)

    -- The text, its three lines in the middle of the card beside the portrait, clear of the pin.
    local left, right = PAD + PORTRAIT + 10, -(PAD + 24)
    alert.kicker = ns.Font(alert, 10, nil, T.accent)
    alert.kicker:SetPoint("TOPLEFT", left, -14)
    alert.kicker:SetText("RARE SPOTTED")
    alert.skull = alert:CreateTexture(nil, "ARTWORK")
    alert.skull:SetSize(14, 14)
    alert.skull:SetPoint("LEFT", alert.kicker, "RIGHT", 6, 0)
    alert.name = ns.Font(alert, 15, nil, T.fg)
    alert.name:SetPoint("TOPLEFT", alert.kicker, "BOTTOMLEFT", 0, -4)
    alert.name:SetPoint("RIGHT", right, 0)
    alert.name:SetJustifyH("LEFT")
    alert.name:SetWordWrap(false)
    alert.about = ns.Font(alert, 11, nil, T.muted)
    alert.about:SetPoint("TOPLEFT", alert.name, "BOTTOMLEFT", 0, -4)
    alert.about:SetPoint("RIGHT", -PAD, 0)
    alert.about:SetJustifyH("LEFT")
    alert.about:SetWordWrap(false)

    -- The glowing border: soft edges fading out from the card, and a thin line on its edge,
    -- one frame under the card whose alpha breathes.
    local glow = CreateFrame("Frame", nil, alert)
    glow:SetPoint("TOPLEFT", -GLOW, GLOW)
    glow:SetPoint("BOTTOMRIGHT", GLOW, -GLOW)
    glow:SetFrameLevel(math.max(alert:GetFrameLevel() - 1, 0))
    local c = T.accent
    local edge, clear = CreateColor(c.r, c.g, c.b, GLOW_ALPHA), CreateColor(c.r, c.g, c.b, 0)
    -- The sides: from the card's edge out, edge colour at the card and clear outside, as long
    -- as the card. x1, y1: a side's top left from the glow's; x2, y2: its bottom right.
    local function Side(x1, y1, x2, y2, orientation, from, to)
        local t = glow:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint("TOPLEFT", x1, y1)
        t:SetPoint("BOTTOMRIGHT", x2, y2)
        t:SetGradient(orientation, from, to)
    end
    Side(GLOW, 0, -GLOW, GLOW + CARD_H, "VERTICAL", edge, clear)                   -- top
    Side(GLOW, -(GLOW + CARD_H), -GLOW, 0, "VERTICAL", clear, edge)                -- bottom
    Side(0, -GLOW, -(GLOW + CARD_W), GLOW, "HORIZONTAL", clear, edge)              -- left
    Side(GLOW + CARD_W, -GLOW, 0, GLOW, "HORIZONTAL", edge, clear)                 -- right
    -- The corners: Media/GlowCorner.tga fades out round its bottom right (the card's corner),
    -- turned for each corner by its texture coordinates.
    local CORNERS = {
        { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
        { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 },
    }
    for _, corner in ipairs(CORNERS) do
        local t = glow:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(GLOW_CORNER)
        t:SetSize(GLOW, GLOW)
        t:SetPoint(corner[1])
        t:SetTexCoord(corner[2], corner[3], corner[4], corner[5])
        t:SetVertexColor(c.r, c.g, c.b, GLOW_ALPHA)
    end
    local line = CreateFrame("Frame", nil, glow)
    line:SetPoint("TOPLEFT", alert, "TOPLEFT")
    line:SetPoint("BOTTOMRIGHT", alert, "BOTTOMRIGHT")
    line:SetFrameLevel(alert:GetFrameLevel() + 3)
    ns.Border(line, c)
    alert.glow = glow

    flash = glow:CreateAnimationGroup()
    flash:SetLooping("BOUNCE")
    local pulse = flash:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(PULSE_LOW)
    pulse:SetDuration(PULSE)
    pulse:SetSmoothing("IN_OUT")
    glow.pulse = flash

    alert:Hide()
    Place()
end

local function PlayAlertSound()
    if S.Get("rareSound") then PlaySoundKey(S.Get("rareSoundKey")) end
end

-- The portrait: the unit's own model while it is in sight, else the creature's; the rare
-- star for a rare with neither.
local function SetPortrait(unit, npc)
    local model = alert.model
    model:ClearModel()
    local shown = false
    if unit and UnitExists(unit) then
        model:SetUnit(unit)
        shown = true
    elseif npc then
        model:SetCreature(npc)
        shown = true
    end
    model:SetShown(shown)
    if shown then Zoom(model) end
    alert.star:SetShown(not shown)
end

local function KillNote(npc)
    if not (npc and R.Known(npc)) then return nil end
    local record = R.Record(npc)
    if not record then return "not killed yet" end
    if record.n > 1 then return ("killed %d times"):format(record.n) end
    return "killed before"
end

-- seen: { name, level (or nil), npc (its npcID, or nil), unit (its unit token while in sight),
-- elite, marked (the raid mark's index that went on it), map, x, y (where the minimap saw it, percent) }.
-- quiet: no sound, taskbar flash or timer (Unlock Mode's preview).
local function ShowAlert(seen, quiet)
    if not alert then BuildAlert() end
    local npc = seen.npc
    shownNpc = npc
    SetPortrait(seen.unit, npc)
    alert.name:SetText(seen.name)
    if seen.marked then alert.skull:SetTexture(MARK_ICON:format(seen.marked)) end
    alert.skull:SetShown(seen.marked ~= nil)
    local elite = seen.elite
    if elite == nil and npc and R.Known(npc) then elite = R.Elite(npc) end
    local parts = {}
    if seen.level and seen.level > 0 then parts[#parts + 1] = ("Level %d"):format(seen.level) end
    parts[#parts + 1] = elite and "rare elite" or "rare"
    local note = KillNote(npc)
    if note then parts[#parts + 1] = note end
    local about = table.concat(parts, ", ")
    alert.about:SetText(about:sub(1, 1):upper() .. about:sub(2))
    -- Where the waypoint goes: where the minimap saw it, else its nearest known spot.
    local spot = alert.spot
    spot.map, spot.x, spot.y = seen.map, seen.x, seen.y
    if not spot.map and npc and R.Known(npc) then spot.map, spot.x, spot.y = R.Spot(npc) end
    alert.pin:SetShown(spot.map ~= nil)
    alert:Show()
    flash:Play()
    if hideTimer then hideTimer:Cancel() end
    hideTimer = nil
    if quiet then return end
    hideTimer = C_Timer.NewTimer(SHOW_FOR, HideAlert)
    PlayAlertSound()
    if FlashClientIcon then FlashClientIcon() end
end

-- The rare the alert is about was killed: nothing left to warn about.
R.OnChange(function(npc)
    if shownNpc and npc == shownNpc and R.Killed(npc) then HideAlert() end
end)

-------------------------------------------------------------------------------
--  Seeing a rare
-------------------------------------------------------------------------------
local alerted = {}   -- npcID or name -> GetTime() of its latest alert
local marked = {}    -- GUID -> true once a mark went on it

-- Never in a group's instance or fight, where the marks are the tank's to give; in a raid
-- only as its leader or an assistant.
local function MayMark()
    if not IsInGroup() then return true end
    if IsInInstance() or InCombatLockdown() then return false end
    if not IsInRaid() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Setting a mark moves it off whatever has it: whether the mark is already on another unit
-- you or your group can see (your target or focus, or a group member's target).
local SEEN_UNITS = { "target", "focus", "mouseover" }
for i = 1, 4 do SEEN_UNITS[#SEEN_UNITS + 1] = "party" .. i .. "target" end
for i = 1, 40 do SEEN_UNITS[#SEEN_UNITS + 1] = "raid" .. i .. "target" end

local function MarkInUse(marker, guid)
    for _, unit in ipairs(SEEN_UNITS) do
        local index = GetRaidTargetIndex(unit)
        if Secret(index) then return true end
        if index == marker then
            local other = UnitGUID(unit)
            if Secret(other) or other ~= guid then return true end
        end
    end
    return false
end

-- Mark Rare's mark on it, once per creature, where it has no mark yet and no one else tapped
-- it: the mark's index, or nil.
local function Mark(unit, guid)
    local marker = Marker()
    if not marker or marked[guid] or not MayMark() then return nil end
    local index, denied = GetRaidTargetIndex(unit), UnitIsTapDenied(unit)
    if Secret(index) or index or Secret(denied) or denied then return nil end
    if MarkInUse(marker, guid) then return nil end
    marked[guid] = true
    SetRaidTarget(unit, marker)
    return marker
end

-- Alerts once in AGAIN_AFTER seconds per rare; one you killed only with Alert for Killed Rares.
local function Due(key, npc)
    if alerted[key] and GetTime() - alerted[key] < AGAIN_AFTER then return false end
    return not (npc and R.Known(npc) and R.Killed(npc) and not S.Get("rareAlertKilled"))
end

local function Alert(key, seen)
    if not Due(key, seen.npc) then return end
    alerted[key] = GetTime()
    ShowAlert(seen)
end

local RARE = { rare = true, rareelite = true }

-- Every nameplate and mouseover comes here: the classification first, before anything that
-- makes a string.
local function Check(unit)
    if not UnitExists(unit) then return end
    local kind = UnitClassification(unit)
    if Secret(kind) or not RARE[kind] then return end
    local guid = UnitGUID(unit)
    if Secret(guid) or not guid then return end
    local npc = R.NpcOf(guid)
    if not npc then return end
    local dead, hostile = UnitIsDead(unit), UnitCanAttack("player", unit)
    if Secret(dead) or Secret(hostile) or dead or not hostile then return end
    local name, level = UnitName(unit), UnitLevel(unit)
    if Secret(name) then return end
    if Secret(level) then level = nil end
    if not Due(npc, npc) then return end
    local skull = Mark(unit, guid)
    Alert(npc, { name = name, level = level, npc = npc, unit = unit, elite = kind == "rareelite", marked = skull })
end

-- A minimap mark: a rare in the data, or one the game draws as a creature to kill.
local function CheckVignette(id)
    local info = C_VignetteInfo.GetVignetteInfo(id)
    if not info or Secret(info.objectGUID) or Secret(info.name) then return end
    local npc = R.NpcOf(info.objectGUID)
    local atlas = type(info.atlasName) == "string" and not Secret(info.atlasName) and info.atlasName or ""
    if not npc or not (R.Known(npc) or atlas:find("Kill")) then return end
    if R.Known(npc) and not R.Mine(npc) then return end
    local level
    if R.Known(npc) then level = R.Levels(npc) end
    -- Where the minimap sees it, on the map you are on.
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_VignetteInfo.GetVignettePosition and C_VignetteInfo.GetVignettePosition(id, map)
    local x, y
    if pos and not Secret(pos) then x, y = pos:GetXY() end
    Alert(npc, { name = info.name or (R.Known(npc) and R.Name(npc)) or "Rare", level = level, npc = npc,
        map = x and map, x = x and x * 100, y = y and y * 100 })
end

-- The alert as a rare would bring it, sound and all: about your target when you can attack it,
-- with Mark Rare's mark on it; else about a made-up rare. Leaves the
-- once-in-a-while memory alone, so a real rare still alerts.
local function TestAlert()
    local name, level, npc, skull, unit = "Mist Howler", 22, 10644, nil, nil
    local guid = UnitGUID("target")
    local hostile = UnitExists("target") and UnitCanAttack("player", "target")
    if guid and not Secret(guid) and not Secret(hostile) and hostile then
        local targetName, targetLevel = UnitName("target"), UnitLevel("target")
        if not Secret(targetName) then
            name = targetName
            level = not Secret(targetLevel) and targetLevel or nil
            npc = R.NpcOf(guid)
            unit = "target"
            local marker = Marker()
            if marker and MayMark() then
                local index = GetRaidTargetIndex("target")
                if not Secret(index) and index ~= marker then
                    SetRaidTarget("target", marker)
                    skull = marker
                end
            end
        end
    end
    ShowAlert({ name = name, level = level, npc = npc, unit = unit, marked = skull })
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, onMinimap)
    if event == "NAME_PLATE_UNIT_ADDED" then
        Check(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Check("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Check("mouseover")
    elseif event == "VIGNETTE_MINIMAP_UPDATED" then
        if onMinimap and not Secret(unit) then CheckVignette(unit) end
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        HideAlert()
        return
    end
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    if C_VignetteInfo and C_VignetteInfo.GetVignetteInfo then
        events:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "rareAlert" then Apply() end
    if key == "rareAlertScale" and alert then Place() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if On() then ShowAlert({ name = "Mist Howler", level = 22, npc = 10644, marked = Marker() }, true) end
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", HideAlert)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local OFF = "Turn on Completo"

local function Enabled() return S.Get("enabled") == true end
local function SoundOn() return Enabled() and S.Get("rareSound") == true end

-- Not for a rare: the addon's spoken lines ("Dispel me", "Move out") and BugSack's error sound.
local function Unfit(key, name)
    return key:find("^voice:") ~= nil or tostring(name or ""):find("BugSack", 1, true) ~= nil
        or key:find("BugSack", 1, true) ~= nil
end

-- The game's sounds, then the addon's.
local function Sounds()
    local values, order = {}, {}
    for _, sound in ipairs(GAME_SOUNDS) do
        if Has(sound) then
            values[sound[1]] = sound[4] .. " (game)"
            order[#order + 1] = sound[1]
        end
    end
    local _, names, keys = nil, nil, nil
    if ns.SoundChoices then _, names, keys = ns.SoundChoices() end
    for _, key in ipairs(keys or {}) do
        if not Unfit(key, names[key]) then
            values[key] = names[key]
            order[#order + 1] = key
        end
    end
    return values, order
end

-- Mark Rare's list: None, then each mark with its icon.
local function MarkChoices()
    local values, order = { none = "None" }, { "none" }
    for _, mark in ipairs(MARKS) do
        values[mark[1]] = ("|T%s:14|t %s"):format(MARK_ICON:format(mark[2]), mark[3])
        order[#order + 1] = mark[1]
    end
    return values, order
end

local function Summary(store)
    local parts = {}
    for _, mark in ipairs(MARKS) do
        if mark[1] == store.Get("rareMarker") then parts[#parts + 1] = "a " .. mark[3]:lower() .. " on it" end
    end
    if store.Get("rareSound") then parts[#parts + 1] = "a sound" end
    if #parts == 0 then return "A warning when a rare is near" end
    return "A warning when a rare is near, " .. table.concat(parts, " and ")
end

Settings.Page("Completo/Rares", S):Card({
    id = "rareAlert", name = "Rare Alerts", order = 20, switch = "rareAlert",
    help = "A warning when a rare is near you: when its nameplate comes up, you mouse over it or target "
        .. "it. A card with its portrait: drag it where you want it, right-click it to close it, and its "
        .. "pin sets a waypoint to the rare.",
    summary = Summary,
    rows = {
        { key = "rareMarker", label = "Mark Rare", choice = MarkChoices, needs = Enabled, why = OFF,
          help = "The raid mark put on the rare, if it has no mark yet, or None. In a raid only as its "
              .. "leader or an assistant." },
        { key = "rareAlertKilled", label = "Alert for Killed Rares", toggle = true, needs = Enabled, why = OFF,
          help = "Also warns about rares you have killed before." },
        { key = "rareSound", label = "Play a Sound", toggle = true, needs = Enabled, why = OFF,
          help = "Plays when the warning comes up, and flashes the game's icon on your taskbar." },
        { key = "rareSoundKey", label = "Sound", choice = Sounds, needs = SoundOn, why = "Needs Play a Sound",
          help = "The game's own alert sounds first, then the addon's. Each plays as you pick it.",
          get = function()
              local key = S.Get("rareSoundKey")
              return (key == nil or key == "none") and DEFAULT_SOUND or key
          end,
          set = function(key)
              S.Set("rareSoundKey", key)
              PlaySoundKey(key)
          end },
        { key = "rareAlertScale", label = "Card Size", slider = { 50, 200, 5 }, unit = "%", scale = 0.01,
          needs = Enabled, why = OFF, help = "How big the card is. Test Alert shows it while you set it." },
        { label = "Card Position", buttonText = "Reset", needs = Enabled, why = OFF,
          button = function()
              S.Set("rareAlertPos", nil)
              if alert then Place() end
          end,
          help = "Puts the card back above the middle of the screen." },
        { label = "Test Alert", buttonText = "Test", button = TestAlert, needs = Enabled, why = OFF,
          help = "Shows the warning with its sound. With something you can attack targeted, it is about "
              .. "that, with Mark Rare's mark on it. Drag the card to where you want it." },
    },
})
