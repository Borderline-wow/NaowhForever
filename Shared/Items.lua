-------------------------------------------------------------------------------
--  Items.lua -- item and gear helpers every module can use (ns.Shared.Items): an item's ID
--  from whatever names it, its name and quality colour, what you keep, the slots it goes in,
--  a call once its data has loaded, and the items the server would not send this session.
--  Functions only, no frames.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Items = ns.Shared.Items
local St = ns.Shared.Style

local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemNameByID = C_Item.GetItemNameByID
local GetItemQualityByID = C_Item.GetItemQualityByID
local GetItemCount = C_Item.GetItemCount
local IsItemDataCachedByID = C_Item.IsItemDataCachedByID

local EMPTY = {}

-- An item ID from a number, an item link, "item=12345" (a Wowhead URL) or "12345".
---@return number?
function Items.IDFrom(value)
    if type(value) == "number" then return value end
    local text = tostring(value)
    return tonumber(text:match("item[:=](%d+)") or text:match("^%s*(%d+)%s*$"))
end

local refused = {}

function Items.Refuse(itemID)
    refused[itemID] = true
end

function Items.Refused(itemID)
    return refused[itemID] == true
end

-- Its name, or "item 12345" while the client has not loaded it.
function Items.Name(itemID)
    return GetItemNameByID(itemID) or ("item " .. itemID)
end

-- Its quality's colour escape ("|cff0070dd"), white while unknown.
function Items.QualityHex(itemID)
    local quality = GetItemQualityByID(itemID)
    local color = quality and ITEM_QUALITY_COLORS[quality]
    return color and color.hex or "|cffffffff"
end

-- Its quality's colour ({ r, g, b }), nil while unknown.
function Items.QualityColor(itemID)
    local quality = GetItemQualityByID(itemID)
    return quality and ITEM_QUALITY_COLORS[quality]
end

-- Where you keep it: In Bag, In Bank, or "" (what you wear has its own mark). In the worn
-- green, muted: a state of the item, quieter than its name.
local KEPT_CODE = ("|cff%02x%02x%02x"):format(St.HAVE_RGB.r * 200, St.HAVE_RGB.g * 200, St.HAVE_RGB.b * 200)
Items.KEPT_CODE = KEPT_CODE
local IN_BAG, IN_BANK = KEPT_CODE .. "In Bag|r", KEPT_CODE .. "In Bank|r"

function Items.Kept(itemID)
    if GetItemCount(itemID) > 0 then return IN_BAG end
    if GetItemCount(itemID, true) > 0 then return IN_BANK end
    return ""
end

-- You have it: worn, in your bags or in your bank.
function Items.Owned(itemID)
    return GetItemCount(itemID, true) > 0 or C_Item.IsEquippedItem(itemID)
end

-------------------------------------------------------------------------------
--  Your loot lines in chat (CHAT_MSG_LOOT): the start of the game's line for loot you
--  receive ("You receive loot: "), and for items handed to you ("You receive item: ": quest
--  rewards, purchases), in the client's language.
-------------------------------------------------------------------------------
local function LineStart(format)
    local start = type(format) == "string" and format:match("^(.-)%%s")
    return start ~= "" and start or nil
end
local LOOTED, HANDED = LineStart(LOOT_ITEM_SELF), LineStart(LOOT_ITEM_PUSHED_SELF)
Items.READS_LOOT = LOOTED ~= nil

-- The item in a line of yours: loot, or with handed set an item handed to you too. A secret
-- line (in an encounter) is nobody's.
---@return string? link
---@return number? itemID
function Items.YourLoot(text, handed)
    if issecretvalue(text) or type(text) ~= "string" then return end
    if not ((LOOTED and text:find(LOOTED, 1, true) == 1)
        or (handed and HANDED and text:find(HANDED, 1, true) == 1)) then return end
    local link, id = text:match("(|c[^|]*|Hitem:(%d+).-|h|r)")
    return link, tonumber(id)
end

