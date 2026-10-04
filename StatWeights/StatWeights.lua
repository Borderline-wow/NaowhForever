-------------------------------------------------------------------------------
--  StatWeights.lua -- what each stat is worth to your spec (ns.StatWeights), and so what an
--  item is worth and how much stronger it makes you over what you wear. The defaults are
--  Data/Defaults.lua's; a player's changes are kept for the account, per spec, only where
--  they differ from the default. The BiS List reads them for its enchants and upgrades
--  whether or not this module is on; on, it also puts its line on gear tooltips (Tooltip.lua).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local Items = ns.Shared.Items

local GetItemStats = C_Item.GetItemStats
local IsItemDataCachedByID = C_Item.IsItemDataCachedByID
local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant

local SW = {}
ns.StatWeights = SW

local S = UI.ModuleSettings("statWeights", { enabled = false })
SW.Settings = S
ns.StatWeightSettings = S

-- Every stat a weight can be set for, in the editor's order: key, name, and the slider's
-- range and step (a percent is worth more than a point).
SW.STATS = {
    { "str", "Strength", 0, 3, 0.05 }, { "agi", "Agility", 0, 3, 0.05 },
    { "sta", "Stamina", 0, 3, 0.05 }, { "int", "Intellect", 0, 3, 0.05 },
    { "spi", "Spirit", 0, 3, 0.05 }, { "ap", "Attack Power", 0, 3, 0.05 },
    { "rap", "Ranged Attack Power", 0, 3, 0.05 }, { "dps", "Weapon DPS", 0, 20, 0.1 },
    { "hit", "Hit %", 0, 30, 0.5 },
    { "crit", "Crit %", 0, 30, 0.5 }, { "haste", "Haste %", 0, 30, 0.5 },
    { "spell", "Spell Damage", 0, 3, 0.05 }, { "heal", "Healing", 0, 3, 0.05 },
    { "scrit", "Spell Crit %", 0, 30, 0.5 }, { "mp5", "Mana every 5 sec", 0, 5, 0.1 },
    { "fire", "Fire Damage", 0, 3, 0.05 }, { "frost", "Frost Damage", 0, 3, 0.05 },
    { "shadow", "Shadow Damage", 0, 3, 0.05 }, { "nature", "Nature Damage", 0, 3, 0.05 },
    { "arcane", "Arcane Damage", 0, 3, 0.05 }, { "holy", "Holy Damage", 0, 3, 0.05 },
    { "def", "Defense", 0, 5, 0.05 }, { "dodge", "Dodge %", 0, 30, 0.5 },
    { "block", "Block %", 0, 30, 0.5 }, { "armor", "Armor", 0, 0.2, 0.005 },
    { "threat", "Threat %", 0, 30, 0.5 },
}
local STAT_KEY, STAT_NAME = {}, {}
for _, stat in ipairs(SW.STATS) do STAT_KEY[stat[1]], STAT_NAME[stat[1]] = true, stat[2] end

-- The game's stat keys -> the weights' (one key may count for two).
local KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spell",
    ITEM_MOD_SPELL_POWER_SHORT = { "spell", "heal" }, ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_CRIT_RATING_SHORT = "crit",
    ITEM_MOD_SPELL_CRIT_RATING_SHORT = "scrit", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_HASTE_RATING_SHORT = "haste", RESISTANCE0_NAME = "armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}
-- What a weapon's damage per second counts for, by slot: the main hand's whole, the off
-- hand's half; a hunter's ranged weapon's only.
local DPS_SHARE = { [16] = 1, [17] = 0.5 }
local HUNTER_DPS_SHARE = { [18] = 1 }
-- Your stats the game sums up for you, by UnitStat's index.
local PRIMARY = { "str", "agi", "sta", "int", "spi" }
local PRIMARY_KEY = { str = true, agi = true, sta = true, int = true, spi = true }
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
-- Each class's talent trees in the game's order, as specs. A druid's Feral tree is weighed for
-- damage; a bear picks Feral Tank by hand.
local TREES = {
    DRUID = { "balance-druid", "feral-dps-druid", "restoration-druid" },
    HUNTER = { "beast-mastery-hunter", "marksmanship-hunter", "survival-hunter" },
    MAGE = { "arcane-mage", "fire-mage", "frost-mage" },
    PALADIN = { "holy-paladin", "protection-paladin", "retribution-paladin" },
    PRIEST = { "discipline-priest", "holy-priest", "shadow-priest" },
    ROGUE = { "assassination-rogue", "combat-rogue", "subtlety-rogue" },
    SHAMAN = { "elemental-shaman", "enhancement-shaman", "restoration-shaman" },
    WARLOCK = { "affliction-warlock", "demonology-warlock", "destruction-warlock" },
    WARRIOR = { "arms-warrior", "fury-warrior", "protection-warrior" },
}
-- A weapon's speed, for when the game has none to give (nothing in the hand).
local SPEED = 2.6

