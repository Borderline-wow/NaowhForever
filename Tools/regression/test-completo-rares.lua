-- Run with Lua 5.1 from the repository root: Completo's Rares. A rare friendly to your faction
-- is not yours; a zone counts the ones you killed; a targeted rare dying counts once when it was
-- yours and not when someone else tapped it; a looted corpse counts; Shift-click ticks one off.
-- Rare Alerts: a rare's nameplate brings the alert and its mark (a skull, or another picked), once per rare in a while; not
-- for a dead or friendly one, nor one you killed unless Alert for Killed Rares; no skull where it has
-- a mark, on one someone else tapped or in a raid without lead or assist; Unlock Mode's preview shows
-- the picked mark; nothing is registered while it is off.

local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local function Strsplit(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
    return unpack(out)
end

local function Region()
    local r = { shown = true, text = "" }
    function r:SetText(t) self.text = t or "" end
    function r:GetText() return self.text end
    function r:GetStringWidth() return #self.text * 7 end
    function r:GetStringHeight() return 14 end
    function r:SetShown(on) self.shown = on and true or false end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:CreateTexture() return Region() end
    function r:SetTexture(t) self.texture = t end
    function r:GetFrameLevel() return 5 end
    -- Where it is: its middle, in its own units (scale), and the screen's (UIParent's).
    r.scale = 1
    function r:SetScale(s) self.scale = s end
    function r:GetScale() return self.scale end
    function r:GetEffectiveScale() return self.scale end
    function r:GetCenter() return 410.4 / self.scale, 619.6 / self.scale end
    function r:SetPoint(_, _, _, x, y) self.at = { x, y } end
    -- A portrait model: what it was last set to show.
    function r:ClearModel() self.unit, self.creature = nil, nil end
    function r:SetUnit(unit) self.unit = unit end
    function r:SetCreature(npc) self.creature = npc end
    function r:SetScript(k, fn) self[k] = fn end
    -- Every other drawing call (a method: a capital first letter) does nothing.
    return setmetatable(r, { __index = function(_, key)
        if key:find("^%u") then return function() end end
    end })
end

