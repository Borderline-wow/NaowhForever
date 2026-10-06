-------------------------------------------------------------------------------
--  Score.lua -- the Naowh Score (ns.NaowhScore): one number for a character's gear, on the
--  item level scale, so it reads at once ("26.4": worth a set of level 26 epics).
--
--  Each item counts as the item level of an epic with the same stats (its quality's SCALE and
--  SHIFT), weighted by how many stats its slot carries (SLOTS); the score is their average over
--  every gear slot, an empty one counting 0. A two-hander takes both hands' weights. The shirt
--  and tabard do not count. A full set of level L epics scores L.
--
--  The constants (SLOTS, SCALE, SHIFT) are measured, not guessed: Data/Formula.lua, which
--  loads first and makes ns.NaowhScore, holds them, fitted by Tools/fit_naowh_score.py to the
--  game's own item table (each item's stat budget against its slot, quality and level) and
--  refitted for each new Forever build. Rules only, no frames; Inspect.lua reads other players'
--  gear for it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local Score = ns.NaowhScore

local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo

-- The gear slots in order, the main hand before the off hand, so a two-hander is known first.
local ORDER = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local TOTAL = 0
for _, slot in ipairs(ORDER) do TOTAL = TOTAL + Score.SLOTS[slot] end
local MAIN, OFF = 16, 17

---@alias NaowhScoreRead fun(slot: number): number?, number?, boolean? item level, quality, two-handed; nil level for an empty slot

--- The score for gear read slot by slot, and whether every item in it had loaded.
---@param read NaowhScoreRead
---@return number score
---@return boolean complete false while an item's level or quality was not known yet
function Score.Of(read)
    local sum, complete, twoHand = 0, true, false
    for _, slot in ipairs(ORDER) do
        if not (slot == OFF and twoHand) then
            local weight = Score.SLOTS[slot]
            local level, quality, two = read(slot)
            -- A two-hander takes the off hand's share too.
            if slot == MAIN and two then
                twoHand = true
                weight = weight + Score.SLOTS[OFF]
            end
            if level then
                if not quality then complete = false end
                local epic = level * (Score.SCALE[quality] or 1) + (Score.SHIFT[quality] or 0)
                if epic > 0 then sum = sum + weight * epic end
            end
        end
    end
    return sum / TOTAL, complete
end

-- An item link's level, quality and whether it takes both hands; level nil for none, quality
-- nil while the client has not loaded it.
function Score.Link(link)
    if not link then return nil end
    local level = GetDetailedItemLevelInfo(link)
    local quality = select(3, GetItemInfo(link))
    local equip = select(4, GetItemInfoInstant(link))
    return level or 0, level and quality, equip == "INVTYPE_2HWEAPON"
end

local unitLinks = {}   -- slot -> link, one unit's, reused

local function ReadUnit(slot)
    return Score.Link(unitLinks[slot])
end

--- A unit's score from the gear the client knows it wears: yours always, another player's once
--- inspected (Inspect.lua).
---@return number score
---@return boolean complete
function Score.Unit(unit)
    wipe(unitLinks)
    for slot in pairs(Score.SLOTS) do unitLinks[slot] = GetInventoryItemLink(unit, slot) end
    return Score.Of(ReadUnit)
end

