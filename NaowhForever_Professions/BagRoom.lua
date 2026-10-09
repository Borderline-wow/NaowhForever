-- BagRoom.lua: how many crafts of a recipe the bags have room for, which caps Create All (ns.CraftBagRoom).
local ns = _G.NaowhForever

local STACK_INDEX = 8
local REAGENT_INDEX = 17
local DEFAULT_BAGS = 4
local GENERAL_BAG = 0

local NONE = {}
local bagStacks, bagLists, bagRecords, memo = {}, {}, {}, {}

local function SmallestFirst(a, b)
    return a.count < b.count
end

local function BagTakes(bag, family, isReagent)
    if Enum.BagIndex and bag == Enum.BagIndex.ReagentBag then return isReagent end
    local _, bagType = C_Container.GetContainerNumFreeSlots(bag)
    return (bagType or GENERAL_BAG) == GENERAL_BAG or bit.band(family, bagType) ~= 0
end

local function StackSize(output)
    return C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(output)
        or select(STACK_INDEX, C_Item.GetItemInfo(output))
end

local function ResetStacks(reagents)
    wipe(bagStacks)
    for i, r in ipairs(reagents or NONE) do
        local list = bagLists[i] or {}
        bagLists[i] = list
        wipe(list)
        bagStacks[r.itemID] = list
    end
end

local function ReadBags(output, stack, family, isReagent)
    local free, room, used = 0, 0, 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or DEFAULT_BAGS) do
        local takes = BagTakes(bag, family, isReagent)
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if not info then
                if takes then free = free + 1 end
            elseif info.itemID == output then
                if takes then room = room + math.max(0, stack - (info.stackCount or 0)) end
            elseif bagStacks[info.itemID] then
                local list = bagStacks[info.itemID]
                used = used + 1
                local rec = bagRecords[used] or {}
                bagRecords[used] = rec
                rec.count, rec.takes = info.stackCount or 1, takes
                list[#list + 1] = rec
            end
        end
    end
    for _, list in pairs(bagStacks) do table.sort(list, SmallestFirst) end
    return free, room
end

local function UseReagents(reagents, free)
    for _, r in ipairs(reagents or NONE) do
        local need, list = r.need, bagStacks[r.itemID]
        for _, s in ipairs(list) do
            if need <= 0 then break end
            local take = math.min(need, s.count)
            if take > 0 then
                s.count, need = s.count - take, need - take
                if s.count == 0 and s.takes then free = free + 1 end
            end
        end
    end
    return free
end

local function BagRoom(output, made, reagents, limit)
    if not output or not limit or limit < 1 then return end
    local stack = StackSize(output)
    if not stack or stack < 1 then return end
    made = math.max(made or 1, 1)
    local family = C_Item.GetItemFamily and C_Item.GetItemFamily(output) or 0
    local isReagent = select(REAGENT_INDEX, C_Item.GetItemInfo(output)) == true
    ResetStacks(reagents)
    local free, room = ReadBags(output, stack, family, isReagent)
    for n = 1, limit do
        if room >= made then
            room = room - made
        else
            local slots = math.ceil((made - room) / stack)
            if free < slots then return n - 1 end
            free = free - slots
            room = room + slots * stack - made
        end
        free = UseReagents(reagents, free)
    end
    return limit
end

function ns.CraftBagRoom(output, made, reagents, limit)
    local changes = ns.ProfBagChanges
    if changes and memo.changes == changes and memo.output == output and memo.made == made
        and memo.reagents == reagents and memo.limit == limit then
        return memo.room
    end
    local room = BagRoom(output, made, reagents, limit)
    memo.changes, memo.output, memo.made, memo.reagents, memo.limit, memo.room =
        changes, output, made, reagents, limit, room
    return room
end
