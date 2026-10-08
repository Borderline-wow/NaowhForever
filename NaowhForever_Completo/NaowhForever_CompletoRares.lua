-------------------------------------------------------------------------------
--  NaowhForever_CompletoRares.lua -- Completo's Rares: every rare of every zone
--  (Data/NaowhForever_CompletoRares.lua), which of them this character has killed, and how
--  many per zone. A rare friendly to your faction is left out: you cannot kill it.
--
--  The game keeps no record of the rares you killed, so Completo counts them itself, per
--  character, from then on: a rare you had targeted dying while it was yours (not tapped by
--  someone else), or a corpse you loot. One killed before can be ticked off by hand in the
--  window (Shift-click). What a rare's corpse had for you in its loot window is kept too, so
--  its drops can be ticked. Off while Completo is: no events until it is on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local St = ns.Shared.Style
local S = ns.CompletoSettings
local D = ns.CompletoRareData

local R = {}
ns.Completo.Rares = R

local NAME, LOW, HIGH, ELITE, REACT_A, REACT_H, MAP, SPOTS, TRAIL = 1, 2, 3, 4, 5, 6, 7, 8, 9
local FRIENDLY = 1

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- The creature's npcID from its GUID ("Creature-0-...-<npcID>-<spawn>"), nil for anything else.
function R.NpcOf(guid)
    if type(guid) ~= "string" or Secret(guid) then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

function R.Known(npc) return D.Rares[npc] ~= nil end
function R.Name(npc) return D.Rares[npc][NAME] end
function R.Elite(npc) return D.Rares[npc][ELITE] == 1 end
function R.Map(npc) return D.Rares[npc][MAP] end

---@return number lowest level: 0 when not known, -1 for a boss level ("??")
---@return number highest level
function R.Levels(npc)
    local rare = D.Rares[npc]
    return rare[LOW], rare[HIGH]
end

function R.SpotCount(npc) return #D.Rares[npc][SPOTS] / 2 end

-- Yours to kill: not friendly to your faction.
local mine

local function Prepare()
    if mine then return end
    mine = {}
    local react = UnitFactionGroup("player") == "Horde" and REACT_H or REACT_A
    for npc, rare in pairs(D.Rares) do
        if rare[react] ~= FRIENDLY then mine[npc] = true end
    end
end

function R.Mine(npc)
    Prepare()
    return mine[npc] == true
end

-------------------------------------------------------------------------------
--  Your kills, per character by its GUID (Shared.CharacterData): npcID -> { n = kills
--  counted, at = the latest, as time() gives it, guid = the creature counted last }; n is 0
--  for one ticked off by hand. Looked up once, when the game knows who you are.
-------------------------------------------------------------------------------
local NONE = {}
local kills, drops

local function Kills()
    kills = kills or ns.Shared.CharacterData("completoRareKills", true)
    return kills or NONE
end

local listeners = {}