--- A score from links kept by slot (an inspected player's, cached).
function Score.Links(links)
    wipe(unitLinks)
    for slot, link in pairs(links) do unitLinks[slot] = link end
    return Score.Of(ReadUnit)
end

--- "26.4", as every place shows it.
function Score.Text(score)
    return ("%.1f"):format(score)
end

-------------------------------------------------------------------------------
--  The best there is, and how a score grades against it
--
--  The best score Forever's gear allows: each slot's best item the addon knows of (the Dungeon
--  Journal's loot and faction rewards, which the BiS List shares), rings and trinkets two
--  different items, and a two-hander or a main and off hand, whichever counts more. Worked out
--  the first time it is asked for, so new loot in the data raises it with no number to keep.
--
--  For a level, the best that level can wear: a full set of blues of its level plus AHEAD
--  (what a well geared player of that level has, dungeon blues being about five levels over
--  what they need), or what the data offers that level if more, and never over the best in
--  the game. The data alone would not do: below the first dungeons it has nothing for most
--  slots, and a level 12 in whites would read as the best there is.
-------------------------------------------------------------------------------
local LEVEL_GAP = 5   -- an item with no required level in the data needs its item level less this
local AHEAD = 5       -- a level's best: blues this many item levels over it
local BLUE = 3
local MAX = 0         -- the key for the best at any level
local CATEGORY = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
    INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
    INVTYPE_FINGER = "ring", INVTYPE_TRINKET = "trinket", INVTYPE_CLOAK = 15,
    INVTYPE_WEAPON = "one", INVTYPE_WEAPONMAINHAND = "main", INVTYPE_2HWEAPON = "two",
    INVTYPE_SHIELD = "off", INVTYPE_HOLDABLE = "off", INVTYPE_WEAPONOFFHAND = "off",
    INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18, INVTYPE_RELIC = 18,
}
local bestAt = {}   -- level (MAX for any) -> the best score

local function Epic(level, quality)
    return math.max(0, level * (Score.SCALE[quality] or 1) + (Score.SHIFT[quality] or 0))
end

-- Keeps the best two of a category (rings and trinkets need two different items).
local function Offer(best, second, category, worth, id)
    local top = best[category]
    if not top or worth > top then
        if top then second[category] = top end
        best[category] = worth
        best[category .. "id"] = id
    elseif id ~= best[category .. "id"] and (not second[category] or worth > second[category]) then
        second[category] = worth
    end
end

local function Best(level)
    local items = ns.Journal and ns.Journal.Items
    if not items then return nil end
    local best, second = {}, {}
    for id, facts in pairs(items) do
        local itemLevel, required, quality = facts[3], facts[4], facts[5]
        if required == 0 then required = itemLevel - LEVEL_GAP end
        if level == MAX or required <= level then
            local category = CATEGORY[select(4, GetItemInfoInstant(id)) or ""]
            if category then Offer(best, second, category, Epic(itemLevel, quality), id) end
        end
    end
    local W = Score.SLOTS
    local sum = 0
    for slot = 1, 18 do
        if W[slot] and best[slot] then sum = sum + W[slot] * best[slot] end
    end
    sum = sum + W[11] * (best.ring or 0) + W[12] * (second.ring or 0)
    sum = sum + W[13] * (best.trinket or 0) + W[14] * (second.trinket or 0)
    local one = math.max(best.one or 0, best.main or 0)
    local off = math.max(best.off or 0, second.one or 0)
    sum = sum + math.max((W[MAIN] + W[OFF]) * (best.two or 0), W[MAIN] * one + W[OFF] * off)
    return sum / TOTAL
end

--- The best score there is: at any level, or for one (what it can wear).
---@param level? number
function Score.Best(level)
    local key = level or MAX
    local best = bestAt[key]
    if best == nil then
        best = Best(key) or false
        if key ~= MAX then
            local top = Score.Best()
            best = math.max(best or 0, Epic(key + AHEAD, BLUE))
            if top then best = math.min(best, top) end
        end
        bestAt[key] = best
    end
    return best or nil
end

-- A score's grade, as an item's quality: grey, white, green, blue, purple, orange, by its
-- share of the best (GRADES: the share each starts at).
Score.GRADES = { { 0, 0 }, { 0.25, 1 }, { 0.45, 2 }, { 0.65, 3 }, { 0.80, 4 }, { 0.95, 5 } }

-- Its colour, by the same share, on a ramp rather than in steps, so a little better reads a
-- little brighter: grey, white, then greener and greener, blue to deeper blue, purple to
-- deeper purple, and orange at the very top. Our own stops: { share, r, g, b }.
local RAMP = {
    { 0.00, 0.62, 0.62, 0.62 }, { 0.15, 1.00, 1.00, 1.00 }, { 0.25, 0.78, 1.00, 0.70 },
    { 0.35, 0.50, 1.00, 0.40 }, { 0.45, 0.12, 1.00, 0.00 }, { 0.55, 0.20, 0.75, 1.00 },
    { 0.65, 0.00, 0.44, 0.87 }, { 0.72, 0.40, 0.36, 1.00 }, { 0.80, 0.64, 0.21, 0.93 },
    { 0.88, 0.82, 0.32, 0.88 }, { 0.94, 1.00, 0.66, 0.25 }, { 1.00, 1.00, 0.50, 0.00 },
}
Score.RAMP = RAMP   -- the paperdoll's bar draws the same stops
local rampCodes = {}   -- percent -> its colour code, made once each

--- The colour code for a share of the best (0 to 1).
function Score.Code(share)
    local percent = math.floor(math.max(0, math.min(1, share)) * 100 + 0.5)
    local code = rampCodes[percent]
    if code then return code end
    local s = percent / 100
    local low, high = RAMP[1], RAMP[#RAMP]
    for i = 2, #RAMP do
        if s <= RAMP[i][1] then
            low, high = RAMP[i - 1], RAMP[i]
            break
        end
    end
    local t = high[1] > low[1] and (s - low[1]) / (high[1] - low[1]) or 1
    local function Mix(k) return math.floor((low[k] + (high[k] - low[k]) * t) * 255 + 0.5) end
    code = ("|cff%02x%02x%02x"):format(Mix(2), Mix(3), Mix(4))
    rampCodes[percent] = code
    return code
end

--- A score's share of the best and its grade (the quality whose colour it takes), against
--- the best at any level or at the player's level: as against says, else as Grade Against is
--- set ("both" grades the number against the best in the game).
---@param level? number the player's level, for "level"
---@param against? "max"|"level"
---@return number? share 0 to 1; nil while the best is not known
---@return number quality
function Score.Grade(score, level, against)
    against = against or ns.QoLSettings.Get("naowhScoreCompare")
    local best = Score.Best(against == "level" and level or nil)
    if not best or best <= 0 then return nil, 1 end
    local share = math.min(1, score / best)
    local quality = 0
    for _, grade in ipairs(Score.GRADES) do
        if share >= grade[1] then quality = grade[2] end
    end
    return share, quality
end

--- The score in its colour on the ramp; plain while there is no best to grade it against.
function Score.Colored(score, level, against)
    local share = Score.Grade(score, level, against)
    return share and Score.Code(share) .. Score.Text(score) .. "|r" or Score.Text(score)
end

-- The tooltip's percent: in the share's colour, or with Both, in gold (the colour of a level's
-- goal on the paperdoll's card) and saying which level it is of. Made once per percent/level.
local GOLD = "|cffffd100"
local percents, ofLevels = {}, {}

local function Percent(share)
    local percent = math.floor(math.max(0, math.min(1, share)) * 100 + 0.5)
    local text = percents[percent]
    if not text then
        text = Score.Code(percent / 100) .. percent .. "%|r"
        percents[percent] = text
    end
    return text
end

local function OfLevel(share, level)
    local percent = math.floor(math.max(0, math.min(1, share)) * 100 + 0.5)
    local key = level * 101 + percent
    local text = ofLevels[key]
    if not text then
        text = ("%s%d%% of level %d|r"):format(GOLD, percent, level)
        ofLevels[key] = text
    end
    return text
end

--- The score as a tooltip says it: the number in its colour, then its share of the best it is
--- graded against, in the same colour. With Both: the number against the best in the game,
--- then in gold its share of the best for their level (below the level cap; at it, the share
--- of the best in the game, the two being the same).
function Score.Tooltip(score, level)
    local compare = ns.QoLSettings.Get("naowhScoreCompare")
    local against = compare == "both" and "max" or nil
    local text = Score.Colored(score, level, against)
    if compare == "both" and level then
        local best, top = Score.Best(level), Score.Best()
        if best and top and best < top then
            return text .. "  " .. OfLevel(math.min(1, score / best), level)
        end
    end
    local share = Score.Grade(score, level, against)
    return share and (text .. "  " .. Percent(share)) or text
end
