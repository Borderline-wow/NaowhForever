-- Run with Lua 5.1 from the repository root: a zone's levels and Fishing skill on the world
-- map's label. The levels go after the zone's name (only where the game writes none) and come
-- back each time the game writes the plain name; the Fishing range runs from 95 under the
-- no-getaway skill (never under 1) to that skill, coloured by your skill with gear, on the line
-- under the name. Both show only under a zone's own name, are worked out again only when the
-- name changes, and nothing is hooked or shown while both switches are off, which they start as.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local settings = { enabled = true, mapZoneLevels = false, mapFishing = false }
local S = { Get = function(key) return settings[key] end, Set = function() end }
local cards = {}
local ns = {
    QoLSettings = S,
    Apply = function() end,
    Color = function(c, text) return "<" .. c .. ">" .. text end,
    Shared = { Settings = { Page = function() return { Card = function(_, c) cards[c.id] = c end } end } },
}

-- A world map label as the game builds it, with the hooks run as the game runs them.
local hooks = {}
local function Hook(t, name, fn)
    if t == S or t == ns then return end
    hooks[#hooks + 1] = { t = t, name = name, fn = fn }
end
local function FontString()
    local fs = {}
    function fs:SetText(v) self.value = v end
    function fs:GetText() return self.value end
    function fs:SetPoint() end
    return fs
end
local label = { labelInfoByType = {}, Name = FontString(), Description = FontString() }
function label:EvaluateLabels()
    for _, h in ipairs(hooks) do if h.t == self and h.name == "EvaluateLabels" then h.fn(self) end end
end
local created = 0
local ourText
local cursorZone, lookups = 1411, 0
local gameLevels = {}
local fishing = { rank = 120, modifier = 10 }
local playerLevel = 12
local boot
local env = setmetatable({
    _G = { NaowhForever = ns },
    MAP_AREA_LABEL_TYPE = { AREA_NAME = 3, POI = 4 },
    QuestDifficultyColors = { trivial = "grey", impossible = "red", difficult = "yellow", standard = "green" },
    GetQuestDifficultyColor = function(level) return "quest" .. level end,
    UnitLevel = function() return playerLevel end,
    PROFESSIONS_FISHING = "Fishing",
    GetProfessions = function() return 1, 2, 3, fishing and 4 or nil, 5 end,
    GetProfessionInfo = function(index)
        assert(index == 4, "reads the Fishing slot")
        return "Fishing", 1, fishing.rank, 300, 0, 0, 356, fishing.modifier
    end,
    WorldMapFrame = {
        dataProviders = { [{}] = true, [{ Label = label }] = true },
        GetMapID = function() return 1414 end,
        GetNormalizedCursorPosition = function() return 0.5, 0.5 end,
    },
    C_Map = {
        GetMapInfoAtPosition = function()
            lookups = lookups + 1
            return cursorZone and { mapID = cursorZone } or { mapID = 1414 }
        end,
        GetMapLevels = function(map) local l = gameLevels[map]; if l then return l[1], l[2] end return 0, 0 end,
    },
    CreateFrame = function(_, _, parent)
        if parent == label then
            created = created + 1
            return { SetAllPoints = function() end,
                CreateFontString = function() ourText = FontString(); return ourText end }
        end
        return { RegisterEvent = function() end, SetScript = function(_, _, fn) boot = fn end }
    end,
    hooksecurefunc = Hook,
}, { __index = _G })
local chunk = assert(loadstring(Read("QoL/NaowhForever_ZoneLevels.lua")))
setfenv(chunk, env)
chunk()
local Z = ns.ZoneLevels

-- The levels.
Check(Z.Levels(1411) == "<quest10> (1-10)", "Durotar 1-10, above it: its top end's colour")
Check(Z.Levels(1413) == "<yellow> (10-25)", "the Barrens 10-25, inside it: yellow")
Check(Z.Levels(1452) == "<quest53> (53-60)", "Winterspring 53-60, under it: its low end's colour")
Check(Z.Levels(1454) == nil and Z.Levels(2548) == nil, "none for a capital or Forever's own zones")
gameLevels[1411] = { 1, 10 }
Check(Z.Levels(1411) == nil, "none where the game writes them itself")
gameLevels[1411] = nil

-- The Fishing range.
local function Range(map) return table.concat({ Z.Range(map) }, "-") end
Check(Range(1411) == "1-25", "Durotar: 1 to 25")
Check(Range(1413) == "1-75", "the Barrens: 1 to 75")
Check(Range(1440) == "55-150", "Ashenvale: 55 to 150")
Check(Range(1434) == "130-225", "Stranglethorn: 130 to 225")
Check(Range(1444) == "205-300", "Feralas: 205 to 300")
Check(Range(1452) == "330-425", "Winterspring: 330 to 425")
Check(Z.Range(1427) == nil and Z.Range(2548) == nil, "no line where the numbers are unknown")
Check(Z.MySkill() == 130, "your skill counts gear and lures")
Check(Z.Fishing(1440, nil) == "<grey>Fishing 55-150", "grey without Fishing")
Check(Z.Fishing(1440, 54) == "<red>Fishing 55-150", "red under the lowest skill")
Check(Z.Fishing(1440, 55) == "<yellow>Fishing 55-150", "yellow while a fish can get away")
Check(Z.Fishing(1440, 150) == "<green>Fishing 55-150", "green once none can")

-- Off by default, and free while off.
Check(Read("QoL/NaowhForever_QoL.lua"):find("mapZoneLevels = false, mapFishing = false", 1, true), "both start off")
boot()
Check(created == 0 and #hooks == 0, "nothing built or hooked while off")
Check(cards.mapZoneLevels and cards.mapZoneLevels.switch == "mapZoneLevels", "a card for the levels")
Check(cards.mapFishing and cards.mapFishing.switch == "mapFishing", "a card for Fishing")
Check(cards.mapFishing.summary() == "Your Fishing: 130", "the Fishing card shows your skill")

local function Show(name, description, poi)
    label.labelInfoByType[3] = name and { name = name } or nil
    label.labelInfoByType[4] = poi and { name = poi } or nil
    label.Name:SetText(poi or name or "")
    label.Description:SetText(description)
    label:EvaluateLabels()
end
-- The game sets nothing between frames while nothing changed.
local function Frame() label:EvaluateLabels() end

-- Fishing on: the line under the zone's name.
settings.mapFishing = true
boot()
Check(created == 1 and #hooks == 1 and ourText, "hooks the map's label once on")
Show("Durotar")
Check(ourText:GetText() == "<green>Fishing 1-25" and label.Name:GetText() == "Durotar", "under the name; no levels while off")
Frame(); Frame()
Check(lookups == 1, "worked out once per name")
cursorZone = 1452
Show("Winterspring")
Check(ourText:GetText() == "<red>Fishing 330-425", "a new name, worked out again")
Show("Winterspring", nil, "Everlook")
Check(ourText:GetText() == "", "hidden under another label")
Show("Winterspring", "A description")
Check(ourText:GetText() == "", "hidden when the game writes a line there")
cursorZone = nil
Show("Razor Hill")
Check(ourText:GetText() == "", "nothing for an area inside a zone map")
cursorZone = 1411
Show(nil)
Check(ourText:GetText() == "", "nothing off the map")

-- Levels on too: after the name, and back after the game writes the plain name again.
settings.mapZoneLevels = true
boot()
Check(created == 1 and #hooks == 1, "not hooked twice")
lookups = 0
Show("Durotar")
Check(label.Name:GetText() == "Durotar<quest10> (1-10)", "the levels after the name")
Frame(); Frame()
Check(lookups == 1 and label.Name:GetText() == "Durotar<quest10> (1-10)", "kept, worked out once")
Show("Durotar")
Check(label.Name:GetText() == "Durotar<quest10> (1-10)" and lookups == 1, "put back on the plain name")
Check(ourText:GetText() == "<green>Fishing 1-25", "both at once")
Show("Durotar", nil, "Razor Hill")
Check(label.Name:GetText() == "Razor Hill", "another label's name left alone")
gameLevels[1411] = { 1, 10 }
Show("Durotar (1-10)")
Check(label.Name:GetText() == "Durotar (1-10)", "not twice where the game writes them")
gameLevels[1411] = nil

-- Fishing off, levels on.
settings.mapFishing = false
boot()
fishing = nil
Show("Durotar")
Check(ourText:GetText() == "" and label.Name:GetText() == "Durotar<quest10> (1-10)", "levels alone")

-- Both off: the plain name back, nothing added, nothing built again.
settings.mapZoneLevels = false
boot()
Check(label.Name:GetText() == "Durotar", "the plain name put back")
Show("Durotar")
Check(ourText:GetText() == "" and label.Name:GetText() == "Durotar", "nothing added while off")
Check(created == 1 and #hooks == 1, "nothing built again")

-- Loaded by the TOC.
Check(Read("NaowhForever.toc"):find("QoL\\NaowhForever_ZoneLevels.lua", 1, true), "in the TOC")

print(("test-zone-levels: %d checks passed"):format(checks))
