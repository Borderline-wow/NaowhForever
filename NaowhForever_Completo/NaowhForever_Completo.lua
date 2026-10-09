-------------------------------------------------------------------------------
--  NaowhForever_Completo.lua -- the Completo module: what you have done of everything the
--  game has to collect. Its first part is Quests: every quest of every zone for your
--  character (Data/NaowhForever_CompletoQuests.lua), how many you have done per zone, and
--  for each quest chain the step you are on. Mounts, transmog and more are to follow as
--  tabs of their own.
--
--  Off by default. Nothing runs until its window is open: the window reads what you have
--  done when it draws, and listens for quest events only while it is shown.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI

local S = UI.ModuleSettings("completo", {
    enabled = false, hideDone = false, windowAlpha = 1, windowScale = 1,
    -- A ! on the map at each quest giver with a quest for you; mapGrey adds the low level ones.
    mapPins = false, mapGrey = false, mapChainsOnly = false, mapPinSize = 18,
    -- Rares: a warning when one is near, with a raid mark on it (NaowhForever_CompletoRareAlert.lua).
    rareHideKilled = false, rareAlert = false, rareMarker = "skull", rareAlertKilled = false,
    rareSound = true, rareSoundKey = "file:gruntlinghorn", rareAlertPosition = nil, rareAlertScale = 1,
    rareAlertTime = 20, rareAlertFont = "", rareAlertFontSize = 13, rareAlertOutline = "",
    rareAlertBackground = "card", rareAlertGlow = false,
    -- A star on the world map where each rare spawns (NaowhForever_CompletoRareMap.lua).
    rarePins = false, rarePinsKilled = false, rarePinSize = 18,
})
ns.CompletoSettings = S

local D = ns.CompletoQuestData
local Q = {}
ns.Completo = { Quests = Q }

-- The world map draws its canvas scaled to fit: in the small map's window it is scaled down,
-- and pins sized in map units shrink with it. A pin's ApplyCurrentScale (the map calls it as
-- it scales) set to this keeps it at least MIN_PIN_SCALE times its size on screen, as on the
-- small map; on the full-screen map, scaled up, it is left as it is, and it grows as you zoom.
local MIN_PIN_SCALE = 1.5

function ns.Completo.ScalePin(pin)
    local map = pin:GetMap()
    local canvas = map and map.GetCanvasScale and map:GetCanvasScale()
    if not canvas or canvas <= 0 then return end
    local scale = math.max(1, MIN_PIN_SCALE / canvas)
    if map.GetGlobalPinScale and not (pin.IsIgnoringGlobalPinScale and pin:IsIgnoringGlobalPinScale()) then
        scale = scale * map:GetGlobalPinScale()
    end
    pin:SetScale(scale)
    pin:ApplyCurrentPosition()
end

