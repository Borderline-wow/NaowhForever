-------------------------------------------------------------------------------
--  NaowhForever_CompletoRareAlert.lua -- Rare Alerts: a warning when a rare is near you, as
--  RareScanner gives, and a raid mark on it (a skull unless you pick another). Any creature the game calls rare or rare elite
--  counts, in the data or not.
--
--  A rare is seen when its nameplate comes up, when you mouse over it or target it, and
--  where the game marks it on the minimap (a vignette, if Forever gives rares one). The
--  alert is a card drawn as the BiS List's drop alert: the rare's portrait, its name and raid
--  mark, and a line with its level, kind and whether you killed it; it fades in, plays a sound
--  and flashes the game's taskbar icon, and is moved in the HUD Editor. Its pin (top right)
--  sets a waypoint to the rare; it fades after Stays For, goes on a right-click, or once the
--  rare is killed. Each rare alerts once in a while, not every time its nameplate comes back.
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
local Parts, St = ns.Shared.Parts, ns.Shared.Style

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
local AGAIN_AFTER = 300   -- seconds before the same rare alerts again

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

local W, H, ICON, PAD, MARK = 300, 54, 38, 8, 14
local DETAIL_SMALLER = 2   -- the line under the name, this much under Font Size
local PIN_ROOM = 20        -- the name stops short of the pin
local FADE = 0.3
local GLOW, GLOW_ALPHA = 3, 0.35
local BLACK = { r = 0, g = 0, b = 0 }
local STAR_ATLAS = "VignetteKill"
local DOT = "  \194\183  "
local TAPPED = "Tapped by someone else"

local alert, holder
local shownNpc   -- the rare the alert is about, by npcID; nil for one not in the data
local shownGuid  -- the creature itself; a minimap alert takes the first live one seen
local events = CreateFrame("Frame")

-- The face of the rare: its model zoomed in to the head, as a unit frame's portrait.
local function Zoom(model)
    model:SetPortraitZoom(1)
end

-- The pin: a waypoint to the rare, where the minimap saw it, else its spawn spot or way
-- nearest you.
local function PinClicked(button)
    local card = button:GetParent()
    local spot = card.spot
    if spot.map then ns.PlaceWaypoint(card.name:GetText(), spot.map, spot.x, spot.y) end
end

-- The card, live or in its settings preview.
local function NewCard(parent, name)
    local f = CreateFrame("Button", name, parent)
    f:SetSize(W, H)
    -- The glow: a ring GLOW wide round the card, its four sides outside the card's edge.
    f.glow = CreateFrame("Frame", nil, f)
    f.glow:SetPoint("TOPLEFT", -GLOW, GLOW)
    f.glow:SetPoint("BOTTOMRIGHT", GLOW, -GLOW)
    local c = T.accent
    local top = ns.Solid(f.glow, "BACKGROUND", c, GLOW_ALPHA)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(GLOW)
    local bottom = ns.Solid(f.glow, "BACKGROUND", c, GLOW_ALPHA)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(GLOW)
    local left = ns.Solid(f.glow, "BACKGROUND", c, GLOW_ALPHA)
    left:SetPoint("TOPLEFT", 0, -GLOW)
    left:SetPoint("BOTTOMLEFT", 0, GLOW)
    left:SetWidth(GLOW)
    local right = ns.Solid(f.glow, "BACKGROUND", c, GLOW_ALPHA)
    right:SetPoint("TOPRIGHT", 0, -GLOW)
    right:SetPoint("BOTTOMRIGHT", 0, GLOW)
    right:SetWidth(GLOW)
    f.glow.sides = { top, bottom, left, right }
    f.backdrop = Parts.HudBackdrop(f)
    f.spot = {}

    local icon = CreateFrame("Frame", nil, f)
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", PAD, 0)
    ns.Solid(icon, "BACKGROUND", BLACK, 1):SetAllPoints()
    ns.Border(icon, BLACK)
    f.model = CreateFrame("PlayerModel", nil, icon)
    f.model:SetPoint("TOPLEFT", 1, -1)
    f.model:SetPoint("BOTTOMRIGHT", -1, 1)
    f.model:SetScript("OnModelLoaded", Zoom)
    -- The rare star where there is no model to show.
    f.star = icon:CreateTexture(nil, "ARTWORK")
    f.star:SetPoint("CENTER")
    f.star:SetSize(ICON * 0.6, ICON * 0.6)
    f.star:SetAtlas(STAR_ATLAS)
    f.icon = icon

    f.pin = Parts.IconButton(f, PinClicked, St.PIN, 0, "Waypoint")
    f.pin.hint = "To the rare: where it was seen, else its nearest spot."
    f.pin:SetPoint("TOPRIGHT", -PAD + 2, -PAD + 2)

    f.name = ns.Font(f, 13, nil, T.fg)
    f.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", PAD, -2)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.mark = f:CreateTexture(nil, "ARTWORK")
    f.mark:SetSize(MARK, MARK)
    f.mark:SetPoint("LEFT", f.name, "RIGHT", 4, 0)
    f.detail = ns.Font(f, 11, nil, T.muted)
    f.detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", PAD, 2)
    f.detail:SetPoint("RIGHT", -PAD, 0)
    f.detail:SetJustifyH("LEFT")
    f.detail:SetWordWrap(false)
    return f