--- What an amount of one of the game's stats ("ITEM_MOD_AGILITY_SHORT") is worth by weights:
--- 0 for one they do not weigh.
function SW.KeyWorth(gameKey, amount, weights)
    local mapped = KEYS[gameKey]
    if not mapped then return 0 end
    if type(mapped) == "string" then return amount * (weights[mapped] or 0) end
    local worth = 0
    for i = 1, #mapped do worth = worth + amount * (weights[mapped[i]] or 0) end
    return worth
end

--- One of the game's stat keys by the weights' name for it ("Weapon DPS"), or nil.
function SW.KeyName(gameKey)
    local mapped = KEYS[gameKey]
    if type(mapped) == "table" then mapped = mapped[1] end
    return mapped and STAT_NAME[mapped]
end

---@return boolean on the module's own extras (the tooltip line); the weights work either way
function SW.On()
    return S.Get("enabled") == true
end

-------------------------------------------------------------------------------
--  Specs and their weights
-------------------------------------------------------------------------------
local classSpecs, byKey

local function Index()
    byKey = {}
    for _, spec in ipairs(ns.StatWeightDefaults) do byKey[spec.key] = spec end
end

---@return table[] specs your class's, in the defaults' order: { class, key, name, weights }
function SW.ClassSpecs()
    if not classSpecs then
        classSpecs = {}
        local _, class = UnitClass("player")
        for _, spec in ipairs(ns.StatWeightDefaults) do
            if spec.class == class then classSpecs[#classSpecs + 1] = spec end
        end
    end
    return classSpecs
end

---@return table? spec by its key
function SW.Spec(key)
    if not byKey then Index() end
    return byKey[key]
end

-- The tree you spent the most talent points in, as a spec; nil before your first point. Forever
-- keeps one spec per class and its three classic trees as the talent tree's groups, which its
-- own talent frame reads the same way (C_Traits' group display and currency info). Read once
-- and again after a talent change.
local talentSpec, talentRead = nil, false
local watcher

local function ReadTalents()
    local trees = TREES[select(2, UnitClass("player"))]
    local configID = trees and C_ClassTalents and C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil end
    local groups, ids = C_Traits.GetGroupDisplayInfoByTreeID(treeID), {}
    for i, group in ipairs(groups) do ids[i] = group.groupID end
    local spentBy = {}
    for _, info in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids)) do
        local currency = info.currencyInfos and info.currencyInfos[1]
        spentBy[info.traitNodeGroupID] = currency and currency.spent or 0
    end
    local best, most = nil, 0
    for i, group in ipairs(groups) do
        local spent = spentBy[group.groupID] or 0
        if spent > most then best, most = trees[i], spent end
    end
    return best
end

---@return string? key the spec your talents say: the tree with the most points
function SW.TalentSpec()
    if talentRead then return talentSpec end
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
        watcher:SetScript("OnEvent", function() talentRead = false end)
    end
    talentSpec, talentRead = ReadTalents(), true
    return talentSpec
end

-- The spec you weigh by: the one picked on this module's page, else your talents' (Automatic),
-- else your BiS list's, else your class's first.
---@return string? key
function SW.ActiveSpec()
    local picked = S.Get("spec")
    local mine = SW.ClassSpecs()
    for _, spec in ipairs(mine) do
        if spec.key == picked then return picked end
    end
    local talents = SW.TalentSpec()
    if talents then return talents end
    local B = ns.BiS
    local listSpec = B and B.Lists and B.Lists.CurrentSpec()
    if listSpec and SW.Spec(listSpec.key) then return listSpec.key end
    return mine[1] and mine[1].key
end

-- Your changes, by spec: { [specKey] = { [stat] = weight } }.
local function Changes(create)
    local account = ns.AccountSettings()
    if create and type(account.statWeights) ~= "table" then account.statWeights = {} end
    return type(account.statWeights) == "table" and account.statWeights or nil
