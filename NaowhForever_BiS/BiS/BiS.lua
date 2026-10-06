-------------------------------------------------------------------------------
--  BiS.lua -- the BiS List's core (ns.BiS): its settings, a list's shape, and telling the
--  module when your list changed. Rankings.lua has the rankings and class rules, Lists.lua
--  your lists, Sharing.lua the share strings, Alerts.lua the marks on tooltips and loot;
--  View/ draws a page and UI/ is where it shows. No frames here.
--
--  Only the entry points other modules call are on ns (ns.IsBisItem, ns.AddBisItem,
--  ns.OpenBisWindow...); the rest hangs off ns.BiS.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Items = ns.Shared.Items

local B = { Settings = ns.QoLSettings }
ns.BiS = B

function B.On()
    return B.Settings.Get("bis") == true
end

-------------------------------------------------------------------------------
--  A list: { id, name, spec, slots = { [slot] = itemID }, extra = { [slot] = { itemID... } },
--  bySpec = { [spec] = { slots, extra } } }. slots[slot] is a slot's BiS, extra[slot] its
--  next picks in order.
-------------------------------------------------------------------------------
-- A slot's picks in order, BiS first: in out (wiped) when given, else a new table.
function B.Picks(list, slot, out)
    out = out and wipe(out) or {}
    out[1] = list.slots[slot]
    local extra = list.extra[slot]
    if extra then
        for i = 1, #extra do out[#out + 1] = extra[i] end
    end
    return out
end

function B.Store(list, slot, picks)
    local rest = {}
    for i = 2, #picks do rest[#rest + 1] = picks[i] end
    list.slots[slot], list.extra[slot] = picks[1], rest[1] and rest or nil
end

-- A two-hander as the main hand's BiS leaves the off hand unused: its picks are kept, not
-- counted, until the main hand's BiS is a one-hander again.
function B.OffHandIdle(list)
    return list.slots[16] ~= nil and Items.IsTwoHand(list.slots[16])
end

-------------------------------------------------------------------------------
--  Changes
-------------------------------------------------------------------------------
local listeners = {}

-- fn() after your list changed: a pick, another list, another spec.
function B.OnListChange(fn)
    listeners[#listeners + 1] = fn
end

function B.ListChanged()
    for i = 1, #listeners do listeners[i]() end
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end