end

-- The portrait: the unit's own model while it is in sight, else the creature's; the rare
-- star for a rare with neither.
local function SetPortrait(f, unit, npc)
    local model = f.model
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
    f.star:SetShown(not shown)
end

-- record: the rare's kill record, false for a rare in the data not killed, nil for one not in it.
local function KillNote(record)
    if record == nil then return nil end
    if not record then return "Not killed yet" end
    if record.n > 1 then return ns.Color(St.HAVE_RGB, ("Killed %d times"):format(record.n)) end
    return ns.Color(St.HAVE_RGB, "Killed before")
end

local function Detail(seen)
    local parts = {}
    if seen.level and seen.level > 0 then parts[#parts + 1] = ("Level %d"):format(seen.level) end
    parts[#parts + 1] = seen.elite and "Rare elite" or "Rare"
    local note = seen.tapped and ns.Color(St.WARN_RGB, TAPPED) or KillNote(seen.record)
    if note then parts[#parts + 1] = note end
    return table.concat(parts, DOT)
end

-- Paints the card by your look settings for seen (ShowAlert's); the portrait is SetPortrait's.
local function Paint(f, seen)
    local mode = f.backdrop:SetMode(S.Get("rareAlertBackground"))
    local font, size, outline = S.Get("rareAlertFont"), S.Get("rareAlertFontSize"), S.Get("rareAlertOutline")
    Parts.HudFont(f.name, font, size, outline, mode)
    Parts.HudFont(f.detail, font, size - DETAIL_SMALLER, outline, mode)
    local glow = S.Get("rareAlertGlow") == true
    f.glow:SetShown(glow)
    if glow then
        local c = T.accent
        for _, side in ipairs(f.glow.sides) do side:SetColorTexture(c.r, c.g, c.b, GLOW_ALPHA) end
    end
    local marked = seen.marked
    if marked then f.mark:SetTexture(MARK_ICON:format(marked)) end
    f.mark:SetShown(marked ~= nil)
    -- As wide as the name, so the mark sits right after it, up to the room there is.
    local room = W - PAD * 3 - ICON - PIN_ROOM - (marked and MARK + 4 or 0)
    f.name:SetWidth(0)
    f.name:SetText(seen.name)
    f.name:SetWidth(math.min(f.name:GetStringWidth() + 1, room))
    f.detail:SetText(Detail(seen))
    local spot = f.spot
    spot.map, spot.x, spot.y = seen.map, seen.x, seen.y
    if not spot.map and seen.npc and R.Known(seen.npc) then spot.map, spot.x, spot.y = R.Spot(seen.npc) end
    f.pin:SetShown(spot.map ~= nil)
end

local function HideAlert()
    if not alert then return end
    alert.fade:Stop()
    alert:Hide()
    shownNpc, shownGuid = nil, nil
    events:UnregisterEvent("UNIT_FLAGS")
end

-- Its spot from the HUD Editor, else above the middle of the screen. Kept in the screen's
-- units, so Size grows it about the same spot.
local function Place()
    local scale = S.Get("rareAlertScale")
    holder:SetScale(scale)
    local pos = S.Get("rareAlertPosition")
    holder:ClearAllPoints()
    if pos then
        holder:SetPoint(pos.point, UIParent, pos.relPoint, pos.x / scale, pos.y / scale)
    else
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 260 / scale)
    end
end

-- Right-click puts the card away.
local function CardClicked(_, button)
    if button == "RightButton" then HideAlert() end
end

local function CardEnter(card)
    GameTooltip:SetOwner(card, "ANCHOR_TOP")
    GameTooltip:SetText(card.name:GetText() or "Rare", 1, 1, 1)
    GameTooltip:AddLine("Right-click to close it.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function CardLeave()
    GameTooltip:Hide()
end

local function BuildAlert()
    holder = CreateFrame("Frame", "NaowhForeverRareAlertHolder", UIParent)
    holder:SetSize(W, H)
    holder:SetFrameStrata("HIGH")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    -- The mover reports offsets in the holder's scaled units.
    holder.mover = ns.UI.AttachMover(holder, "Rare Alert", function(pos)
        local scale = holder:GetScale()
        S.Set("rareAlertPosition", { point = pos.point, relPoint = pos.relPoint, x = pos.x * scale, y = pos.y * scale })
    end, "Completo/Rares", "Completo/Rares:rareAlert")
    alert = NewCard(holder, "NaowhForeverRareAlert")
    alert:SetPoint("CENTER")
    alert:RegisterForClicks("RightButtonUp")
    alert:SetScript("OnClick", CardClicked)
    alert:SetScript("OnEnter", CardEnter)
    alert:SetScript("OnLeave", CardLeave)
    alert.fade = alert:CreateAnimationGroup()
    alert.fadeIn = alert.fade:CreateAnimation("Alpha")
    alert.fadeIn:SetFromAlpha(0)
    alert.fadeIn:SetToAlpha(1)
    alert.fadeIn:SetDuration(FADE)
    alert.fadeIn:SetOrder(1)
    alert.fadeOut = alert.fade:CreateAnimation("Alpha")
    alert.fadeOut:SetFromAlpha(1)
    alert.fadeOut:SetToAlpha(0)
    alert.fadeOut:SetDuration(FADE)
    alert.fadeOut:SetOrder(2)
    alert.fade:SetScript("OnFinished", HideAlert)
    alert:Hide()
    Place()
end

local function PlayAlertSound()
    if S.Get("rareSound") then PlaySoundKey(S.Get("rareSoundKey")) end
end

-- seen: { name, level (or nil), npc (its npcID, or nil), guid and unit (the creature and its unit
-- token while in sight), elite, tapped, marked (the raid mark's index that went on it), map, x, y (where the minimap saw
-- it, percent) }. quiet: Unlock Mode's preview, with no fade, sound or taskbar flash. Only a
-- real alert with Rare Alerts on follows its rare (its tap state, its kill).
local function ShowAlert(seen, quiet)
    if not alert then BuildAlert() end
    local npc = seen.npc
    local track = not quiet and On()
    shownNpc, shownGuid = track and npc or nil, track and seen.guid or nil
    alert.preview = quiet == true
    if npc and R.Known(npc) then
        if seen.elite == nil then seen.elite = R.Elite(npc) end
        seen.record = R.Record(npc) or false
    end
    alert.seen = seen
    SetPortrait(alert, seen.unit, npc)
    Paint(alert, seen)
    Place()
    alert.fade:Stop()
    alert:Show()
    if track then events:RegisterEvent("UNIT_FLAGS") else events:UnregisterEvent("UNIT_FLAGS") end
    if quiet then return end
    alert.fadeIn:SetFromAlpha(0)
    alert.fadeOut:SetStartDelay(S.Get("rareAlertTime"))
    alert.fade:Play()
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
local function Mark(unit, guid, denied)
    local marker = Marker()
    if not marker or marked[guid] or not MayMark() then return nil end
    local index = GetRaidTargetIndex(unit)
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

-- The alerted creature seen while the card is up: someone tapping it after the card came up,
-- or the rare seen at last after a minimap mark, shows on the card.
local function Retap(unit)
    local denied = UnitIsTapDenied(unit)
    if Secret(denied) then return end
    local seen = alert.seen
    if (seen.tapped == true) == (denied == true) then return end
    seen.tapped = denied or nil
    Paint(alert, seen)
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
    if npc == shownNpc then
        shownGuid = shownGuid or guid
        if guid == shownGuid then Retap(unit) end
    end
    local name, level = UnitName(unit), UnitLevel(unit)
    if Secret(name) then return end
    if Secret(level) then level = nil end
    if not Due(npc, npc) then return end
    local denied = UnitIsTapDenied(unit)
    local skull = Mark(unit, guid, denied)
    Alert(npc, { name = name, level = level, npc = npc, guid = guid, unit = unit, elite = kind == "rareelite",
        marked = skull, tapped = not Secret(denied) and denied or nil })
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
    local name, level, npc, skull, unit, creature = "Mist Howler", 22, 10644, nil, nil, nil
    local guid = UnitGUID("target")
    local hostile = UnitExists("target") and UnitCanAttack("player", "target")
    if guid and not Secret(guid) and not Secret(hostile) and hostile then
        local targetName, targetLevel = UnitName("target"), UnitLevel("target")
        if not Secret(targetName) then
            name = targetName
            level = not Secret(targetLevel) and targetLevel or nil
            npc = R.NpcOf(guid)
            unit, creature = "target", guid
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
    ShowAlert({ name = name, level = level, npc = npc, guid = creature, unit = unit, marked = skull })
end

events:SetScript("OnEvent", function(_, event, unit, onMinimap)
    if event == "UNIT_FLAGS" then
        if not shownGuid then return end
        local guid = UnitGUID(unit)
        if Secret(guid) or guid ~= shownGuid then return end
        local dead = UnitIsDead(unit)
        if not Secret(dead) and not dead then Retap(unit) end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Check(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Check("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Check("mouseover")
    elseif event == "VIGNETTE_MINIMAP_UPDATED" then
        if onMinimap and not Secret(unit) then CheckVignette(unit) end
    end
end)

-- rareAlertPos was the card's own spot before the HUD Editor placed it: the same CENTER offset
-- in the screen's units, so it carries over as it is.
local function Migrate()
    local db = S.DB()
    local old = db.rareAlertPos
    if old == nil then return end
    if type(old) == "table" and db.rareAlertPosition == nil then
        db.rareAlertPosition = { point = "CENTER", relPoint = "CENTER", x = old.x, y = old.y }
    end
    db.rareAlertPos = nil
end

local function Apply()
    Migrate()
    -- A profile switch or import can bring another spot or size.
    if holder then Place() end
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
    if shownNpc then events:RegisterEvent("UNIT_FLAGS") end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "rareAlert" then Apply() end
    if key == "rareAlertScale" and holder then Place() end
    if key == "rareAlertTime" and alert and alert.fade:IsPlaying() then
        alert.fade:Stop()
        alert.fadeIn:SetFromAlpha(1)
        alert.fadeOut:SetStartDelay(S.Get("rareAlertTime"))
        alert.fade:Play()
    end
    if alert and alert:IsShown() and key:find("^rareAlert") and key ~= "rareAlertPosition" then
        Paint(alert, alert.seen)
    end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if not On() then return end
    if not (alert and alert:IsShown()) then
        ShowAlert({ name = "Mist Howler", level = 22, npc = 10644, marked = Marker() }, true)
    end
    holder.mover:Show()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    if not alert then return end
    holder.mover:Hide()
    if alert.preview then HideAlert() end
end)

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

-- The preview: the card as it will look, at its size unless the stage is too narrow, in the
-- moment picked.
local STAGE_H = 110
local CARD_ROOM = 32          -- the least room left beside the card when the stage is narrow
local CARD_ROOM_V = 8         -- and above and below it, its glow ring counted in
local FALLBACK_STAGE_W = 600  -- the stage before layout has run
local STATES = {
    { key = "new", label = "Not Killed", tip = "A rare you have not killed yet." },
    { key = "killed", label = "Killed Before", tip = "A rare you have killed before." },
    { key = "tapped", label = "Tapped", tip = "A rare someone else is fighting." },
}
local SAMPLE_RECORD = { n = 1 }

local PREVIEW_NPC = 10644

-- A model set while the stage had no size, or dropped while the settings were shut, comes back.
local function PreviewShown(preview)
    SetPortrait(preview.card, nil, PREVIEW_NPC)
end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.card = NewCard(preview)
    preview.card:EnableMouse(false)
    preview.card.pin:EnableMouse(false)
    preview.seen = {}
    preview:SetScript("OnShow", PreviewShown)
    PreviewShown(preview)
    return preview
end

local function PaintPreview(preview, state)
    local seen = preview.seen
    seen.name, seen.level, seen.npc, seen.marked = "Mist Howler", 22, PREVIEW_NPC, Marker()
    seen.elite = R.Known(PREVIEW_NPC) and R.Elite(PREVIEW_NPC)
    seen.record = state == "killed" and SAMPLE_RECORD or false
    seen.tapped = state == "tapped" or nil
    seen.map, seen.x, seen.y = 1440, 50, 40
    local card = preview.card
    if not card.model:GetModelFileID() then PreviewShown(preview) end
    Paint(card, seen)
    local w, h = preview:GetWidth(), preview:GetHeight()
    if not w or w <= 0 then w = FALLBACK_STAGE_W end
    if not h or h <= 0 then h = STAGE_H end
    card:SetScale(math.min(S.Get("rareAlertScale"), (w - CARD_ROOM) / W, (h - CARD_ROOM_V) / (H + GLOW * 2)))
    card:ClearAllPoints()
    card:SetPoint("CENTER", preview, "CENTER", 0, 0)
end

Settings.Page("Completo/Rares", S):Card({
    id = "rareAlert", name = "Rare Alerts", order = 20, switch = "rareAlert",
    help = "A warning when a rare is near you: when its nameplate comes up, you mouse over it or target "
        .. "it. A card with its portrait: right-click it to close it, and its pin sets a waypoint to the "
        .. "rare. Move it in the HUD Editor.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Settings.Group("Alert"),
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
        { key = "rareAlertTime", label = "Stays For", slider = { 5, 60, 1 }, unit = "s", needs = Enabled, why = OFF,
          help = "Seconds before it fades." },
        { key = "rareAlertScale", label = "Size", slider = { 50, 200, 5 }, unit = "%", scale = 0.01,
          needs = Enabled, why = OFF, help = "How big the card is." },
        { label = "Reset Position", buttonText = "Reset", needs = Enabled, why = OFF,
          button = function()
              S.Set("rareAlertPosition", nil)
              if holder then Place() end
          end,
          help = "Puts the card back above the middle of the screen, where it starts." },
        { label = "Test Alert", buttonText = "Test", button = TestAlert, needs = Enabled, why = OFF,
          help = "Shows the warning on screen with its sound. With something you can attack targeted, it is "
              .. "about that, with Mark Rare's mark on it." },
        Settings.Look("rareAlert", { text = true, size = { 10, 20, 1 }, background = "card", needs = Enabled,
            why = OFF }),
        { key = "rareAlertGlow", label = "Glow", toggle = true, needs = Enabled, why = OFF,
          help = "A soft glow round it in your accent colour." },
    },
})
