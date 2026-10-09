-------------------------------------------------------------------------------
--  NaowhForever_ZoneLevels.lua -- what a zone asks of you, on the world map's label when you
--  point at it on a continent map: its levels after its name ("Durotar (1-10)") and the
--  Fishing skill under it ("Fishing 1-25"), each on its own switch and coloured against you.
--
--  Free while off: the map's label is hooked the first time either switch is on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local GAP = -6       -- below the zone's name, where the game puts a label's second line
local GETAWAY = 95   -- a zone's lowest skill to fish sits this far under its no-getaway skill

-- Each zone's levels, by zone map. Capitals and Forever's own zones are left out.
local LEVELS = {
    [1411] = { 1, 10 }, [1412] = { 1, 10 }, [1420] = { 1, 10 }, [1426] = { 1, 10 }, [1429] = { 1, 10 },
    [1438] = { 1, 10 },
    [1413] = { 10, 25 }, [1421] = { 10, 20 }, [1432] = { 10, 20 }, [1436] = { 10, 20 }, [1439] = { 10, 20 },
    [1433] = { 15, 25 }, [1442] = { 15, 27 }, [1431] = { 18, 30 }, [1440] = { 18, 30 },
    [1424] = { 20, 30 }, [1437] = { 20, 30 }, [1441] = { 25, 35 },
    [1416] = { 30, 40 }, [1417] = { 30, 40 }, [1443] = { 30, 40 }, [1434] = { 30, 45 },
    [1418] = { 35, 45 }, [1435] = { 35, 45 }, [1445] = { 35, 45 },
    [1425] = { 40, 50 }, [1444] = { 40, 50 }, [1446] = { 40, 50 },
    [1427] = { 45, 50 }, [1419] = { 45, 55 }, [1447] = { 45, 55 }, [1448] = { 48, 55 }, [1449] = { 48, 55 },
    [1428] = { 50, 58 }, [1422] = { 51, 58 }, [1423] = { 53, 60 }, [1452] = { 53, 60 },
    [1430] = { 55, 60 }, [1450] = { 55, 60 }, [1451] = { 55, 60 },
}

-- The skill no fish gets away at, by zone map. Zones with no water to fish are left out, and
-- so are Forever's own zones until their numbers are known.
local NO_GETAWAY = {
    -- Starting zones
    [1411] = 25, [1412] = 25, [1420] = 25, [1426] = 25, [1429] = 25, [1438] = 25,
    -- Level 10-20 zones and the capitals
    [1413] = 75, [1421] = 75, [1432] = 75, [1436] = 75, [1439] = 75,
    [1453] = 75, [1454] = 75, [1455] = 75, [1456] = 75, [1457] = 75, [1458] = 75,
    -- Ashenvale, Duskwood, Hillsbrad, Redridge, Stonetalon, Wetlands
    [1424] = 150, [1431] = 150, [1433] = 150, [1437] = 150, [1440] = 150, [1442] = 150,
    -- Alterac, Arathi, Stranglethorn, Swamp of Sorrows, Thousand Needles, Desolace, Dustwallow
    [1416] = 225, [1417] = 225, [1434] = 225, [1435] = 225, [1441] = 225, [1443] = 225, [1445] = 225,
    -- Western Plaguelands, Hinterlands, Feralas, Tanaris, Azshara, Felwood, Un'Goro, Moonglade
    [1422] = 300, [1425] = 300, [1444] = 300, [1446] = 300, [1447] = 300, [1448] = 300, [1449] = 300,
    [1450] = 300,
    -- Eastern Plaguelands, Burning Steppes, Deadwind Pass, Silithus, Winterspring
    [1423] = 425, [1428] = 425, [1430] = 425, [1451] = 425, [1452] = 425,
}

local function LevelsOn() return S.Get("enabled") and S.Get("mapZoneLevels") end
local function FishingOn() return S.Get("enabled") and S.Get("mapFishing") end

-------------------------------------------------------------------------------
--  Zone levels
-------------------------------------------------------------------------------
-- " (1-10)" for a zone, or nil where the game already writes its levels or none are known.
-- Yellow while you are inside the range, else the game's colour for a quest of its nearest end.
local function Levels(mapID)
    local gameLow = C_Map.GetMapLevels(mapID)
    if gameLow and gameLow > 0 then return nil end
    local range = LEVELS[mapID]
    if not range then return nil end
    local low, high = range[1], range[2]
    local mine = UnitLevel("player")
    local color = mine < low and GetQuestDifficultyColor(low) or mine > high and GetQuestDifficultyColor(high)
        or QuestDifficultyColors.difficult
    return ns.Color(color, (" (%d-%d)"):format(low, high))
