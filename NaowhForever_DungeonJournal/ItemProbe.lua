-------------------------------------------------------------------------------
--  ItemProbe.lua -- /nf itemprobe, a tool for the Journal's data: asks the server for every
--  item the Journal lists, in Forever or not yet, and keeps which it sent and which it would
--  not in NaowhForeverDB.journalProbe, for Tools/items_in_game.py. Nothing is made until it
--  is run; it stops listening once every item has answered.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal

local GetItemNameByID = C_Item.GetItemNameByID
local RequestLoadItemDataByID = C_Item.RequestLoadItemDataByID

local BATCH = 50
local WAIT = 5

local frame, queue, pending, loads, refused, at, waiting, generation
local running = false

local function Sorted(set)
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    table.sort(list)
    return list
end

local function Finish()
    running = false
    frame:UnregisterAllEvents()
    local _, build = GetBuildInfo()
    local sv = _G.NaowhForeverDB
    if type(sv) == "table" then
        sv.journalProbe = { build = tonumber(build) or 0, loads = Sorted(loads), refused = Sorted(refused) }
    end
    local sent, kept = 0, 0
    for _ in pairs(loads) do sent = sent + 1 end
    for _ in pairs(refused) do kept = kept + 1 end
    ns.Print(("Item probe: %d items load, %d are not in Forever. /reload to save them, then run "
        .. "Tools/items_in_game.py."):format(sent, kept))
end

local function Answer(id, sent)
    if not pending[id] then return end
    pending[id] = nil
    waiting = waiting - 1
    if sent then loads[id] = true else refused[id] = true end
end

local Next

-- A batch's time is up: an item still without an answer counts by whether it has a name now.
local function TimeUp(asked)
    if asked ~= generation or not running then return end
    for id in pairs(pending) do Answer(id, GetItemNameByID(id) ~= nil) end
    Next()
end

Next = function()
    if waiting > 0 then return end
    if at > #queue then return Finish() end
    generation = generation + 1
    for i = at, math.min(at + BATCH - 1, #queue) do
        local id = queue[i]
        if GetItemNameByID(id) then
            loads[id] = true
        else
            pending[id] = true
            waiting = waiting + 1
            RequestLoadItemDataByID(id)
        end
    end
    at = at + BATCH
    if waiting == 0 then return Next() end
    local asked = generation
    C_Timer.After(WAIT, function() TimeUp(asked) end)
end

local function OnEvent(_, _, id, success)
    Answer(id, success == true)
    if waiting == 0 then Next() end
end

function ns.JournalItemProbe()
    if running then return ns.Print("Item probe: still running.") end
    local seen = {}
    for id in pairs(J.Items) do seen[id] = true end
    for id in pairs(J.NotYet) do seen[id] = true end
    queue, pending, loads, refused = Sorted(seen), {}, {}, {}
    at, waiting, generation, running = 1, 0, 0, true
    frame = frame or CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    ns.Print(("Item probe: asking for %d items."):format(#queue))
    Next()
end
