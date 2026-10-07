-------------------------------------------------------------------------------
--  Sharing.lua -- a BiS list as a string to share, and back (ns.ExportBisList,
--  ns.ImportBisList, which profile packs call too). Parsed as data, never run.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local R, L = B.Rankings, B.Lists
local Items = ns.Shared.Items
local SLOT_NAME, Fits = Items.SLOT_NAME, Items.Fits

local PREFIX = "!NBIS1!"
local VERSION = 4
local LIMITS = { maxChars = 100000, maxBytes = 1048576, maxDepth = 8, maxValues = 20000 }

local function Codec()
    return LibStub("LibSerialize"), LibStub("LibDeflate")
end

function ns.ExportBisList()
    local LS, LD = Codec()
    local list = L.List()
    return PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize({
        v = VERSION, name = list.name, spec = list.spec, slots = list.slots, extra = list.extra,
    })))
end

local function ValidID(id)
    return type(id) == "number" and id > 0 and id < 2 ^ 31 and id == math.floor(id)
end

-- Version 1: a flat item list, placed as an old saved list is. 2: BiS picks only. 3: next
-- picks unordered, put in the spec's ranked order. 4: next picks in order.
local function Decode(text)
    local body = type(text) == "string" and text:match("^%s*" .. PREFIX:gsub("!", "%%!") .. "(%S+)%s*$")
    local data = body and ns.Shared.Decode.String(body, LIMITS)
    if type(data) ~= "table" then return end
    local name = ns.Shared.Decode.Text(data.name, 40)
    if not name or name == "" then name = "Imported BiS" end
    local spec = ns.Shared.Decode.Text(data.spec, 40)
    local list = { slots = {}, extra = {} }
    if data.v == 1 and type(data.items) == "table" then
        for _, id in ipairs(data.items) do
            local slot = ValidID(id) and L.FreeSlot(list.slots, id)
            if slot then list.slots[slot] = id end
        end
    elseif (data.v == 2 or data.v == 3 or data.v == 4) and type(data.slots) == "table" then
        for slot, id in pairs(data.slots) do
            if SLOT_NAME[slot] and ValidID(id) and Fits(id, slot) then list.slots[slot] = id end
        end
        for slot, more in pairs(data.v > 2 and type(data.extra) == "table" and data.extra or {}) do
            if SLOT_NAME[slot] and type(more) == "table" then
                if data.v == 3 then
                    local set = {}
                    for id, on in pairs(more) do
                        if on == true and ValidID(id) then set[id] = true end
                    end
                    more = R.Ranked(set, R.Ranking(spec, slot))
                end
                local picks = B.Picks(list, slot)
                local seen = {}
                for _, id in ipairs(picks) do seen[id] = true end
                for _, id in ipairs(more) do
                    if ValidID(id) and Fits(id, slot) and not seen[id] then
                        seen[id] = true
                        picks[#picks + 1] = id
                    end
                end
                B.Store(list, slot, picks)
            end
        end
    else
        return
    end
    return name, list.slots, list.extra, spec
end

-- Added as a new list and switched to; quiet skips asking first.
function ns.ImportBisList(text, quiet)
    local name, slots, extra, spec = Decode(text)
    if not name then
        ns.Print("That is not a Naowh BiS list.")
        return false
    end
    local count = 0
    for _ in pairs(slots) do count = count + 1 end
    for _, rest in pairs(extra) do count = count + #rest end
    local function Apply()
        local list = L.AddList(name, spec, slots, extra)
        ns.Print(("Imported %s: %d items."):format(list.name, count))
    end
    if quiet then
        Apply()
    else
        ns.Confirm(("Add %s (%d items) as a new BiS list?"):format(name, count), Apply)
    end
    return true
end
