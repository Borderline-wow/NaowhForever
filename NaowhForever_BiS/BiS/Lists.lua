-------------------------------------------------------------------------------
--  Lists.lua -- your BiS lists (ns.BiS.Lists): kept per class in the account store, so every
--  character of a class shares them and none travels in an exported profile; each character
--  remembers which one it uses. The picks, and the ns entry points other modules change
--  them with. Rules only, no frames.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local R = B.Rankings
local Items = ns.Shared.Items
local SLOT_NAME = Items.SLOT_NAME
local Picks, Store = B.Picks, B.Store

local L = {}
B.Lists = L

local lookup   -- itemID -> its best pick number (1 is BiS), rebuilt when the list changes

-------------------------------------------------------------------------------
--  Storage
-------------------------------------------------------------------------------
local function ClassLists()
    local account = ns.AccountSettings()
    local _, class = UnitClass("player")
    account.bisLists = account.bisLists or {}
    local store = account.bisLists[class] or { lists = {}, nextID = 1 }
    account.bisLists[class] = store
    account.bisActive = account.bisActive or {}
    return store, account
end

local function AddList(store, list)
    list.id = store.nextID
    store.nextID = store.nextID + 1
    store.lists[#store.lists + 1] = list
    return list
end

local function Taken(store, name, except)
    for _, l in ipairs(store.lists) do
        if l ~= except and l.name:lower() == name:lower() then return true end
    end
    return false
end

local function FreeName(store, name)
    local try, n = name, 1
    while Taken(store, try) do
        n = n + 1
        try = ("%s %d"):format(name, n)
    end
    return try
end

local function CharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function Use(list)
    local _, account = ClassLists()
    account.bisActive[CharKey()] = list.id
end

local function FreeSlot(slots, itemID)
    for _, s in ipairs(Items.SlotsFor(itemID) or {}) do
        if not slots[s] then return s end
    end
end
L.FreeSlot = FreeSlot

-- A flat item list from before slots: each item into the first slot it fits, and what no
-- longer fits named in chat once.
local function SlotItems(list)
    local dropped = {}
    list.slots = {}
    for _, id in ipairs(list.items or {}) do
        local slot = FreeSlot(list.slots, id)
        if slot then list.slots[slot] = id else dropped[#dropped + 1] = Items.Name(id) end
    end
    list.items = nil
    if #dropped > 0 then
        ns.Print("Your BiS list now keeps a ranked list per slot. These did not fit: "
            .. table.concat(dropped, ", "))
    end
end

-- The list this character uses. Older saved lists are moved on the way: a character's own
-- list from before lists were shared joins its class's (named for the character unless it
-- had a name of its own), a flat item list is put in slots, and the unordered next picks of
-- the 0.5.12 test builds go in ranked order.
function L.List()
    local store, account = ClassLists()
    local key = CharKey()
    local old = account.bis and account.bis[key]
    if old then
        old.name = FreeName(store, (not old.name or old.name == "My BiS") and UnitName("player") or old.name)
        account.bisActive[key] = AddList(store, old).id
        account.bis[key] = nil
    end
    local list
    for _, l in ipairs(store.lists) do
        if l.id == account.bisActive[key] then list = l end
    end
    list = list or store.lists[1] or AddList(store, { name = "My BiS" })
    account.bisActive[key] = list.id
    list.extra = list.extra or {}
    if not list.slots then SlotItems(list) end
    for slot, set in pairs(list.extra) do
        if not set[1] then
            list.extra[slot] = R.Ranked(set, R.Ranking(list.spec, slot))
            Store(list, slot, Picks(list, slot))
        end
    end
    return list
end
local List = L.List

-- Each spec keeps its own picks on a list: switching parks the current ones under bySpec.
local function SwitchSpec(key)
    local list = List()
    local first = R.ClassSpecs()[1]
    local previous = list.spec or (first and first.key)
    if not key or key == previous then
        list.spec = previous
        return list
    end
    list.bySpec = list.bySpec or {}
    if previous then list.bySpec[previous] = { slots = list.slots, extra = list.extra } end
    local picks = list.bySpec[key] or { slots = {}, extra = {} }
    list.slots, list.extra, list.spec = picks.slots, picks.extra, key
    return list
end

function L.CurrentSpec()
    local specs = R.ClassSpecs()
    local key = List().spec
    for _, spec in ipairs(specs) do
        if spec.key == key then return spec end
    end
    return specs[1]
end

local function Rebuild()
    lookup = {}
    local list = List()
    for slot in pairs(SLOT_NAME) do
        for rank, id in ipairs(Picks(list, slot)) do
            if not lookup[id] or rank < lookup[id] then lookup[id] = rank end
        end
    end
end

local function Changed()
    Rebuild()
    B.ListChanged()
end

-- Names show in chat and tooltips, so escape codes are neutralised.
local function CleanName(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil end
    return (name:sub(1, 40):gsub("|", "||"))
end

-- A new list, switched to: from Sharing, a profile pack, or New List.
function L.AddList(name, spec, slots, extra)
    local store = ClassLists()
    local list = AddList(store, { name = FreeName(store, name), spec = spec, slots = slots, extra = extra })
    Use(list)
    Changed()
    return list
end

-------------------------------------------------------------------------------
--  Entry points
-------------------------------------------------------------------------------
---@return number? rank its best pick number on your list (1 is BiS); nil with the module off
function ns.IsBisItem(itemID)
    if not (B.On() and itemID) then return nil end
    if not lookup then Rebuild() end
    return lookup[itemID]
end

-- The slot that has it as its best pick.
---@return number? slot
function L.SlotOf(itemID)
    local list, best, bestRank = List(), nil, nil
    for slot in pairs(SLOT_NAME) do
        local picks = Picks(list, slot)
        for rank = 1, #picks do
            if picks[rank] == itemID and (not bestRank or rank < bestRank) then best, bestRank = slot, rank end
        end
    end
    return best
end

function ns.BisListIsEmpty()
    return next(List().slots) == nil
end

function ns.SetBisSpec(key)
    for _, spec in ipairs(R.ClassSpecs()) do
        if spec.key == key then
            SwitchSpec(key)
            return Changed()
        end
    end
end

-- For a list menu: id -> name in the order they were made, and the one in use.
function ns.BisListChoices()
    local id = List().id
    local values, order = {}, {}
    for _, l in ipairs((ClassLists()).lists) do
        values[l.id], order[#order + 1] = l.name, l.id
    end
    return values, order, id
end

function ns.SelectBisList(id)
    for _, l in ipairs((ClassLists()).lists) do
        if l.id == id then
            Use(l)
            return Changed()
        end
    end
end

-- An empty list, ranked for the spec the current one is ranked for, and switched to.
function ns.NewBisList(name)
    name = CleanName(name)
    if not name then return false, "the name is empty" end
    if Taken((ClassLists()), name) then return false, "that name is taken" end
    local current = L.CurrentSpec()
    L.AddList(name, current and current.key, {}, {})
    return true
end

function ns.RenameBisList(name)
    name = CleanName(name)
    if not name then return false, "the name is empty" end
    local list = List()
    if Taken((ClassLists()), name, list) then return false, "that name is taken" end
    list.name = name
    Changed()
    return true
end

-- Every character using it moves to the class's first list, or a new empty one.
function ns.DeleteBisList()
    local list = List()
    local lists = (ClassLists()).lists
    for i, l in ipairs(lists) do
        if l == list then
            table.remove(lists, i)
            break
        end
    end
    Changed()
end

-- Each change below reads the slot's picks, changes them and stores them back.
local function Edit(list, slot, change, ...)
    local picks = Picks(list, slot)
    change(picks, ...)
    Store(list, slot, picks)
end

local function IndexOf(picks, itemID)
    for i = 1, #picks do
        if picks[i] == itemID then return i end
    end
end

local function Append(picks, itemID)
    if not IndexOf(picks, itemID) then picks[#picks + 1] = itemID end
end

local function Drop(picks, itemID)
    local i = IndexOf(picks, itemID)
    if i then table.remove(picks, i) end
end

-- Swaps it with the one above (step -1) or below (step 1).
local function Step(picks, itemID, step)
    local i = IndexOf(picks, itemID)
    local j = i and i + step
    if j and picks[j] then picks[i], picks[j] = picks[j], itemID end
end

local function Top(picks, itemID)
    local i = IndexOf(picks, itemID)
    if i and i > 1 then
        table.remove(picks, i)
        table.insert(picks, 1, itemID)
    end
end

function ns.AddBisPick(slot, itemID)
    Edit(List(), slot, Append, itemID)
    Changed()
end

function ns.RemoveBisPick(slot, itemID)
    Edit(List(), slot, Drop, itemID)
    Changed()
end

function ns.MoveBisPick(slot, itemID, step)
    Edit(List(), slot, Step, itemID, step)
    Changed()
end

-- Its slot's BiS.
function ns.TopBisPick(slot, itemID)
    Edit(List(), slot, Top, itemID)
    Changed()
end

-- The BiS in the first empty slot the item fits, else the next pick in its first slot.
function ns.AddBisItem(value)
    local id = Items.IDFrom(value)
    local fits = id and Items.SlotsFor(id)
    if not fits then
        ns.Print("That is not an item you can equip.")
        return
    end
    if not lookup then Rebuild() end
    if lookup[id] then return end
    local list = List()
    local slot = FreeSlot(list.slots, id)
    ns.AddBisPick(slot or fits[1], id)
    if slot then
        ns.Print(("Added %s to your BiS %s."):format(Items.Name(id), SLOT_NAME[slot]))
    else
        ns.Print(("Added %s to your BiS %s as #%d."):format(Items.Name(id), SLOT_NAME[fits[1]],
            #Picks(list, fits[1])))
    end
end

-- The BiS in every slot it is listed in.
function ns.PromoteBisItem(itemID)
    local list = List()
    for slot in pairs(SLOT_NAME) do Edit(list, slot, Top, itemID) end
    Changed()
end

function ns.RemoveBisItem(itemID)
    local list = List()
    for slot in pairs(SLOT_NAME) do Edit(list, slot, Drop, itemID) end
    Changed()
end