-- fn(npc) runs whenever a rare is counted or ticked off (the window redraws, the alert hides).
function R.OnChange(fn) listeners[#listeners + 1] = fn end

local function Changed(npc)
    for _, fn in ipairs(listeners) do fn(npc) end
end

function R.Killed(npc) return Kills()[npc] ~= nil end

---@return table? record { n, at }, nil while not killed
function R.Record(npc) return Kills()[npc] end

-- guid: the creature, so its corpse looted again after a reload is not a second kill.
function R.AddKill(npc, guid)
    local all = Kills()
    if all == NONE then return end
    local record = all[npc] or { n = 0 }
    record.n = record.n + 1
    record.at = time()
    record.guid = guid
    all[npc] = record
    Changed(npc)
end

-- Ticked off or back by hand: one killed before Completo counted, or counted by mistake.
function R.SetKilled(npc, killed)
    local all = Kills()
    if all == NONE then return end
    all[npc] = killed and (all[npc] or { n = 0, at = time() }) or nil
    Changed(npc)
end

-- The items each rare dropped for this character: npcID -> { itemID -> time() it first did }.
local function Drops()
    drops = drops or ns.Shared.CharacterData("completoRareDrops", true)
    return drops or NONE
end

-- Whether the rare ever dropped the item for you.
function R.Dropped(npc, itemID)
    local items = Drops()[npc]
    return items ~= nil and items[itemID] ~= nil
end

local function AddDrop(npc, itemID)
    local all = Drops()
    if all == NONE then return end
    all[npc] = all[npc] or {}
    if all[npc][itemID] then return end
    all[npc][itemID] = time()
    Changed(npc)
end

-------------------------------------------------------------------------------
--  Zones
-------------------------------------------------------------------------------
---@return number killed
---@return number total your rares in the zone
---@return number? lowest level
---@return number? highest level
function R.ZoneProgress(zone)
    Prepare()
    local all = Kills()
    local n, total, low, high = 0, 0, nil, nil
    for _, npc in ipairs(zone.rares) do
        if mine[npc] then
            total = total + 1
            if all[npc] then n = n + 1 end
            local lo, hi = R.Levels(npc)
            if lo > 0 then
                low = math.min(low or lo, lo)
                high = math.max(high or hi, hi)
            end
        end
    end
    return n, total, low, high
end

function R.Progress()
    local n, total = 0, 0
    for _, zone in ipairs(D.Zones) do
        local zn, zt = R.ZoneProgress(zone)
        n, total = n + zn, total + zt
    end
    return n, total
end

function R.Zones() return D.Zones end

-- Your rares in the zone, lowest level first (as the data lists them). Reused until the next call.
local list = {}

function R.ZoneList(zone)
    Prepare()
    wipe(list)
    for _, npc in ipairs(zone.rares) do
        if mine[npc] then list[#list + 1] = npc end
    end
    return list
end

local function ZoneFor(map)
    for _, zone in ipairs(D.Zones) do
        if zone.map == map then return zone end
    end
end

R.ZoneFor = ZoneFor

-- The zone you are in, if it has rares: walks up from the map you are on (a cave, a town).
function R.CurrentZone()
    local map = C_Map.GetBestMapForUnit("player")
    while map do
        local zone = ZoneFor(map)
        if zone then return zone end
        local info = C_Map.GetMapInfo(map)
        map = info and info.parentMapID ~= 0 and info.parentMapID or nil
    end
end

function R.Zone(npc) return ZoneFor(D.Rares[npc][MAP]) end

-- Your rares whose name holds the text (lower case, as typed), zone by zone, at most limit:
-- { { zone, ids }, ... } and how many there were in all. Tables reused until the next call.
local found, foundIn, lowered = {}, {}, {}

function R.Search(text, limit)
    Prepare()
    wipe(found)
    local n = 0
    for _, zone in ipairs(D.Zones) do
        local entry = foundIn[zone] or { zone = zone, ids = {} }
        foundIn[zone] = entry
        local ids = wipe(entry.ids)
        for _, npc in ipairs(zone.rares) do
            local name = lowered[npc]
            if not name then
                name = D.Rares[npc][NAME]:lower()
                lowered[npc] = name
            end
            if mine[npc] and name:find(text, 1, true) then
                n = n + 1
                if n <= limit then ids[#ids + 1] = npc end
            end
        end
        if #ids > 0 then found[#found + 1] = entry end
    end
    return found, n
end

local function Nearest(points, px, py, bx, by, bestD)
    for i = 1, #points, 2 do
        local dx, dy = points[i] / 100 - px, points[i + 1] / 100 - py
        local d = dx * dx + dy * dy
        if not bestD or d < bestD then bx, by, bestD = points[i], points[i + 1], d end
    end
    return bx, by, bestD
end

-- Where it spawns nearest to you when you are on its map (a spawn spot, or a dot along the
-- way it patrols), else where it spawns most.
function R.Spot(npc)
    local rare = D.Rares[npc]
    local spots = rare[SPOTS]
    if #spots == 0 then return end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetBestMapForUnit("player") == rare[MAP]
        and C_Map.GetPlayerMapPosition(rare[MAP], "player")
    if not pos then return rare[MAP], spots[1], spots[2] end
    local px, py = pos:GetXY()
    local bx, by, bestD = Nearest(spots, px, py, spots[1], spots[2], nil)
    if rare[TRAIL] then bx, by = Nearest(rare[TRAIL], px, py, bx, by, bestD) end
    return rare[MAP], bx, by
end

-- Its spawn spots, { x, y, x, y, ... } in percent on R.Map(npc). Not to be changed.
function R.Spots(npc) return D.Rares[npc][SPOTS] end

-- For a rare that walks about: dots along its way, { x, y, ... } as R.Spots; nil for one that
-- stays where it spawns.
function R.Trail(npc) return D.Rares[npc][TRAIL] end

-- Its special drops (D.Loot): rare and epic items, recipes and what is new in Forever, its own
-- first, each { itemID, quality, chance (percent), name, 1 when new in Forever }, and .more,
-- how many more there are; nil for a rare with none.
function R.Loot(npc) return D.Loot and D.Loot[npc] end

local ID, QUALITY, CHANCE, ITEM_NAME, NEW = 1, 2, 3, 4, 5

-- Whether a drop (R.Loot's entry) is new in WoW Forever: marked with Forever's sign.
function R.NewInForever(item) return item[NEW] == 1 end

local function QualityColor(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Its special drops as tooltip lines, under a blank line: each item with its icon in its
-- quality's colour, Forever's sign on one new in Forever, and its chance, then how many more.
-- Nothing for a rare with none.
function R.AddLoot(tooltip, npc)
    local loot = R.Loot(npc)
    if not loot then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("Drops", 1, 0.82, 0)
    for _, item in ipairs(loot) do
        local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(item[ID])
        local name = icon and ("|T%s:14:14|t %s"):format(icon, item[ITEM_NAME]) or item[ITEM_NAME]
        local r, g, b = QualityColor(item[QUALITY])
        local chance = item[CHANCE] >= 1 and ("%d%%"):format(math.floor(item[CHANCE] + 0.5))
            or ("%.1f%%"):format(item[CHANCE])
        if item[NEW] == 1 then name = name .. ns.Shared.Parts.ForeverInline(12) end
        if R.Dropped(npc, item[ID]) then name = name .. "  " .. ns.Color(St.HAVE_RGB, "(you got it)") end
        tooltip:AddDoubleLine(name, chance, r, g, b, T.muted.r, T.muted.g, T.muted.b)
    end
    if loot.more then
        tooltip:AddLine(("And %d more"):format(loot.more), T.muted.r, T.muted.g, T.muted.b)
    end
end

-- Your rares that spawn on the map. Built once; not to be changed.
local byMap

function R.OnMap(mapID)
    Prepare()
    if not byMap then
        byMap = {}
        for npc, rare in pairs(D.Rares) do
            if mine[npc] and #rare[SPOTS] > 0 then
                byMap[rare[MAP]] = byMap[rare[MAP]] or {}
                table.insert(byMap[rare[MAP]], npc)
            end
        end
    end
    return byMap[mapID] or NONE
end

function R.Waypoint(npc)
    local map, x, y = R.Spot(npc)
    if map then ns.PlaceWaypoint(R.Name(npc), map, x, y) end
end

-------------------------------------------------------------------------------
--  Counting kills: the rare you have targeted dying while it was yours, or a corpse you loot.
--  Each creature (its GUID) counts once.
-------------------------------------------------------------------------------
local counted = {}   -- GUID -> true, this session
local watching       -- the GUID of the rare you have targeted, while it lives

local function Count(guid)
    local npc = R.NpcOf(guid)
    if not npc or not D.Rares[npc] or counted[guid] then return end
    counted[guid] = true
    local record = Kills()[npc]
    if record and record.guid == guid then return end
    R.AddKill(npc, guid)
end

local events = CreateFrame("Frame")

local function Readable(...)
    for i = 1, select("#", ...) do
        if Secret((select(i, ...))) then return false end
    end
    return true
end

-- The target died: yours when it was not tapped by someone else.
local function CheckTarget()
    local guid = UnitGUID("target")
    if not Readable(guid) or guid ~= watching then return end
    local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
    if not Readable(dead, denied) then return end
    if dead then
        if not denied then Count(guid) end
        watching = nil
        events:UnregisterEvent("UNIT_HEALTH")
    end
end

local function Retarget()
    watching = nil
    events:UnregisterEvent("UNIT_HEALTH")
    local guid = UnitGUID("target")
    local npc = R.NpcOf(guid)
    if not npc or not D.Rares[npc] or counted[guid] then return end
    local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
    if not Readable(dead, denied) then return end
    -- Its corpse, yours: killed while you had something else targeted.
    if dead then
        if not denied then Count(guid) end
        return
    end
    watching = guid
    events:RegisterUnitEvent("UNIT_HEALTH", "target")
end

-- Each slot: the rare (or rares) it came from counts as killed, and keeps the item as dropped.
local function Looted()
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = type(link) == "string" and Readable(link) and tonumber(link:match("item:(%d+)"))
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            if Readable(sources[i]) then
                Count(sources[i])
                local npc = R.NpcOf(sources[i])
                if itemID and npc and D.Rares[npc] then AddDrop(npc, itemID) end
            end
        end
    end
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        Retarget()
    elseif event == "UNIT_HEALTH" then
        CheckTarget()
    elseif event == "LOOT_READY" then
        Looted()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    watching = nil
    if not S.Get("enabled") then return end
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("LOOT_READY")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

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

local page = Settings.Page("Completo/Rares", S)

page:Window({
    text = "Open Rares",
    open = function() ns.OpenCompletoWindow("rares") end,
    headline = function()
        local n, total = R.Progress()
        return ("%d of %d rares killed"):format(n, total)
    end,
    detail = function()
        local zone = R.CurrentZone()
        if not zone then return "Every rare of every zone, and which of them you have killed." end
        local n, total = R.ZoneProgress(zone)
        return ("%s: %d of %d."):format(zone.name, n, total)
    end,
})

page:Card({
    id = "rares", name = "Rares", order = 10,
    help = "What a zone's page in the Completo window lists. Kills count from when Completo is on: "
        .. "Shift-click a rare there to tick off one you killed before.",
    rows = {
        { key = "rareHideKilled", label = "Hide Killed Rares", toggle = true,
          help = "Leaves the rares you have killed out of a zone's list in the Completo window." },
    },
})
