-------------------------------------------------------------------------------
--  NaowhForever_SleepingBagData.lua -- the Cozy Sleeping Bag: a hidden quest chain across
--  Azeroth, each step a thing in the world to click, ending in the Cozy Sleeping Bag (rest in
--  it for a bonus to experience). From Wowhead Forever's quests (objects and spots) and its
--  guide (the climbs and jumps), 2026-10-04.
--
--  steps: in order, for your faction. Each: object = what you click, map = uiMapID, x, y,
--  place = where it is, tip = how to get there where it is not plain; done = the quest that
--  clicking it hands in (it is done once that quest is), or for the first, started = the quest
--  it starts. optional: a side step that is not needed for the bag.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local WESTFALL = { object = "Burned-Out Remains", map = 1436, x = 37.5, y = 50.7,
    place = "Alexston Farmstead", tip = "The wreckage of a cart in the rubble." }
local BARRENS = { object = "Burned-Out Remains", map = 1413, x = 46.4, y = 73.9,
    place = "the burnt tower south of Camp Taurajo", tip = "Follow the road south of Camp Taurajo." }

local function Copy(t, extra)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    for k, v in pairs(extra) do out[k] = v end
    return out
end

-- The rest of the chain is the same for both factions.
local SHARED = {
    { object = "Pocket Litter", map = 1442, x = 40.8, y = 52.6, place = "an abandoned camp", done = 79192,
      tip = "Take the path northeast of Sun Rock Retreat; it lies on top of a box." },
    { object = "Mound of Dirt", map = 1442, x = 39.6, y = 49.9, place = "a ledge north of the camp", done = 79980,
      tip = "Climb the hill straight north of the camp and jump across to it from the edge." },
    { object = "Carved Figurine", map = 1432, x = 49.5, y = 12.8, place = "the Stonewrought Dam", done = 79974,
      tip = "Jump onto the carved heads facing the Wetlands." },
    { object = "Messenger Bag", map = 1417, x = 22.5, y = 24.2, place = "inside Thoradin's Wall", done = 79975,
      tip = "Climb into the wall from the cart on the Hillsbrad side (Hillsbrad Foothills 87.3, 49.6); the bag "
          .. "hangs outside, to the right." },
    { object = "Hastily Rolled-Up Satchel", map = 1417, x = 22.5, y = 24.2, place = "under the Messenger Bag",
      done = 79976, tip = "Right below the Messenger Bag. It holds the Cozy Sleeping Bag." },
}

local function Chain(first, second, note)
    local steps = { Copy(first, { started = note }), Copy(second, { done = note }) }
    for _, step in ipairs(SHARED) do steps[#steps + 1] = step end
    return steps
end

ns.SleepingBag = {
    level = 14,                -- the chain needs it
    item = 211527,             -- Cozy Sleeping Bag
    -- "... and that note you found": Alliance from Westfall to The Barrens, Horde the other way.
    steps = {
        A = Chain(WESTFALL, BARRENS, 79008),
        H = Chain(BARRENS, WESTFALL, 79007),
    },
    optional = { object = "Firepit", map = 1442, x = 40.6, y = 52.4, place = "the abandoned camp", done = 80001,
        quest = "Rekindle",
        tip = "Light it with the Simple Wood and Flint and Tinder from the Pocket Litter. Not needed for the bag." },
}