local function Fixture(settings, units)
    local env = { pairs = pairs, ipairs = ipairs, type = type, math = math, table = table, select = select,
        tostring = tostring, tonumber = tonumber, string = string, wipe = function(t)
            for k in pairs(t) do t[k] = nil end
            return t
        end }
    env.strsplit = Strsplit
    env.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    local now = 1000
    env.time = function() return now end
    env.GetTime = function() return now end
    env.Advance = function(s) now = now + s end
    local frames = {}
    env.CreateFrame = function()
        local f = Region()
        f.events, f.unitEvents = {}, {}
        function f:RegisterForClicks() end
        function f:RegisterEvent(e) self.events[e] = true end
        function f:RegisterUnitEvent(e, unit) self.events[e] = true; self.unitEvents[e] = unit end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:UnregisterAllEvents() self.events = {} end
        function f:SetScript(k, fn) self[k] = fn end
        f.CreateAnimationGroup = function()
            local none = function() end
            local g = { playing = false, SetLooping = none, SetScript = none }
            g.Play = function(group) group.playing = true end
            g.Stop = function(group) group.playing = false end
            g.CreateAnimation = function()
                return { SetFromAlpha = none, SetToAlpha = none, SetDuration = none, SetSmoothing = none }
            end
            return g
        end
        frames[#frames + 1] = f
        return f
    end
    -- Every frame listening for the event hears it.
    env.Fire = function(event, ...)
        for _, f in ipairs(frames) do
            if f.events[event] and f.OnEvent then f.OnEvent(f, event, ...) end
        end
    end
    env.Listening = function(event)
        for _, f in ipairs(frames) do
            if f.events[event] then return true end
        end
        return false
    end
    env.hooksecurefunc = function(t, key, fn)
        local orig = t[key]
        t[key] = function(...) orig(...); fn(...) end
    end
    env.UnitName = function(unit) return units[unit] and units[unit].name or "Grim" end
    env.GetRealmName = function() return "Realm" end
    env.UnitFactionGroup = function() return "Horde" end
    env.UnitGUID = function(unit) return units[unit] and units[unit].guid end
    env.UnitExists = function(unit) return units[unit] ~= nil end
    env.UnitIsDead = function(unit) return units[unit] and units[unit].dead or false end
    env.UnitIsTapDenied = function(unit) return units[unit] and units[unit].denied or false end
    env.UnitClassification = function(unit) return units[unit] and units[unit].kind or "normal" end
    env.UnitCanAttack = function(_, unit) return not (units[unit] and units[unit].friend) end
    env.UnitLevel = function(unit) return units[unit] and units[unit].level or 20 end
    env.IsInGroup = function() return units.group ~= nil end
    env.IsInRaid = function() return units.group == "raid" end
    env.UnitIsGroupLeader = function() return false end
    env.UnitIsGroupAssistant = function() return false end
    env.marks = {}
    env.GetRaidTargetIndex = function(unit) return units[unit] and units[unit].mark end
    env.SetRaidTarget = function(unit, index)
        env.marks[#env.marks + 1] = { unit, index }
        units[unit].mark = index
    end
    env.loot = {}
    env.GetNumLootItems = function() return #env.loot end
    env.GetLootSourceInfo = function(slot) return env.loot[slot], 1 end
    env.lootLinks = {}
    env.GetLootSlotLink = function(slot) return env.lootLinks[slot] end
    env.sounds = 0
    env.PlaySound = function() env.sounds = env.sounds + 1 end
    env.PlaySoundFile = function(file) env.soundFile = file; env.sounds = env.sounds + 1 end
    env.SOUNDKIT = { RAID_WARNING = 8959 }
    env.C_Timer = { NewTimer = function() return { Cancel = function() end } end }
    env.C_Map = { GetBestMapForUnit = function() return 1440 end, GetMapInfo = function() end }
    env.vignettes = {}
    env.C_VignetteInfo = { GetVignetteInfo = function(id) return env.vignettes[id] end }
    local account = {}
    env.IsInInstance = function() return units.instance == true end
    env.InCombatLockdown = function() return units.combat == true end
    local ns = { THEME = { accent = {}, muted = {}, fg = {}, panel = {}, accentSoft = {} }, Apply = function() end,
        ShowRaidReminderAnchorConfig = function() end, HideRaidReminderAnchorConfig = function() end }
    ns.AccountSettings = function() return account end
    ns.Font = function() return Region() end
    ns.Solid = function() return Region() end
    ns.Border = function() end

    env.waypoints = {}
    ns.PlaceWaypoint = function(name, map, x, y) env.waypoints[#env.waypoints + 1] = { name, map, x, y } end
    env.UIParent = Region()
    env.UIParent.GetCenter = function() return 400, 500 end
    -- The card, by its frame name.
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, ...)
        local f = create(kind, name, ...)
        if name == "NaowhForeverRareAlert" then ns.alert = f end
        if name == "NaowhForeverRareMapPanel" then ns.mapPanel = f end
        return f
    end
    ns.UI = { SoundPathFor = function() return nil end, _PlayLSMSound = function() end }
    ns.SoundChoices = function()
        return {}, { ["voice:move-out"] = "Move out", ["lsm:BugSack: Fatality"] = "BugSack: Fatality",
            ["lsm:Bell"] = "Bell" }, { "voice:move-out", "lsm:BugSack: Fatality", "lsm:Bell" }
    end
    ns.CompletoSettings = { Get = function(k) return settings[k] end, Set = function(k, v) settings[k] = v end }
    ns.Completo = {}
    -- The settings pages' cards, by id, to reach their rows.
    ns.cards = {}
    local page = { Window = function() end, Card = function(_, spec) ns.cards[spec.id] = spec end }
    ns.Shared = { Settings = { Page = function() return page end }, Style = { PIN = "pin" },
        -- Per character, by the player's GUID.
        CharacterData = function(key)
            account[key] = account[key] or {}
            account[key]["Player-1-0001"] = account[key]["Player-1-0001"] or {}
            return account[key]["Player-1-0001"]
        end,
        -- Forever's sign, as text.
        -- The pin button: its click.
        Parts = { ForeverInline = function() return " <inf>" end, IconButton = function(_, onClick)
            local button = Region()
            button.OnClick = onClick
            return button
        end } }
    -- Ashenvale: Mist Howler; Darkslayer Mordenthal, friendly to the Horde; Ursol'lok.
    ns.CompletoRareData = {
        Zones = { { map = 1440, name = "Ashenvale", continent = 1, rares = { 10644, 3736, 12037, 10647 } } },
        Rares = {
            [3736] = { "Darkslayer Mordenthal", 23, 23, 0, -1, 1, 1440, { 60.0, 70.0 } },
            [10644] = { "Mist Howler", 22, 22, 0, -1, -1, 1440, { 50.0, 40.0, 52.0, 44.0 } },
            [12037] = { "Ursol'lok", 31, 31, 0, -1, -1, 1440, {} },
            -- Patrols: a star on its way, three dots along it.
            [10647] = { "Prince Raze", 32, 32, 0, -1, -1, 1440, { 70.0, 20.0 }, { 68.0, 20.0, 70.0, 22.0, 72.0, 24.0 } },
        },
        -- Prince Raze: a blue of his own, a recipe, and more; Mist Howler: nothing special.
        Loot = {
            [10647] = { { 4454, 3, 22.2, "Talon of Vultros" }, { 5971, 2, 0.4, "Pattern: Feathered Cape" },
                { 285330, 3, 4.3, "Signet of the Zhevra", 1 }, more = 3 },
        },
    }
    ns.ThemeTint = function() return nil end
    env.CreateFromMixins = function(...)
        local out = {}
        for i = 1, select("#", ...) do
            for k, v in pairs((select(i, ...))) do out[k] = v end
        end
        return out
    end
    env.MapCanvasPinMixin = { UseFrameLevelType = function(pin, _, index) pin.levelIndex = index end }
    env.MapCanvasDataProviderMixin = {}
    -- The world map, open on Ashenvale: pins made from the template's mixin, kept by template.
    local map = { pins = {} }
    function map:GetMapID() return 1440 end
    function map:RemoveAllPinsByTemplate() self.pins = {} end
    function map:RemovePin(pin)
        for i = #self.pins, 1, -1 do
            if self.pins[i] == pin then table.remove(self.pins, i) end
        end
    end
    function map:EnumeratePinsByTemplate()
        local i = 0
        return function()
            i = i + 1
            return self.pins[i]
        end
    end
    function map:AcquirePin(_, data)
        local pin = env.CreateFromMixins(env.NaowhForeverRarePinMixin)
        local icon = { atlas = nil, desaturated = false }
        function icon.SetAtlas(t, atlas) t.atlas = atlas; return true end
        function icon.SetTexture() end
        function icon.SetDesaturated(t, on) t.desaturated = on end
        function icon.SetAlpha(t, a) t.alpha = a end
        pin.Icon = icon
        pin.SetSize = function(p, w) p.size = w end
        pin.EnableMouse = function(p, on) p.mouse = on end
        pin.SetPosition = function(p, x, y) p.at = { x, y } end
        pin:OnAcquired(data)
        self.pins[#self.pins + 1] = pin
        return pin
    end
    env.WorldMapFrame = { IsShown = function() return true end }
    local none = function() end
    env.IsShiftKeyDown = function() return env.shift == true end
    -- The tooltip's lines, as shown last.
    env.tip = {}
    env.GameTooltip = { SetOwner = function(_, owner) env.tip, env.tipOwner = {}, owner end, SetText = none, Show = function() env.tipHidden = false end,
        Hide = function() env.tipHidden = true end,
        AddLine = function(_, text, r, g, b) env.tip[#env.tip + 1] = { text, nil, r, g, b } end,
        SetItemByID = function(_, id) env.tipItem = id end,
        AddDoubleLine = function(_, left, right, r, g, b) env.tip[#env.tip + 1] = { left, right, r, g, b } end }
    env.ITEM_QUALITY_COLORS = { [2] = { r = 0.1, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
    env.C_Item = { GetItemIconByID = function(id) return 1000 + id end }
    function env.WorldMapFrame:AddDataProvider(provider)
        provider.GetMap = function() return map end
        env.provider = provider
    end
    env.worldMap = map
    env.NaowhForever = ns
    env._G = env
    Load({ "NaowhForever_Completo/NaowhForever_CompletoRares.lua",
        "NaowhForever_Completo/NaowhForever_CompletoRareAlert.lua",
        "NaowhForever_Completo/NaowhForever_CompletoRareMap.lua" }, env)
    env.Fire("PLAYER_LOGIN")
    return ns, env, account
end

local function Guid(npc, spawn) return ("Creature-0-1-2-3-%d-%s"):format(npc, spawn or "0001") end

-- Kills
do
    local units = {}
    local ns, env, account = Fixture({ enabled = true }, units)
    local R = ns.Completo.Rares
    local zone = R.Zones()[1]
    Check(R.NpcOf(Guid(10644)) == 10644, "the npcID comes from the GUID")
    Check(R.NpcOf("Player-1-0001") == nil, "a player is no creature")
    Check(not R.Mine(3736) and R.Mine(10644), "a rare friendly to the Horde is not a Horde rare")
    local n, total, low, high = R.ZoneProgress(zone)
    Check(n == 0 and total == 3 and low == 22 and high == 32, "the zone counts its three rares for the Horde")

    units.target = { guid = Guid(10644), name = "Mist Howler" }
    env.Fire("PLAYER_TARGET_CHANGED")
    Check(env.Listening("UNIT_HEALTH"), "a targeted rare is watched")
    units.target.dead = true
    env.Fire("UNIT_HEALTH", "target")
    Check(R.Killed(10644) and R.Record(10644).n == 1, "the targeted rare dying counts")
    Check(not env.Listening("UNIT_HEALTH"), "a dead rare is no longer watched")
    env.loot = { Guid(10644) }
    env.Fire("LOOT_READY")
    Check(R.Record(10644).n == 1, "looting the same corpse does not count it again")
    Check(account.completoRareKills["Player-1-0001"][10644] ~= nil, "kills are kept per character, by its GUID")

    units.target = { guid = Guid(10644, "0002"), name = "Mist Howler" }
    env.Fire("PLAYER_TARGET_CHANGED")
    units.target.dead, units.target.denied = true, true
    env.Fire("UNIT_HEALTH", "target")
    Check(R.Record(10644).n == 1, "a rare someone else tapped does not count")

    env.loot = { Guid(12037) }
    env.lootLinks = { "|cff0070dd|Hitem:4454::::::::30:::::|h[Talon of Vultros]|h|r" }
    env.Fire("LOOT_READY")
    Check(R.Killed(12037), "a looted rare counts")
    Check(R.Dropped(12037, 4454) and not R.Dropped(12037, 5971) and not R.Dropped(10644, 4454),
        "the item its loot window had is kept as that rare's drop")
    env.lootLinks = {}
    Check(select(1, R.ZoneProgress(zone)) == 2, "the zone counts both kills")

    local heard = 0
    R.OnChange(function() heard = heard + 1 end)
    R.SetKilled(12037, false)
    Check(not R.Killed(12037) and heard == 1, "Shift-click unticks a rare, and says so")
    R.SetKilled(12037, true)
    Check(R.Killed(12037) and R.Record(12037).n == 0, "ticked off by hand: killed, no kill counted")

    local found, count = R.Search("howl", 10)
    Check(count == 1 and found[1].ids[1] == 10644, "the search finds a rare by name")
    Check(R.CurrentZone() == zone, "the zone you are in")
    local map, x, y = R.Spot(10644)
    Check(map == 1440 and x == 50 and y == 40, "the waypoint goes to its first spot off its map")
end

-- Rare Alerts
do
    local units = {}
    local settings = { enabled = true, rareAlert = false, rareMarker = "skull", rareSound = true,
        rareAlertKilled = false }
    local ns, env = Fixture(settings, units)
    local R = ns.Completo.Rares
    Check(not env.Listening("NAME_PLATE_UNIT_ADDED"), "nothing is registered while Rare Alerts is off")
    ns.CompletoSettings.Set("rareAlert", true)
    Check(env.Listening("NAME_PLATE_UNIT_ADDED"), "on: nameplates are watched")

    units.nameplate1 = { guid = Guid(10644), name = "Mist Howler", kind = "rare", level = 22 }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Check(ns.alert and ns.alert:IsShown(), "a rare's nameplate brings the alert")
    Check(ns.alert.name.text:find("Mist Howler", 1, true), "the alert names it")
    Check(ns.alert.about.text == "Level 22, rare, not killed yet", "its level, kind, and that it is not killed yet")
    Check(ns.alert.model.unit == "nameplate1", "the portrait is its own model")
    Check(ns.alert.skull.shown, "the card shows the skull went on it")
    Check(ns.alert.skull.texture == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", "with the skull's icon")
    Check(ns.alert.glow.pulse.playing, "its glowing border pulses")
    Check(ns.alert.pin.shown, "its pin shows: it has a spot to go to")
    ns.alert.OnClick(ns.alert, "LeftButton")
    Check(#env.waypoints == 0, "a click on the card sets no waypoint")
    ns.alert.pin.OnClick()
    local wp = env.waypoints[1]
    Check(wp and wp[1] == "Mist Howler" and wp[2] == 1440 and wp[3] == 50 and wp[4] == 40,
        "its pin sets a waypoint to its spot")
    ns.alert.OnDragStart(ns.alert)
    ns.alert.OnDragStop(ns.alert)
    Check(type(settings.rareAlertPos) == "table" and settings.rareAlertPos.x == 10 and settings.rareAlertPos.y == 120,
        "a drag keeps the card's spot, from the screen's middle")
    ns.CompletoSettings.Set("rareAlertScale", 2)
    Check(ns.alert.scale == 2 and ns.alert.at[1] == 5 and ns.alert.at[2] == 60,
        "Card Size scales it about the same spot")
    ns.CompletoSettings.Set("rareAlertScale", 1)
    ns.alert.OnClick(ns.alert, "RightButton")
    Check(ns.alert:IsShown(), "letting go after a drag does not close it")
    ns.alert.OnClick(ns.alert, "RightButton")
    Check(not ns.alert:IsShown(), "a right-click puts it away")
    Check(not ns.alert.glow.pulse.playing, "and the glow stops")
    ns.alert:Show()
    Check(#env.marks == 1 and env.marks[1][2] == 8, "a skull goes on it")
    Check(env.sounds == 1, "a sound plays")

    ns.alert:Hide()
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Check(not ns.alert:IsShown() and #env.marks == 1, "its nameplate coming back does not alert or mark again")
    env.Advance(301)
    units.nameplate1.mark = 2
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Check(ns.alert:IsShown() and #env.marks == 1, "a while later it alerts again, the mark left alone")

    R.SetKilled(10644, true)
    Check(not ns.alert:IsShown(), "the alert goes once its rare is killed")

    units.nameplate2 = { guid = Guid(10644, "0003"), name = "Mist Howler", kind = "rare", level = 22 }
    env.Advance(301)
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    Check(not ns.alert:IsShown(), "a rare you killed does not alert")
    Check(#env.marks == 1, "nor gets a skull")
    settings.rareAlertKilled = true
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    Check(ns.alert:IsShown() and ns.alert.about.text:find("killed before", 1, true), "with Alert for Killed Rares it does")
    Check(#env.marks == 2, "and the skull goes on it")

    ns.alert:Hide()
    units.nameplate3 = { guid = Guid(5555), name = "Not A Rare", kind = "normal" }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    units.nameplate4 = { guid = Guid(6666), name = "Dead Rare", kind = "rareelite", dead = true }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
    units.nameplate5 = { guid = Guid(7777), name = "Friendly Rare", kind = "rare", friend = true }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
    Check(not ns.alert:IsShown(), "no alert for a normal mob, a dead rare or a friendly one")

    units.group = "raid"
    units.target = { guid = Guid(8888), name = "Raid Rare", kind = "rareelite", level = 40 }
    env.Fire("PLAYER_TARGET_CHANGED")
    Check(ns.alert:IsShown() and ns.alert.about.text == "Level 40, rare elite",
        "a rare not in the data alerts too, without a kill note")
    Check(not ns.alert.pin.shown, "no pin with no spot to send a waypoint to")
    Check(#env.marks == 2, "in a raid without lead or assist, no skull")
    units.group = nil
    settings.rareMarker = "moon"
    units.nameplate6 = { guid = Guid(9999), name = "Moon Rare", kind = "rare" }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
    Check(#env.marks == 3 and env.marks[3][2] == 5, "Mark Rare: the moon when it is picked")
    Check(ns.alert.skull.texture == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5", "the card shows the moon")
    units.nameplate8 = { guid = Guid(9997), name = "Tapped Rare", kind = "rare", denied = true }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
    Check(ns.alert.name.text:find("Tapped Rare", 1, true) and #env.marks == 3,
        "a rare someone else tapped alerts, but gets no mark")
    ns.alert:Hide()
    ns.ShowRaidReminderAnchorConfig()
    Check(ns.alert:IsShown() and ns.alert.skull.shown and ns.alert.skull.texture == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
        "Unlock Mode previews the card with Mark Rare's mark")
    settings.rareMarker = "none"
    units.nameplate7 = { guid = Guid(9998), name = "Unmarked Rare", kind = "rare" }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
    Check(#env.marks == 3 and not ns.alert.skull.shown, "None: no mark, and none on the card")
    ns.alert:Hide()
    ns.ShowRaidReminderAnchorConfig()
    Check(ns.alert:IsShown() and not ns.alert.skull.shown, "and none on Unlock Mode's preview")

    ns.CompletoSettings.Set("rareAlert", false)
    Check(not env.Listening("NAME_PLATE_UNIT_ADDED") and not ns.alert:IsShown(), "switched off: unregistered, alert gone")
end

-- Mark Rare leaves the group's marks alone
do
    local units = {}
    local settings = { enabled = true, rareAlert = true, rareMarker = "skull", rareSound = false }
    local ns, env = Fixture(settings, units)
    units.group, units.instance = "party", true
    units.nameplate1 = { guid = Guid(10644), name = "Mist Howler", kind = "rare", level = 22 }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Check(ns.alert:IsShown() and #env.marks == 0, "in a party's dungeon: the alert, but no mark")
    units.instance, units.combat = nil, true
    units.nameplate2 = { guid = Guid(10647), name = "Prince Raze", kind = "rare", level = 32 }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    Check(#env.marks == 0, "in a party's fight: no mark")
    units.group, units.combat = nil, nil
    units.party1target = { guid = Guid(5555), name = "Kobold", mark = 8 }
    units.nameplate3 = { guid = Guid(9999), name = "Moon Rare", kind = "rare" }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    Check(#env.marks == 0, "a skull already on something else is not moved onto the rare")
    units.party1target = nil
    units.nameplate4 = { guid = Guid(9998), name = "Other Rare", kind = "rare" }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
    Check(#env.marks == 1 and env.marks[1][1] == "nameplate4", "solo, with the skull free: it goes on")
    units.nameplate5 = { guid = Guid(12037), name = "Ursol'lok", kind = "normal" }
    env.Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
    Check(ns.alert.name.text ~= "Ursol'lok", "a creature the game does not call rare brings no alert")
    env.vignettes.v1 = { objectGUID = Guid(3736), name = "Darkslayer Mordenthal", atlasName = "VignetteKill" }
    env.Fire("VIGNETTE_MINIMAP_UPDATED", "v1", true)
    Check(ns.alert.name.text ~= "Darkslayer Mordenthal", "no minimap alert for a rare friendly to you")
    env.vignettes.v2 = { objectGUID = Guid(10647, "0002"), name = "Prince Raze", atlasName = "VignetteKill" }
    env.Advance(301)
    env.Fire("VIGNETTE_MINIMAP_UPDATED", "v2", true)
    Check(ns.alert.name.text == "Prince Raze", "a hostile rare on the minimap alerts")
end

-- A kill is counted once per creature, a reload in between too
do
    local units = {}
    local ns, env, account = Fixture({ enabled = true }, units)
    local R = ns.Completo.Rares
    account.completoRareKills = { ["Player-1-0001"] = { [10644] = { n = 1, at = 900, guid = Guid(10644, "0007") } } }
    env.loot = { Guid(10644, "0007") }
    env.Fire("LOOT_READY")
    Check(R.Record(10644).n == 1, "a corpse counted before a reload does not count again")
    env.loot = { Guid(10644, "0008") }
    env.Fire("LOOT_READY")
    Check(R.Record(10644).n == 2, "another one of it does")
end

-- Test Alert
do
    local units = {}
    local settings = { enabled = true, rareAlert = false, rareMarker = "skull", rareSound = true }
    local ns, env = Fixture(settings, units)
    local test
    for _, row in ipairs(ns.cards.rareAlert.rows) do
        if row.label == "Test Alert" then test = row.button end
        if row.label == "Card Position" then ns.resetCard = row.button end
    end
    Check(test ~= nil, "Rare Alerts has a Test button")
    settings.rareAlertPos = { point = "TOP", relPoint = "TOP", x = 1, y = 2 }
    ns.resetCard()
    Check(settings.rareAlertPos == nil, "Reset puts the card back where it starts")
    local soundRow
    for _, row in ipairs(ns.cards.rareAlert.rows) do
        if row.key == "rareSoundKey" then soundRow = row end
    end
    local values, order = soundRow.choice()
    Check(order[1] == "file:gruntlinghorn" and values["file:gruntlinghorn"] == "Gruntling Horn (game)"
        and order[2] == "game:raidwarning", "the Gruntling Horn first, then the game's other sounds")
    Check(values["game:legendary"] == nil, "a SOUNDKIT name the client lacks is left out")
    Check(values["game:flaghorde"] == "Flag Taken, Horde (game)", "the flag sounds are offered by their kit ID")
    Check(values["file:thunder"] == nil and values["file:scourgehorn"] == nil and values["file:pvphorde"] == nil,
        "no Thunder Crack, Scourge Horn or PvP warnings")
    Check(soundRow.get() == "file:gruntlinghorn", "the Gruntling Horn by default")
    soundRow.set("file:gruntlinghorn")
    Check(env.soundFile == 598196 and env.sounds == 1, "a sound file plays by its ID")
    env.soundFile = nil
    soundRow.set("game:flaghorde")
    Check(env.sounds == 2 and env.soundFile == nil, "a flag sound plays by its kit ID")
    env.soundFile = nil
    soundRow.set("file:pvphorde")
    Check(env.soundFile == 598196, "a sound no longer offered falls back to the Gruntling Horn")
    env.sounds = 0
    settings.rareSoundKey = nil
    Check(values["voice:move-out"] == nil and values["lsm:BugSack: Fatality"] == nil and values["lsm:Bell"] == "Bell"
        and order[#order] == "lsm:Bell", "no spoken lines or BugSack's sound; the addon's other sounds stay")
    soundRow.set("game:raidwarning")
    Check(env.sounds == 1 and settings.rareSoundKey == "game:raidwarning", "picking a sound plays it")
    env.sounds = 0
    test()
    Check(ns.alert:IsShown() and ns.alert.name.text:find("Mist Howler", 1, true), "with nothing targeted, a made-up rare")
    Check(env.sounds == 1 and #env.marks == 0, "with its sound, and no skull on anything")
    units.target = { guid = Guid(5555), name = "Kobold Miner", level = 7 }
    test()
    Check(ns.alert.name.text:find("Kobold Miner", 1, true) and #env.marks == 1 and env.marks[1][1] == "target",
        "with a hostile target, about it, with a skull on it")
    units.target.friend = true
    units.target.mark = nil
    test()
    Check(#env.marks == 1 and ns.alert.name.text:find("Mist Howler", 1, true), "a friendly target is not marked")
end

-- Map Pins
do
    local units = {}
    local settings = { enabled = true, rarePins = false, rarePinsKilled = false, rarePinSize = 18 }
    local ns, env = Fixture(settings, units)
    local R = ns.Completo.Rares
    Check(env.provider == nil, "no map provider while Map Pins is off")
    Check(ns.cards.rarePins and ns.cards.rarePins.switch == "rarePins", "Rares has a Map Pins card")
    ns.CompletoSettings.Set("rarePins", true)
    local pins = env.worldMap.pins
    Check(#pins == 2, "one star each for Mist Howler and Prince Raze; none for the Horde-friendly rare or one "
        .. "with no spot")
    local function PinsOf(npc, kind)
        local out = {}
        for _, pin in ipairs(env.worldMap.pins) do
            if pin.npc == npc and (kind == nil or pin.kind == (kind or nil)) then out[#out + 1] = pin end
        end
        return out
    end
    local howler = PinsOf(10644)[1]
    Check(howler.Icon.atlas == "VignetteKill" and howler.at[1] == 0.5 and howler.at[2] == 0.4,
        "the game's rare star, at its first spot (where it was seen most)")
    howler:OnMouseEnter()
    local other = PinsOf(10644, "spot")[1]
    Check(#PinsOf(10644, "spot") == 1 and other.at[1] == 0.52 and other.size < howler.size and not other.mouse,
        "hovering it shows its other spot, smaller, taking no mouse")
    howler:OnMouseLeave()
    Check(#PinsOf(10644) == 1, "moving off takes the other spot away")
    local star = PinsOf(10647, false)[1]
    star:OnMouseEnter()
    Check(#env.worldMap.pins == 5 and #PinsOf(10647, "dot") == 3, "hovering a patrolling rare's star shows its way's three dots")
    local dot = PinsOf(10647, "dot")[1]
    Check(dot.size < star.size and dot.levelIndex < star.levelIndex and not dot.mouse,
        "a trail's dots are smaller, under the star and take no mouse")
    Check(star.size > 18 and howler.Icon.alpha < 0.5, "the hovered rare's star is lit, the others faded")
    local function Line(find)
        for _, line in ipairs(env.tip) do
            if tostring(line[1]):find(find, 1, true) then return line end
        end
    end
    local talon = Line("Talon of Vultros")
    Check(Line("Drops") and talon and talon[1] == "|T5454:14:14|t Talon of Vultros" and talon[2] == "22%"
        and talon[5] == 0.87, "its tooltip lists its loot: icon, name in its quality's colour, chance")
    Check(Line("Pattern: Feathered Cape")[2] == "0.4%", "a rare chance keeps its decimal")
    Check(Line("And 3 more"), "and says how many more")
    Check(Line("Signet of the Zhevra <inf>") and not Line("Talon of Vultros <inf>"),
        "Forever's sign on a drop new in Forever, none on the others")
    star:OnMouseLeave()
    howler:OnMouseEnter()
    Check(not Line("Drops"), "a rare with nothing special has no Drops section")
    howler:OnMouseLeave()
    Check(#env.worldMap.pins == 2 and #PinsOf(10647, "dot") == 0, "moving off the star takes its way away")
    Check(star.size == 18 and howler.Icon.alpha == 1, "and puts the others back")
    star:OnClick("RightButton")
    Check(#env.waypoints == 1 and env.waypoints[1][3] == 70, "right-clicking a star sets a waypoint there")
    star:OnClick("LeftButton")
    star:OnMouseLeave()
    Check(#PinsOf(10647, "dot") == 3 and howler.Icon.alpha < 0.5 and #env.waypoints == 1,
        "clicking a star focuses its rare: its way stays and the others stay faded after the pointer leaves")
    local panel = ns.mapPanel
    Check(panel and panel:IsShown() and panel.npc == 10647, "and a panel stays up beside its star")
    Check(panel.rows[1].item[1] == 4454 and panel.rows[3].item[1] == 285330 and panel.rows[3]:IsShown(),
        "with a row for each of its drops")
    Check(panel.rows[3].name.text:find("Signet of the Zhevra <inf>", 1, true), "Forever's sign on the new one")
    panel.rows[1].OnEnter(panel.rows[1])
    Check(env.tipItem == 4454, "hovering a drop shows the item's own tooltip")
    panel.rows[1].OnLeave(panel.rows[1])
    howler:OnMouseEnter()
    Check(#PinsOf(10647, "dot") == 0 and #PinsOf(10644, "spot") == 1, "hovering another rare shows that one meanwhile")
    howler:OnMouseLeave()
    Check(#PinsOf(10647, "dot") == 3 and #PinsOf(10644, "spot") == 0, "and leaving it goes back to the focused one")
    env.provider:RefreshAllData()
    Check(#PinsOf(10647, "dot") == 3, "a redraw keeps the focus")
    star = PinsOf(10647, false)[1]
    star:OnClick("LeftButton")
    star:OnMouseLeave()
    howler = PinsOf(10644)[1]
    Check(#PinsOf(10647, "dot") == 0 and howler.Icon.alpha == 1, "clicking it again lets go")
    Check(not ns.mapPanel:IsShown(), "its panel goes with it")
    R.SetKilled(10644, true)
    Check(#PinsOf(10644) == 0 and #env.worldMap.pins == 1, "a killed rare's star goes")
    ns.CompletoSettings.Set("rarePinsKilled", true)
    Check(#PinsOf(10644) == 1 and PinsOf(10644)[1].Icon.desaturated, "with Show Killed Rares, a grey star")
    ns.CompletoSettings.Set("rarePins", false)
    Check(#env.worldMap.pins == 0, "switched off: the stars go")
end

print(("test-completo-rares: %d checks passed"):format(checks))
