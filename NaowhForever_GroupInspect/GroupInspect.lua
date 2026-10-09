-- GroupInspect.lua: Group Inspect's namespace (ns.GroupInspect), its shared state, its change callbacks and the API its views read.
local ns = _G.NaowhForever
local S = ns.QoLSettings

local GI = {}
ns.GroupInspect = GI

local state = {
    open = false, previewOn = false, previewMode = "party",
    records = {}, members = {}, count = 0,
    preview = { party = {}, raid = {} }, previewBy = {},
}
GI.state = state

local listeners = {}
local dirty, batch = {}, {}
local rosterDirty, flushQueued = false, false

function GI.Readable(value)
    return value ~= nil and not issecretvalue(value)
end

function GI.On()
    return S.Get("enabled") == true and S.Get("groupInspect") == true
end

function GI.IsOpen()
    return state.open
end

GI.StatsFromGear = GI.StatsFromGear or function() end

local function Flush()
    flushQueued = false
    if not (state.open or state.previewOn) then
        rosterDirty = false
        wipe(dirty)
        return
    end
    if rosterDirty then
        rosterDirty = false
        wipe(dirty)
        for i = 1, #listeners do listeners[i](nil) end
        return
    end
    dirty, batch = batch, dirty
    for guid in pairs(batch) do
        for i = 1, #listeners do listeners[i](guid) end
    end
    wipe(batch)
end

function GI.Changed(guid)
    if not (state.open or state.previewOn) then return end
    if guid == nil then rosterDirty = true else dirty[guid] = true end
    if flushQueued then return end
    flushQueued = true
    C_Timer.After(0, Flush)
end

function GI.OnChange(fn)
    listeners[#listeners + 1] = fn
end

function GI.Mode()
    if state.previewOn then return state.previewMode end
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

function GI.Members()
    if state.previewOn then return state.preview[state.previewMode] end
    return state.members
end

function GI.Count()
    return #GI.Members()
end

function GI.Member(guid)
    if state.previewOn then
        if state.previewMode == "raid" then return state.previewBy[guid] end
        for _, rec in ipairs(state.preview.party) do
            if rec.guid == guid then return rec end
        end
        return nil
    end
    return state.records[guid]
end