-------------------------------------------------------------------------------
--  Gear slots, by inventory slot number
-------------------------------------------------------------------------------
-- Every gear slot, in the order a list of them reads, and their names.
Items.GEAR_SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
    { 11, "Ring 1" }, { 12, "Ring 2" }, { 13, "Trinket 1" }, { 14, "Trinket 2" },
    { 16, "Main Hand" }, { 17, "Off Hand" }, { 18, "Ranged" },
}
Items.SLOT_NAME = {}
for _, s in ipairs(Items.GEAR_SLOTS) do Items.SLOT_NAME[s[1]] = s[2] end

-- Where an item can go, by its equip location, first choice first.
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- The slots it goes in, first choice first (shared, read-only); nil for what is not worn.
---@return number[]?
function Items.SlotsFor(itemID)
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    return EQUIP_SLOTS[equipLoc]
end
local SlotsFor = Items.SlotsFor

function Items.Fits(itemID, slot)
    local slots = SlotsFor(itemID) or EMPTY
    for i = 1, #slots do
        if slots[i] == slot then return true end
    end
    return false
end

function Items.IsTwoHand(itemID)
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    return equipLoc == "INVTYPE_2HWEAPON"
end

-- The slot's pair: the other ring, the other trinket.
local PAIR = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

-- You wear it in the slot, or in its pair (a ring is worn in either ring slot).
function Items.Wearing(slot, itemID)
    if GetInventoryItemID("player", slot) == itemID then return true end
    local pair = PAIR[slot]
    return pair ~= nil and GetInventoryItemID("player", pair) == itemID
end

-------------------------------------------------------------------------------
--  Weapons in short, as players say them ("1h Sword", "Bow"), by the game's weapon subclass
--  (Enum.ItemWeaponSubclass), so any client language gets them; one that only goes in one
--  hand says which ("MH Sword", "OH Dagger").
-------------------------------------------------------------------------------
Items.ONE_HAND_ONLY = { INVTYPE_WEAPONMAINHAND = "MH", INVTYPE_WEAPONOFFHAND = "OH" }
local WEAPON_SHORT = {
    [0] = { "Axe", "1h" }, [1] = { "Axe", "2h" }, [2] = { "Bow" }, [3] = { "Gun" },
    [4] = { "Mace", "1h" }, [5] = { "Mace", "2h" }, [6] = { "Polearm" }, [7] = { "Sword", "1h" },
    [8] = { "Sword", "2h" }, [10] = { "Staff" }, [13] = { "Fist Weapon" }, [15] = { "Dagger" },
    [16] = { "Thrown" }, [18] = { "Crossbow" }, [19] = { "Wand" },
}
local weaponNames = {}   -- subclass -> hand -> its short name, made once each

---@return string? name nil for a weapon type with no short name
function Items.WeaponName(subclass, equipLoc)
    local short = WEAPON_SHORT[subclass]
    if not short then return nil end
    local hand = Items.ONE_HAND_ONLY[equipLoc] or short[2] or ""
    local byHand = weaponNames[subclass]
    if not byHand then
        byHand = {}
        weaponNames[subclass] = byHand
    end
    local name = byHand[hand]
    if not name then
        name = hand ~= "" and hand .. " " .. short[1] or short[1]
        byHand[hand] = name
    end
    return name
end

-- A weapon's short name from the item itself, which the client knows without loading it.
function Items.WeaponOf(itemID)
    local _, _, _, equipLoc, _, classID, subclass = GetItemInfoInstant(itemID)
    return classID == 2 and Items.WeaponName(subclass, equipLoc) or nil
end

-------------------------------------------------------------------------------
--  Waiting on item data
-------------------------------------------------------------------------------
-- Runs fn, at most once a frame, as the items in ids load. An item the server fails to load
-- never calls back, so a ContinuableContainer over ids would never finish. Nothing waits on
-- items already loaded.
function Items.OnLoaded(ids, fn)
    local queued
    local function Run()
        queued = false
        fn()
    end
    local function Refresh()
        if queued then return end
        queued = true
        C_Timer.After(0, Run)
    end
    for i = 1, #ids do
        if not IsItemDataCachedByID(ids[i]) then ItemEventListener:AddCallback(ids[i], Refresh) end
    end
end