end

local merged = {}    -- spec key -> its weights with your changes, made on first use
local listeners = {}

---@return table<string, number>? weights the spec's, with your changes on top; read-only, shared
function SW.For(key)
    if not key then return nil end
    local weights = merged[key]
    if weights then return weights end
    local spec = SW.Spec(key)
    if not spec then return nil end
    weights = {}
    for stat, worth in pairs(spec.weights) do weights[stat] = worth end
    local changes = Changes()
    for stat, worth in pairs(changes and changes[key] or {}) do
        if STAT_KEY[stat] and type(worth) == "number" then weights[stat] = worth end
    end
    merged[key] = weights
    return weights
end

---@return number default the spec's own weight for the stat (0 where it has none)
function SW.Default(key, stat)
    local spec = SW.Spec(key)
    return spec and spec.weights[stat] or 0
end

---@return boolean changed whether you changed the spec's weight for the stat
function SW.Changed(key, stat)
    local changes = Changes()
    return changes ~= nil and changes[key] ~= nil and changes[key][stat] ~= nil
end

local function Changed(key)
    merged[key] = nil
    for i = 1, #listeners do listeners[i](key) end
end

--- Your weight for the stat, kept only where it differs from the default; nil is the default.
function SW.Set(key, stat, worth)
    if not (SW.Spec(key) and STAT_KEY[stat]) then return end
    local changes = Changes(true)
    if worth ~= nil and math.abs(worth - SW.Default(key, stat)) < 1e-9 then worth = nil end
    if worth == nil and not (changes[key] and changes[key][stat] ~= nil) then return end
    changes[key] = changes[key] or {}
    changes[key][stat] = worth
    if next(changes[key]) == nil then changes[key] = nil end
    Changed(key)
end

--- Every weight of the spec back to its default.
function SW.Reset(key)
    local changes = Changes()
    if not (changes and changes[key]) then return end
    changes[key] = nil
    Changed(key)
end