-- The client's race IDs to their bit in Wowhead's race masks (Forever's own two races too).
local RACE_BITS = { [1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6, [8] = 7, [95] = 32, [96] = 33 }
local NAME, LEVEL, REQ_LEVEL, SIDE, RACES, CLASSES, MAP, X, Y, GIVER, ITEM = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
local ALLIANCE, HORDE = 1, 2

local function HasBit(mask, bit)
    return math.floor(mask / 2 ^ bit) % 2 == 1
end

-------------------------------------------------------------------------------
--  Which quests are yours: your faction, race and class. Worked out once, the first time
--  the window draws; none of it changes while you play.
-------------------------------------------------------------------------------
local mine           -- questID -> true
local zoneOf         -- questID -> its zone (a D.Zones entry)
local chains         -- your chains: { steps = { {ids}, ... }, name, level, id }
local chainOf        -- questID -> its chain

local function ForMe(quest, side, raceBit, classBit)
    if quest[SIDE] == ALLIANCE and side ~= ALLIANCE then return false end
    if quest[SIDE] == HORDE and side ~= HORDE then return false end
    if quest[RACES] > 0 and raceBit and not HasBit(quest[RACES], raceBit) then return false end
    if quest[CLASSES] > 0 and classBit and not HasBit(quest[CLASSES], classBit) then return false end
    return true
end

local function Prepare()
    if mine then return end
    mine, zoneOf, chains, chainOf = {}, {}, {}, {}
    local side = UnitFactionGroup("player") == "Horde" and HORDE or ALLIANCE
    local raceBit = RACE_BITS[select(3, UnitRace("player"))]
    local classID = select(3, UnitClass("player"))
    local classBit = classID and classID - 1
    for id, quest in pairs(D.Quests) do
        if ForMe(quest, side, raceBit, classBit) then mine[id] = true end
    end
    for _, zone in ipairs(D.Zones) do
        for _, id in ipairs(zone.quests) do zoneOf[id] = zone end
    end
    -- A chain keeps the steps you can do; one left with a single step is no chain for you.
    for _, steps in ipairs(D.Chains) do
        local own = {}
        for _, step in ipairs(steps) do
            local ids = {}
            for _, id in ipairs(step) do
                if mine[id] then ids[#ids + 1] = id end
            end
            ids.any = step.any
            if #ids > 0 then own[#own + 1] = ids end
        end
        if #own > 1 then
            local first = D.Quests[own[1][1]]
            local chain = { steps = own, name = first[NAME], level = first[LEVEL], id = #chains + 1 }
            chains[#chains + 1] = chain
            for _, ids in ipairs(own) do
                for _, id in ipairs(ids) do chainOf[id] = chain end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  What you have done: read in one call when the window draws (Q.Refresh), else one
--  quest at a time.
-------------------------------------------------------------------------------
local done = {}

function Q.Refresh()
    Prepare()
    wipe(done)
    local all = C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
    if all then
        for i = 1, #all do done[all[i]] = true end
    else
        for id in pairs(mine) do
            if C_QuestLog.IsQuestFlaggedCompleted(id) then done[id] = true end
        end
    end
end

function Q.Done(id) return done[id] == true end

function Q.InLog(id)
    return C_QuestLog.GetLogIndexForQuestID(id) ~= nil
end

function Q.Mine(id) return mine[id] == true end
function Q.Name(id) return D.Quests[id][NAME] end
function Q.Level(id) return D.Quests[id][LEVEL] end

-- Wowhead's required level is wrong for some quests (Mending Old Wounds: level 60, "requires
-- level 15", and the game does not offer it at 15). None is taken as needing less than its
-- own level less MAX_UNDER.
local MAX_UNDER = 10

function Q.RequiredLevel(id)
    local quest = D.Quests[id]
    return math.max(quest[REQ_LEVEL], quest[LEVEL] - MAX_UNDER)
end
function Q.Zone(id) return zoneOf[id] end
function Q.Chain(id) return chainOf[id] end
function Q.Zones() return D.Zones end

-- Who gives it, where its start is known: a quest giver, or the mob that drops its item.
function Q.Giver(id) return D.Quests[id][GIVER] end

-- The item that begins it, for a quest a mob's drop starts (its giver is then that mob).
function Q.Item(id) return D.Quests[id][ITEM] end

-- One you can do again and again: the game never marks it done.
function Q.Repeatable(id) return D.Repeatable ~= nil and D.Repeatable[id] == true end

function Q.Spot(id)
    local quest = D.Quests[id]
    if quest[MAP] then return quest[MAP], quest[X], quest[Y] end
end

-- A step is done when all its quests are, or with any (versions of one quest) when one is.
function Q.StepDone(step)
    for _, id in ipairs(step) do
        if done[id] and step.any then return true end
        if not done[id] and not step.any then return false end
    end
    return not step.any
end

---@return number at the step you are on (#steps + 1 once all are done)
---@return number steps
function Q.ChainAt(chain)
    local steps = chain.steps
    for i = #steps, 1, -1 do
        if Q.StepDone(steps[i]) then return i + 1, #steps end
    end
    return 1, #steps
end

-------------------------------------------------------------------------------
--  Quests a quest giver did not offer you when you spoke to them, though the data says you
--  could take them: a prerequisite the data does not know (NaowhForever_CompletoGivers.lua
--  records them). Kept per character until you level up or hand in a quest in its zone,
--  either of which may be what it waited for: questID -> { your level, the zone's hand-ins }.
-------------------------------------------------------------------------------
local function CharStore(key)
    local account = ns.AccountSettings()
    account[key] = account[key] or {}
    local char = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    account[key][char] = account[key][char] or {}
    return account[key][char]
end

local function ZoneTurnIns(id)
    local zone = zoneOf and zoneOf[id]
    return zone and CharStore("completoTurnIns")[zone.map] or 0
end

function Q.NotOffered(id)
    local store = CharStore("completoNotOffered")
    local entry = store[id]
    if not entry then return false end
    if entry[1] == UnitLevel("player") and entry[2] == ZoneTurnIns(id) then return true end
    store[id] = nil
    return false
end

-- offered: whether the quest giver had it for you when you last spoke to them.
function Q.SetOffered(id, offered)
    CharStore("completoNotOffered")[id] = not offered and { UnitLevel("player"), ZoneTurnIns(id) } or nil
end

-- A quest handed in: the quests its zone's givers held back may be on offer now.
function Q.CountTurnIn(id)
    Prepare()
    local zone = zoneOf[id]
    if not zone then return end
    local turnIns = CharStore("completoTurnIns")
    turnIns[zone.map] = (turnIns[zone.map] or 0) + 1
end

-- Where a quest stands for you: "done", "log" (in your quest log), "low" (your level is under
-- what it needs), "later" (an earlier step of its chain is not done yet), "held" (its quest
-- giver did not offer it to you) or "open".
function Q.State(id)
    local state = Q.Expected(id)
    if state == "open" and Q.NotOffered(id) then return "held" end
    return state
end

-- Whether the quests before it are done: any one of them (D.Requires). One for another
-- faction, race or class does not count; one the data has no row for (a dungeon or class
-- quest) does.
function Q.Opened(id)
    local before = D.Requires[id]
    if not before then return true end
    local counted = false
    for _, other in ipairs(before) do
        if done[other] then return true end
        if mine[other] or not D.Quests[other] then counted = true end
    end
    return not counted
end

-- The state from the data alone, as if its quest giver had never been asked: never "held".
function Q.Expected(id)
    if done[id] then return "done" end
    if Q.InLog(id) then return "log" end
    if not Q.Opened(id) then return "later" end
    if UnitLevel("player") < Q.RequiredLevel(id) then return "low" end
    return "open"
end

---@return number done
---@return number total your quests in the zone
---@return number lowest quest level
---@return number highest quest level
function Q.ZoneProgress(zone)
    local n, total, low, high = 0, 0, nil, nil
    for _, id in ipairs(zone.quests) do
        -- A repeatable quest is never done for good, so it is left out of the count.
        if mine[id] and not Q.Repeatable(id) then
            total = total + 1
            if done[id] then n = n + 1 end
            local level = D.Quests[id][LEVEL]
            if level > 0 then
                low = math.min(low or level, level)
                high = math.max(high or level, level)
            end
        end
    end
    return n, total, low, high
end

function Q.Progress()
    local n, total = 0, 0
    for _, zone in ipairs(D.Zones) do
        local zn, zt = Q.ZoneProgress(zone)
        n, total = n + zn, total + zt
    end
    return n, total
end

-- The zone's chains (any step in it), and its quests in no chain, lowest level first.
-- Tables reused until the next call.
local zoneChains, zoneSingles, seenChain = {}, {}, {}

local function ByLevel(a, b)
    local la = type(a) == "table" and a.level or D.Quests[a][LEVEL]
    local lb = type(b) == "table" and b.level or D.Quests[b][LEVEL]
    if la ~= lb then return la < lb end
    local na = type(a) == "table" and a.name or D.Quests[a][NAME]
    local nb = type(b) == "table" and b.name or D.Quests[b][NAME]
    return na < nb
end

function Q.ZoneLists(zone)
    wipe(zoneChains)
    wipe(zoneSingles)
    wipe(seenChain)
    for _, id in ipairs(zone.quests) do
        if mine[id] then
            local chain = chainOf[id]
            if chain then
                if not seenChain[chain] then
                    seenChain[chain] = true
                    zoneChains[#zoneChains + 1] = chain
                end
            else
                zoneSingles[#zoneSingles + 1] = id
            end
        end
    end
    table.sort(zoneChains, ByLevel)
    table.sort(zoneSingles, ByLevel)
    return zoneChains, zoneSingles
end

-- Where a quest sits in its chain: its step and the chain's length, or nil out of one.
function Q.ChainStep(id)
    local chain = chainOf[id]
    if not chain then return end
    for i, step in ipairs(chain.steps) do
        for _, other in ipairs(step) do
            if other == id then return i, #chain.steps end
        end
    end
end

-- Your quests whose name or quest giver holds the text (lower case, as typed), zone by zone in
-- the zones' order, at most limit of them: { { zone, ids }, ... } and how many there were in
-- all. Tables reused until the next call.
local found, foundIds = {}, {}

-- Lowest level first, a chain's quests together at its first quest's level in the chain's
-- order: by level, then chain, then step, then name, so the order is the same however asked.
local function FoundKey(id)
    local chain = chainOf[id]
    if not chain then return D.Quests[id][LEVEL], 0, 0 end
    return chain.level, chain.id, (Q.ChainStep(id))
end

local function FoundOrder(a, b)
    local la, ca, sa = FoundKey(a)
    local lb, cb, sb = FoundKey(b)
    if la ~= lb then return la < lb end
    if ca ~= cb then return ca < cb end
    if sa ~= sb then return sa < sb end
    return D.Quests[a][NAME] < D.Quests[b][NAME]
end

function Q.Search(text, limit)
    Prepare()
    wipe(found)
    local n = 0
    for _, zone in ipairs(D.Zones) do
        local ids = foundIds[zone] or {}
        foundIds[zone] = wipe(ids)
        for _, id in ipairs(zone.quests) do
            if mine[id] then
                local quest = D.Quests[id]
                if quest[NAME]:lower():find(text, 1, true)
                    or (quest[GIVER] and quest[GIVER]:lower():find(text, 1, true)) then
                    n = n + 1
                    if n <= limit then ids[#ids + 1] = id end
                end
            end
        end
        if #ids > 0 then
            table.sort(ids, FoundOrder)
            found[#found + 1] = { zone = zone, ids = ids }
        end
    end
    return found, n
end

-- The zone you are in, if it has quests: walks up from the map you are on (a cave, a town).
function Q.CurrentZone()
    local map = C_Map.GetBestMapForUnit("player")
    while map do
        for _, zone in ipairs(D.Zones) do
            if zone.map == map then return zone end
        end
        local info = C_Map.GetMapInfo(map)
        map = info and info.parentMapID ~= 0 and info.parentMapID or nil
    end
end

function Q.Waypoint(id)
    local map, x, y = Q.Spot(id)
    if map then ns.PlaceWaypoint(Q.Name(id), map, x, y) end
end

-------------------------------------------------------------------------------
--  Quests to pick up, for the map: at each quest giver, the quests you could take now
-------------------------------------------------------------------------------
-- Low level: grey in your quest log, worth no experience any more. The game's own colour
-- for its level, else classic's rule (more than the green range under your level).
function Q.Trivial(id)
    local level = D.Quests[id][LEVEL]
    if level <= 0 then return false end
    if QuestDifficultyColors and QuestDifficultyColors.trivial then
        return GetQuestDifficultyColor(level) == QuestDifficultyColors.trivial
    end
    local green = GetQuestGreenRange and GetQuestGreenRange() or 8
    return level < UnitLevel("player") - green
end

-- Yours, not done, not in your log, your level high enough, its chain's earlier steps done.
function Q.Available(id)
    return mine[id] == true and Q.State(id) == "open"
end

local byMap         -- uiMapID -> your quests that start there
local givers = {}   -- Q.Givers' answer, reused
local spare = {}    -- its entries, reused

local function Index()
    if byMap then return end
    byMap = {}
    for id, quest in pairs(D.Quests) do
        local map = quest[MAP]
        if map and mine[id] then
            byMap[map] = byMap[map] or {}
            table.insert(byMap[map], id)
        end
    end
end

-- Your quests a quest giver of that name gives on the map. Reused until the next call.
local named = {}

function Q.GiverQuests(name, mapID)
    Prepare()
    Index()
    wipe(named)
    for _, id in ipairs(byMap[mapID] or {}) do
        if D.Quests[id][GIVER] == name then named[#named + 1] = id end
    end
    return named
end

-- The quest givers on a map with a quest you could pick up: { x, y, quests = { ids },
-- grey = true when every one is low level, repeatable = true when every one is }. Low level ones only with grey; with chainsOnly,
-- only quests in a chain (Q.Available already leaves only a chain's next step). Tables
-- reused until the next call; call Q.Refresh first.
function Q.Givers(mapID, grey, chainsOnly)
    Prepare()
    Index()
    for i = #givers, 1, -1 do
        local entry = givers[i]
        wipe(entry.quests)
        spare[#spare + 1] = entry
        givers[i] = nil
    end
    local at = {}
    for _, id in ipairs(byMap[mapID] or {}) do
        if Q.Available(id) and (chainOf[id] or not chainsOnly) then
            local trivial = Q.Trivial(id)
            if grey or not trivial then
                local quest = D.Quests[id]
                local key = quest[X] .. ":" .. quest[Y]
                local entry = at[key]
                if not entry then
                    entry = table.remove(spare) or { quests = {} }
                    entry.x, entry.y, entry.grey, entry.repeatable = quest[X], quest[Y], true, true
                    at[key] = entry
                    givers[#givers + 1] = entry
                end
                table.insert(entry.quests, id)
                if not trivial then entry.grey = false end
                if not Q.Repeatable(id) then entry.repeatable = false end
            end
        end
    end
    return givers
end

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local page = Settings.Page("Completo/Quests", S)

local function Headline()
    Q.Refresh()
    local n, total = Q.Progress()
    return ("%d of %d zone quests done"):format(n, total)
end

local function Detail()
    local zone = Q.CurrentZone()
    if not zone then return "Every quest of every zone, and where you are in each chain." end
    local n, total = Q.ZoneProgress(zone)
    return ("%s: %d of %d."):format(zone.name, n, total)
end

page:Window({
    text = "Open Quests",
    open = function() ns.OpenCompletoWindow("quests") end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "quests", name = "Quests", order = 10,
    help = "What a zone's page in the Completo window lists.",
    rows = {
        { key = "hideDone", label = "Hide Done", toggle = true,
          help = "Leave out the quests and chains you have finished." },
    },
})

local QUESTS_OFF = "Turn on Completo"

local function On() return S.Get("enabled") == true end

local function MapSummary(store)
    local what = store.Get("mapChainsOnly") and "Quest chains" or "Quests"
    return store.Get("mapGrey") and what .. " you can pick up, low level ones too"
        or what .. " that still give experience"
end

page:Card({
    id = "mapPins", name = "Map Pins", order = 20, switch = "mapPins",
    help = "A yellow ! on the world map at every quest giver with a quest you can pick up that still gives "
        .. "experience. Hover it for the quests; click it for a waypoint.",
    summary = MapSummary,
    rows = {
        { key = "mapGrey", label = "Low Level Quests", toggle = true, needs = On, why = QUESTS_OFF,
          help = "Also a grey ! for quests you can still pick up that no longer give experience." },
        { key = "mapChainsOnly", label = "Chains Only", toggle = true, needs = On, why = QUESTS_OFF,
          help = "Only quest chains: the first quest of each one, and the next step of those you are on." },
        { key = "mapPinSize", label = "Pin Size", slider = { 12, 32, 1 }, needs = On, why = QUESTS_OFF,
          help = "How big the pins are on the map." },
    },
})

-- General: what is Completo's as a whole, not one tab's.
local general = Settings.Page("Completo/General", S)

general:Window({
    text = "Open Completo",
    open = function() ns.OpenCompletoWindow("overview") end,
    headline = function()
        Q.Refresh()
        local n, total = Q.Progress()
        local killed, rares = ns.Completo.Rares.Progress()
        return ("%d of %d quests done, %d of %d rares killed"):format(n, total, killed, rares)
    end,
    detail = function() return "Everything there is to do, and how much of it you have done." end,
})

general:Card({
    id = "keys", name = "Key Binding", order = 30,
    help = "The key that opens the Completo window.",
    rows = {
        { label = "Open Completo", binding = "NAOWHFOREVER_COMPLETO",
          help = "Press it to open or close Completo. Shift-L unless something else had it." },
    },
})

general:Card({
    id = "window", name = "Window", order = 90,
    help = "Completo's own window. Drag its bottom right corner to size it.",
    rows = {
        { key = "windowScale", label = "Window Scale", slider = { 50, 150, 5 }, unit = "%", scale = 0.01,
          help = "How big the window and everything in it is. Drag its corner to make it bigger instead." },
        { key = "windowAlpha", label = "Window Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 },
          unit = "%", scale = 0.01, help = "How solid the window is, in percent. Also on its title bar." },
    },
})