end

-------------------------------------------------------------------------------
--  Fishing
-------------------------------------------------------------------------------
-- The lowest skill that can fish in a zone and the skill no fish gets away at.
local function Range(mapID)
    local high = NO_GETAWAY[mapID]
    if high then return math.max(1, high - GETAWAY), high end
end

-- Your Fishing skill with gear and lures, or nil without Fishing.
local function MySkill()
    local fishing = select(4, GetProfessions())
    if not fishing then return nil end
    local _, _, rank, _, _, _, _, modifier = GetProfessionInfo(fishing)
    return (rank or 0) + (modifier or 0)
end

-- Red while you cannot fish there, yellow while a fish can still get away, green once none can,
-- grey without Fishing.
local function Fishing(mapID, skill)
    local low, high = Range(mapID)
    if not low then return nil end
    local color = not skill and "trivial" or skill < low and "impossible" or skill < high and "difficult"
        or "standard"
    return ns.Color(QuestDifficultyColors[color], ("%s %d-%d"):format(PROFESSIONS_FISHING or "Fishing", low, high))
end

ns.ZoneLevels = { Levels = Levels, Range = Range, Fishing = Fishing, MySkill = MySkill }

-------------------------------------------------------------------------------
--  The world map's area label
-------------------------------------------------------------------------------
local label, text
local shownFor     -- the zone name the label showed when ours were last worked out
local withLevels   -- that name with its levels after it, or nil

-- The label frame the game's area label provider made for the world map.
local function FindLabel()
    for provider in pairs(WorldMapFrame.dataProviders or {}) do
        if type(provider) == "table" and provider.Label and provider.Label.labelInfoByType then
            return provider.Label
        end
    end
end

-- The zone under the cursor: the label names one only on a continent or the world map.
local function HoveredZone()
    local mapID = WorldMapFrame:GetMapID()
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    local info = mapID and x and C_Map.GetMapInfoAtPosition(mapID, x, y)
    if info and info.mapID ~= mapID then return info.mapID end
end

-- After the label is worked out each frame: ours while it shows a zone's name with nothing under
-- it, worked out again only when the name changes, the levels put back each time the game
-- writes the plain name again.
local function Update()
    local name
    if LevelsOn() or FishingOn() then
        local area = label.labelInfoByType[MAP_AREA_LABEL_TYPE.AREA_NAME]
        local shown = label.Name:GetText()
        name = area and area.name
        if (shown ~= name and shown ~= withLevels) or (label.Description:GetText() or "") ~= "" then name = nil end
    end
    if name ~= shownFor then
        shownFor, withLevels = name, nil
        local zone = name and HoveredZone()
        text:SetText(zone and FishingOn() and Fishing(zone, MySkill()) or "")
        local levels = zone and LevelsOn() and Levels(zone)
        if levels then withLevels = name .. levels end
    end
    if withLevels and label.Name:GetText() ~= withLevels then label.Name:SetText(withLevels) end
end

local function Apply()
    if not label then
        if not (LevelsOn() or FishingOn()) then return end
        label = FindLabel()
        if not label then return end
        local holder = CreateFrame("Frame", nil, label)
        holder:SetAllPoints()
        text = holder:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
        text:SetPoint("TOP", label.Name, "BOTTOM", 0, GAP)
        hooksecurefunc(label, "EvaluateLabels", Update)
    end
    if withLevels and label.Name:GetText() == withLevels then label.Name:SetText(shownFor) end
    shownFor, withLevels = nil, nil
    text:SetText("")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "mapZoneLevels" or key == "mapFishing" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local page = ns.Shared.Settings.Page("QoL/Interface", S)
page:Card({
    id = "mapZoneLevels", name = "Zone Levels", order = 47, switch = "mapZoneLevels",
    help = "Shows each zone's level range after its name on the world map.",
})
page:Card({
    id = "mapFishing", name = "Fishing Levels", order = 48, switch = "mapFishing",
    help = "Shows the Fishing skill a zone needs under its name on the world map.",
    summary = function()
        local skill = MySkill()
        return skill and ("Your Fishing: %d"):format(skill) or "You have no Fishing"
    end,
})