--- fn(specKey) whenever a spec's weights change.
function SW.OnChange(fn)
    listeners[#listeners + 1] = fn
end

-------------------------------------------------------------------------------
--  What an item is worth, and how much stronger it makes you
-------------------------------------------------------------------------------
local statsOf, cached = {}, 0
local CACHE_MAX = 600   -- items read; then it starts over, so hovering everything stays bounded

---@return table? stats the game's stats for an item ID or link, read once; nil while its data loads
function SW.Stats(item)
    local stats = statsOf[item]
    if stats then return stats end
    if type(item) == "number" and not IsItemDataCachedByID(item) then return nil end
    stats = GetItemStats(type(item) == "number" and "item:" .. item or item) or {}
    if cached >= CACHE_MAX then
        wipe(statsOf)
        cached = 0
    end
    statsOf[item], cached = stats, cached + 1
    return stats
end
local Stats = SW.Stats

--- What the stats are worth to the weights; a weapon's damage per second counts by dpsShare.
--- skipPrimary leaves your five stats out (Power has them from the game).
function SW.Worth(stats, weights, dpsShare, skipPrimary)
    local worth = 0
    for key, value in pairs(stats) do
        local mine = KEYS[key]
        if type(mine) == "table" then
            for i = 1, #mine do worth = worth + (weights[mine[i]] or 0) * value end
        elseif mine == "dps" then
            worth = worth + (weights.dps or 0) * value * (dpsShare or 0)
        elseif mine and not (skipPrimary and PRIMARY_KEY[mine]) then
            worth = worth + (weights[mine] or 0) * value
        end
    end
    return worth
end
local Worth = SW.Worth

---@return number share what a weapon's damage per second counts for in the slot
function SW.DpsShare(slot)
    local shares = select(2, UnitClass("player")) == "HUNTER" and HUNTER_DPS_SHARE or DPS_SHARE
    return shares[slot] or 0
end
local DpsShare = SW.DpsShare

-- Your weapon speeds and stats' worth (per weights table) as last read, for while the game
-- keeps your stats secret: a gain then is against your stats from just before. Forgotten when
-- your gear or level changes, so no gain is shown from numbers that no longer hold.
local lastMain, lastOff
local lastPower = setmetatable({}, { __mode = "k" })
local forgetter

local function Forget()
    wipe(lastPower)
    lastMain, lastOff = nil, nil
end

local function Remembering()
    if forgetter then return end
    forgetter = CreateFrame("Frame")
    forgetter:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    forgetter:RegisterEvent("PLAYER_LEVEL_UP")
    forgetter:SetScript("OnEvent", Forget)
end

--- What a point of weapon damage per swing (an enchant's) is worth in the slot: a point of the
--- weapon's damage per second over its speed.
function SW.SwingDamage(weights, slot)
    local main, off = lastMain, lastOff
    if not C_Secrets.ShouldUnitStatsBeSecret() then
        main, off = UnitAttackSpeed("player")
        lastMain, lastOff = main, off
        Remembering()
    end
    local speed = (slot == 17 and off or main) or SPEED
    return (weights.dps or 0) * DpsShare(slot) / (speed > 0 and speed or SPEED)
end

--- What your stats are worth now: your five stats as the game sums them (gear in them), and
--- the rest from what you wear. While the game keeps your stats secret, the worth last read for
--- these weights; nil if there is none yet.
function SW.Power(weights)
    if C_Secrets.ShouldUnitStatsBeSecret() then return lastPower[weights] end
    local power = 0
    for i, key in ipairs(PRIMARY) do power = power + (weights[key] or 0) * select(2, UnitStat("player", i)) end
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        local stats = link and Stats(link)
        if stats then power = power + Worth(stats, weights, DpsShare(slot), true) end
    end
    lastPower[weights] = power
    Remembering()
    return power
end

-- What you wear in the slot is worth: 0 for nothing, nil while it has not loaded.
local function WornWorth(slot, weights)
    local link = GetInventoryItemLink("player", slot)
    if not link then return 0 end
    local worn = Stats(link)
    return worn and Worth(worn, weights, DpsShare(slot))
end

--- How much stronger the item (an ID or a link) makes you in the slot, in percent of power,
--- over what you wear there; with also, a second slot it would empty (a two-hander's off
--- hand). nil while its data or what you wear has not loaded, or with nothing to measure by.
---@return number? percent
function SW.Gain(item, slot, weights, power, also)
    if not (weights and power and power > 0) then return nil end
    local stats = Stats(item)
    local worn = WornWorth(slot, weights)
    local other = also and WornWorth(also, weights) or 0
    if not (stats and worn and other) then return nil end
    return 100 * (Worth(stats, weights, DpsShare(slot)) - worn - other) / power
end

local MIN_GAIN = 0.5   -- percent: less than this is not an upgrade
local facts = {}       -- an item's { class, subclass, item level, required level }, refilled
local myClass

-- Your class wears its kind (the BiS List's rules: your armour type for your level, the
-- weapons you can learn); nil while its data has not loaded.
local function Usable(id, link)
    local canUse = ns.ClassCanUse
    if not canUse then return true end
    local _, _, _, equipLoc, _, itemClass, subclass = GetItemInfoInstant(id)
    local _, _, _, _, required = GetItemInfo(link or id)
    if not (itemClass and required) then return nil end
    myClass = myClass or select(2, UnitClass("player"))
    -- The game files a cloak under cloth; everyone wears one (the rules' data has them as 0).
    if equipLoc == "INVTYPE_CLOAK" then subclass = 0 end
    facts[1], facts[2], facts[4] = itemClass, subclass, required
    return canUse(myClass, facts)
end

--- The most the item makes you stronger in a slot it goes in, in percent of power (see Gain):
--- a ring or trinket against the weaker of the two you wear, a two-hander against both hands.
--- nil where it is no upgrade (under half a percent), you wear it, your class does not wear
--- its kind, or its data has not loaded. The gear tooltip's line and the bags' arrow.
---@param id number the item's ID
---@param link? string its link, for its own stats where it has random ones
---@return number? percent
function SW.BestGain(id, link, weights, power)
    local slots = Items.SlotsFor(id)
    if not (slots and weights) then return nil end
    for i = 1, #slots do
        if Items.Wearing(slots[i], id) then return nil end
    end
    if not Usable(id, link) then return nil end
    local twoHand = Items.IsTwoHand(id)
    local best
    for i = 1, #slots do
        local slot = slots[i]
        local gain = SW.Gain(link or id, slot, weights, power, twoHand and slot == 16 and 17 or nil)
        if gain and (not best or gain > best) then best = gain end
    end
    return best and best >= MIN_GAIN and best or nil
end

-------------------------------------------------------------------------------
--  Sharing a spec's weights as a line of text
-------------------------------------------------------------------------------
local PREFIX = "NFSW1"

---@return string text your changes to the spec's weights: "NFSW1:fire-mage:fire=1.2,spi=0"; with
--- none, the spec alone (Naowh's weights)
function SW.Export(key)
    local weights = SW.For(key)
    if not weights then return "" end
    local parts = {}
    for _, stat in ipairs(SW.STATS) do
        if SW.Changed(key, stat[1]) then parts[#parts + 1] = ("%s=%g"):format(stat[1], weights[stat[1]] or 0) end
    end
    return PREFIX .. ":" .. key .. ":" .. table.concat(parts, ",")
end

-- A simulator's export, the string stat-weight tools share, as WoWSims' EP export writes it:
-- ( <tool>: v1: "Name": Class=Rogue, Agility=2.1, Ap=1, HitRating=13.2 ). A percent stat is
-- worth its number per 1%, as ours are. Its keys -> ours; a spell and a melee version of a
-- stat count for the one we have, summed. Keys we have no stat for are left out.
local SIM_KEYS = {
    strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi",
    ap = "ap", rap = "rap", dps = "dps", meleedps = "dps", mainhanddps = "dps", onehanddps = "dps",
    twohanddps = "dps", hitrating = "hit", spellhitrating = "hit", critrating = "crit",
    spellcritrating = "scrit", hasterating = "haste", spellhasterating = "haste", spelldamage = "spell",
    spellpower = "spell", healing = "heal", mp5 = "mp5", armor = "armor", defenserating = "def",
    dodgerating = "dodge", blockrating = "block", firespelldamage = "fire", frostspelldamage = "frost",
    shadowspelldamage = "shadow", naturespelldamage = "nature", arcanespelldamage = "arcane",
    holyspelldamage = "holy",
}
local SIM_STRING = '^%s*%(%s*%a+%s*:%s*v1%s*:%s*"([^"]*)"%s*:%s*(.-)%s*%)%s*$'

-- A simulator's weights for key: every stat it names, the rest to 0.
local function ImportSim(name, body, key)
    local spec = SW.Spec(key)
    if not spec then return false, "Pick your spec first." end
    local _, class = UnitClass("player")
    local read, count = {}, 0
    for part in body:gmatch("[^,]+") do
        local stat, value = part:match("^%s*(%w+)%s*=%s*(%S-)%s*$")
        stat = stat and stat:lower()
        if stat == "class" then
            if value:upper():gsub("%s", "") ~= class then
                return false, ("Those weights are for a %s."):format(value)
            end
        else
            -- A hunter's weapon is the ranged one; anyone else's ranged weapon is not weighed.
            local mine = stat == "rangeddps" and (class == "HUNTER" and "dps") or SIM_KEYS[stat]
            local worth = tonumber(value)
            if mine and worth and worth > 0 then
                read[mine] = (read[mine] or 0) + worth
                count = count + 1
            end
        end
    end
    if count == 0 then return false, "Those weights name no stat it can read." end
    for _, stat in ipairs(SW.STATS) do SW.Set(key, stat[1], read[stat[1]] or 0) end
    return true, ("%s imported for %s."):format(name ~= "" and name or "The weights", spec.name)
end

--- Reads pasted weights: a Naowh line (the spec's weights back to the defaults, then the
--- line's changes on top), or a simulator's export (WoWSims' EP export), which replaces the
--- weights of key, the spec on the page.
---@return boolean ok
---@return string message what happened, for chat
function SW.Import(text, key)
    local name, simBody = (text or ""):match(SIM_STRING)
    if simBody then return ImportSim(name, simBody, key) end
    local lineKey, body = (text or ""):match("^%s*" .. PREFIX .. ":([%w%-]+):([%w=.,%-]*)%s*$")
    local spec = lineKey and SW.Spec(lineKey)
    if not spec then return false, "That is not a Naowh stat weights line, nor a simulator's export." end
    local read = {}
    for part in body:gmatch("[^,]+") do
        local stat, worth = part:match("^(%w+)=([%d.]+)$")
        worth = tonumber(worth)
        if not (STAT_KEY[stat] and worth and worth < 1000) then
            return false, "That line has a weight it cannot read: " .. part .. "."
        end
        read[stat] = worth
    end
    SW.Reset(lineKey)
    for stat, worth in pairs(read) do SW.Set(lineKey, stat, worth) end
    return true, ("Weights for %s imported."):format(spec.name)
end
