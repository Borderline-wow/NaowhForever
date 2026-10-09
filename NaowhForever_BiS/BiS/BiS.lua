-- BiS.lua: the BiS List's core (ns.BiS): its settings, a list's shape, and its change listeners.
local ns = _G.NaowhForever

local Items = ns.Shared.Items

local listeners = {}

local B = { Settings = ns.QoLSettings }
ns.BiS = B

function B.On()
    return B.Settings.Get("bis") == true
end

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

function B.OffHandIdle(list)
    local main = list.slots[B.C.MAIN_HAND]
    return main ~= nil and Items.IsTwoHand(main)
end

function B.OnListChange(fn)
    listeners[#listeners + 1] = fn
end

function B.ListChanged()
    for i = 1, #listeners do listeners[i]() end
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end
